import AVFoundation
import Foundation
import os.log

// MARK: - Logging Helper

private func Log(_ module: String, _ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    print("[\(timestamp)] [\(module)] \(message)")
}

// MARK: - Audio Packet Recorder

/// 音频包记录器 - 用于调试和音质分析
private class AudioPacketRecorder {
    private var uplinkPackets: [Data] = []
    private var downlinkPackets: [Data] = []
    private var uplinkTimestamps: [Date] = []
    private var downlinkTimestamps: [Date] = []
    private let maxPackets = 500  // 最多保存 500 个包 (10秒)

    func recordUplink(_ data: Data) {
        uplinkPackets.append(data)
        uplinkTimestamps.append(Date())
        if uplinkPackets.count > maxPackets {
            uplinkPackets.removeFirst()
            uplinkTimestamps.removeFirst()
        }
    }

    func recordDownlink(_ data: Data) {
        downlinkPackets.append(data)
        downlinkTimestamps.append(Date())
        if downlinkPackets.count > maxPackets {
            downlinkPackets.removeFirst()
            downlinkTimestamps.removeFirst()
        }
    }

    func saveToFile() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = formatter.string(from: Date())

        // 保存上行 PCM
        if !uplinkPackets.isEmpty {
            let uplinkPath = "\(documentsPath)/uplink_\(dateStr).pcm"
            let combined = uplinkPackets.reduce(Data()) { $0 + $1 }
            try? combined.write(to: URL(fileURLWithPath: uplinkPath))
            Log("AudioRecorder", "Saved uplink: \(uplinkPackets.count) frames to \(uplinkPath)")
        }

        // 保存下行 PCM
        if !downlinkPackets.isEmpty {
            let downlinkPath = "\(documentsPath)/downlink_\(dateStr).pcm"
            let combined = downlinkPackets.reduce(Data()) { $0 + $1 }
            try? combined.write(to: URL(fileURLWithPath: downlinkPath))
            Log("AudioRecorder", "Saved downlink: \(downlinkPackets.count) frames to \(downlinkPath)")
        }

        // 保存时间戳信息
        let infoPath = "\(documentsPath)/audio_info_\(dateStr).txt"
        var info = "Uplink frames: \(uplinkPackets.count)\n"
        info += "Downlink frames: \(downlinkPackets.count)\n\n"

        if uplinkTimestamps.count > 1 {
            info += "Uplink intervals (ms):\n"
            for i in 1..<min(uplinkTimestamps.count, 10) {
                let interval = uplinkTimestamps[i].timeIntervalSince(uplinkTimestamps[i-1]) * 1000
                info += "  Frame \(i): \(String(format: "%.2f", interval))ms\n"
            }
        }

        if downlinkTimestamps.count > 1 {
            info += "\nDownlink intervals (ms):\n"
            for i in 1..<min(downlinkTimestamps.count, 10) {
                let interval = downlinkTimestamps[i].timeIntervalSince(downlinkTimestamps[i-1]) * 1000
                info += "  Frame \(i): \(String(format: "%.2f", interval))ms\n"
            }
        }

        try? info.write(to: URL(fileURLWithPath: infoPath), atomically: true, encoding: .utf8)
        Log("AudioRecorder", "Saved info to \(infoPath)")

        print("=================================================")
        print("📁 Audio files saved to Documents folder:")
        print("   \(documentsPath)")
        print("   Use iTunes/File sharing to retrieve")
        print("=================================================")
    }

    func clear() {
        uplinkPackets.removeAll()
        downlinkPackets.removeAll()
        uplinkTimestamps.removeAll()
        downlinkTimestamps.removeAll()
    }
}

// MARK: - Audio Pipeline Manager

/// 音频流水线管理器
///
/// 协调录音、播放、AMR 编解码的完整音频流水线。
///
/// ## 上行流程 (发送)
/// ```
/// AVAudioEngine (44.1k) → AudioResampler (8k) → PcmFrameBuffer (320B)
///     → AmrNbEncoder (32B) → Delegate.didEncodeAmrFrame
/// ```
///
/// ## 下行流程 (接收)
/// ```
/// feedDownlinkAmr(32B) → AmrNbDecoder (320B) → AVAudioPlayerNode
///     → Delegate.didDecodeDownlinkPcm
/// ```
@MainActor
final class AudioPipelineManager: AudioPipelineProtocol {

    // MARK: - Constants

    private enum Constants {
        static let audioBufferSize: AVAudioFrameCount = 1024
        static let frameDurationNs: UInt64 = 20_000_000
        static let playbackIntervalMs: UInt64 = 20  // 按 20ms 固定间隔播放
        static let maxPlaybackQueueFrames: Int = 50  // 增加缓冲区大小
        static let minQueueFramesBeforePlay: Int = 5   // 最小缓冲帧数再开始播放
    }

    // MARK: - Audio Processing Configuration

    /// 音频处理配置
    struct AudioProcessingConfig {
        /// 是否启用 AEC (声学回声消除) - iOS voiceChat 模式自动启用
        static var aecEnabled: Bool = true

        /// 是否启用 AGC (自动增益控制) - iOS 系统自动处理
        static var agcEnabled: Bool = true

        /// 是否启用 ANS (噪声抑制) - iOS 系统自动处理
        static var ansEnabled: Bool = true

        /// 播放增益倍数 (1.0 - 3.0，过高会导致失真)
        static var playbackGain: Float = 2.0

        /// 录音增益倍数 (1.0 - 2.0)
        static var recordingGain: Float = 1.2

        /// 是否启用线性插值（改善音质）
        static var useLinearInterpolation: Bool = true
    }

    // MARK: - Properties

    /// 代理
    weak var delegate: AudioPipelineDelegate?

    /// 音频引擎
    private let audioEngine = AVAudioEngine()

    /// 播放节点
    private let playerNode = AVAudioPlayerNode()

    /// 重采样器
    private let resampler = AudioResampler()

    /// AMR 编码器
    private let amrEncoder = AmrNbEncoder(dtx: false)

    /// AMR 解码器
    private let amrDecoder = AmrNbDecoder()

    /// 上行 PCM 帧缓冲区
    private var uplinkFrameBuffer = PcmFrameBuffer()

    /// 下行 PCM 播放队列
    private var playbackQueue: Data = Data()

    /// 播放队列锁
    private let playbackLock = NSLock()

    /// 音频包记录器（用于调试）
    private let packetRecorder = AudioPacketRecorder()

    /// 是否记录音频包（用于调试）
    private(set) var isRecordingPackets: Bool = false

    /// 是否正在录音
    private(set) var isRecording = false

    /// 是否正在播放
    private(set) var isPlaying = false

    /// 当前音频模式
    private(set) var currentMode: AudioMode = .earpiece

    /// AMR 解码后的目标格式: 8kHz, 16bit, Mono
    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: TargetAudioFormat.sampleRate,
            channels: TargetAudioFormat.channels,
            interleaved: true
        )!
    }()

    /// 播放格式: 48kHz, 16bit, Mono (与 AudioSession 匹配)
    private lazy var playbackFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000.0,
            channels: 1,
            interleaved: true
        )!
    }()

    /// 播放增益 (从配置读取)
    private var playbackGain: Float {
        get { AudioProcessingConfig.playbackGain }
        set { AudioProcessingConfig.playbackGain = newValue }
    }

    /// 播放定时器
    private var playbackTimer: Timer?

    /// 调试定时器 - 用于检查音频引擎状态
    private var debugCheckTimer: Timer?

    /// 播放状态监控定时器
    private var playbackMonitorTimer: Timer?

    private var encodeFrameCount = 0
    private var decodeFrameCount = 0
    private var resampleCount = 0

    /// 首帧播放标记
    private var firstFrameScheduled = false

    // MARK: - Initialization

    init() {
        setupAudioEngine()
        Log("AudioPipeline", "Initialized")
        Log("AudioPipeline", "  - AEC: \(AudioProcessingConfig.aecEnabled ? "ON" : "OFF") (iOS voiceChat auto-enables)")
        Log("AudioPipeline", "  - AGC: \(AudioProcessingConfig.agcEnabled ? "ON" : "OFF") (iOS system auto)")
        Log("AudioPipeline", "  - ANS: \(AudioProcessingConfig.ansEnabled ? "ON" : "OFF") (iOS system auto)")
        Log("AudioPipeline", "  - Playback Gain: \(AudioProcessingConfig.playbackGain)x")
        Log("AudioPipeline", "  - Recording Gain: \(AudioProcessingConfig.recordingGain)x")
    }

    deinit {
        // cleanup() is @MainActor-isolated, run on main actor
        Task { @MainActor in
            cleanup()
        }
    }

    // MARK: - Setup

    /// 配置音频引擎
    private func setupAudioEngine() {
        // 附加播放节点
        audioEngine.attach(playerNode)

        // 连接播放节点到输出 (使用 48kHz 播放格式，与 AudioSession 匹配)
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(playerNode, to: mainMixer, format: playbackFormat)

        // 设置播放增益
        playerNode.volume = playbackGain
        mainMixer.outputVolume = 1.0

        Log("AudioPipeline", "Engine configured (playback gain: \(playbackGain)x)")
    }

    /// 配置音频会话
    ///
    /// 音频处理功能说明:
    /// - AEC (声学回声消除): iOS voiceChat 模式自动启用
    /// - AGC (自动增益控制): iOS 系统自动处理
    /// - ANS (噪声抑制): iOS 系统自动处理
    ///
    /// 注意: iOS 不提供直接控制这些功能的开关，系统会根据 mode 和设备自动优化
    private func configureAudioSession(mode: AudioMode) throws {
        let session = AVAudioSession.sharedInstance()

        Log("AudioPipeline", "Configuring session for \(mode)...")

        // 根据模式选择不同的配置
        switch mode {
        case .earpiece:
            // 听筒模式：voiceChat 启用 AEC/AGC/ANS
            // .mixWithOthers: 允许与其他音频混合
            // .duckOthers: 降低其他音频音量
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .mixWithOthers
            ])
            try session.overrideOutputAudioPort(.none)  // 使用听筒

        case .speaker:
            // 扬声器模式：强制使用扬声器
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .mixWithOthers
            ])
            try session.overrideOutputAudioPort(.speaker)
        }

        // 设置首选采样率 (48kHz 支持更好的音频处理效果)
        try session.setPreferredSampleRate(48000)

        // 设置缓冲区时长
        // 设置为 20ms (0.02) 以匹配 AMR 帧时长，可能改善 tap 回调稳定性
        // 注意: 这只是"首选"值，系统可能不严格遵循
        try session.setPreferredIOBufferDuration(0.02)

        // 设置首选输入输出通道数
        try session.setPreferredInputNumberOfChannels(1)
        try session.setPreferredOutputNumberOfChannels(1)

        // 激活音频会话
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        Log("AudioPipeline", "Session configured: \(mode)")
        Log("AudioPipeline", "  - Mode: \(session.mode.rawValue) (voiceChat enables AEC/AGC/ANS)")
        Log("AudioPipeline", "  - SampleRate: \(session.sampleRate)Hz")
        Log("AudioPipeline", "  - InputChannels: \(session.inputNumberOfChannels)")
        Log("AudioPipeline", "  - OutputChannels: \(session.outputNumberOfChannels)")
        Log("AudioPipeline", "  - Route: \(session.currentRoute.outputs.map { $0.portName }.joined(separator: ", "))")
        Log("AudioPipeline", "  - OutputVolume: \(session.outputVolume)")
    }

    // MARK: - Recording (Uplink)

    /// 开始录音
    func startRecording() async -> Result<Void, Error> {
        guard !isRecording else {
            return .success(())
        }

        do {
            // 检查麦克风权限
            let session = AVAudioSession.sharedInstance()
            if session.recordPermission != .granted {
                return .failure(AudioPipelineError.permissionDenied)
            }

            // 配置音频会话
            try configureAudioSession(mode: currentMode)

            // 获取输入节点
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            Log("AudioPipeline", "Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, \(inputFormat.commonFormat.rawValue)")

            // 安装 tap 捕获音频（使用 nil 让系统自动选择格式）
            var tapCallCount = 0
            inputNode.installTap(
                onBus: 0,
                bufferSize: Constants.audioBufferSize,
                format: nil  // 使用 nil 让系统自动选择
            ) { [weak self] buffer, _ in
                tapCallCount += 1
                if tapCallCount == 1 {
                    Log("AudioPipeline", "Audio capture started")
                }

                let bufferCopy = buffer.copy() as? AVAudioPCMBuffer
                Task { @MainActor [weak self] in
                    guard let bufferCopy = bufferCopy else { return }
                    self?.processUplinkBuffer(bufferCopy)
                }
            }

            // 启动音频引擎
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            isRecording = true
            encodeFrameCount = 0
            resampleCount = 0
            Log("AudioPipeline", "Recording started")

            startDebugTimer()

            return .success(())

        } catch {
            Log("AudioPipeline", "Failed to start recording: \(error)")
            return .failure(error)
        }
    }

    /// 停止录音
    func stopRecording() async -> Result<Void, Error> {
        guard isRecording else {
            return .success(())
        }

        stopDebugTimer()

        do {
            audioEngine.inputNode.removeTap(onBus: 0)

            if audioEngine.isRunning {
                audioEngine.stop()
            }

            isRecording = false
            Log("AudioPipeline", "Recording stopped (encoded: \(encodeFrameCount) frames)")

            uplinkFrameBuffer.clear()

            try AVAudioSession.sharedInstance().setActive(false)

            return .success(())

        } catch let error {
            print("[AudioPipeline] ❌ Failed to stop recording: \(error)")
            return .failure(error)
        }
    }

    // MARK: - Debug Timer

    /// 启动调试定时器 - 每秒检查音频引擎状态
    private func startDebugTimer() {
        stopDebugTimer()

        var checkCount = 0
        debugCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            checkCount += 1
            let session = AVAudioSession.sharedInstance()

            print("[AudioPipeline-DEBUG] 🔍 Check #\(checkCount):")
            print("[AudioPipeline-DEBUG]    - audioEngine.isRunning: \(self.audioEngine.isRunning)")
            print("[AudioPipeline-DEBUG]    - isRecording: \(self.isRecording)")
            print("[AudioPipeline-DEBUG]    - encodeFrameCount: \(self.encodeFrameCount)")
            print("[AudioPipeline-DEBUG]    - resampleCount: \(self.resampleCount)")
            print("[AudioPipeline-DEBUG]    - session.isInputAvailable: \(session.isInputAvailable)")
            print("[AudioPipeline-DEBUG]    - session.category: \(session.category)")

            // 如果5秒后还没有任何音频数据，打印警告
            if checkCount == 5 && self.encodeFrameCount == 0 {
                print("[AudioPipeline-DEBUG] ⚠️⚠️⚠️ WARNING: No audio data after 5 seconds! ⚠️⚠️⚠️")
                print("[AudioPipeline-DEBUG]    - Check microphone permissions")
                print("[AudioPipeline-DEBUG]    - Check if another app is using the microphone")
                print("[AudioPipeline-DEBUG]    - Try testing on a physical device (not simulator)")
            }
        }

        debugCheckTimer?.tolerance = 0.1
    }

    /// 停止调试定时器
    private func stopDebugTimer() {
        debugCheckTimer?.invalidate()
        debugCheckTimer = nil
    }

    /// 处理上行音频缓冲区
    private var lastUplinkEncodeTime: Date?

    private func processUplinkBuffer(_ buffer: AVAudioPCMBuffer) {
        resampleCount += 1
        if resampleCount == 1 {
            Log("AudioPipeline", "First audio buffer received")
        }

        // 1. 重采样到 8kHz
        guard let resampledData = resampler.resample(buffer: buffer) else {
            return
        }

        // 2. 添加到帧缓冲区
        uplinkFrameBuffer.append(resampledData)

        // 3. 提取完整的 320 字节帧并编码
        while let pcmFrame = uplinkFrameBuffer.popFrame() {
            let now = Date()

            // 计算编码间隔
            if let lastTime = lastUplinkEncodeTime {
                let interval = now.timeIntervalSince(lastTime) * 1000
                // 打印前 20 帧的间隔，或间隔异常时
                if encodeFrameCount <= 20 || abs(interval - 20) > 10 {
                    Log("AudioPipeline", "UL encode #\(encodeFrameCount), interval: \(String(format: "%.1f", interval))ms")
                }
            }
            lastUplinkEncodeTime = now

            // 记录音频包（如果启用）
            if isRecordingPackets {
                packetRecorder.recordUplink(pcmFrame)
            }

            // 3a. 回调上行 PCM (用于录音)
            delegate?.audioPipeline(self, didCaptureUplinkPcm: pcmFrame)

            // 3b. 编码为 AMR
            let amrFrame = amrEncoder.encode(pcmData: pcmFrame)

            guard !amrFrame.isEmpty else {
                continue
            }

            encodeFrameCount += 1
            if encodeFrameCount % 100 == 0 {
                Log("AudioPipeline", "Encoded \(encodeFrameCount) frames")
            }

            // 3c. 回调 AMR 帧 (发送给设备)
            delegate?.audioPipeline(self, didEncodeAmrFrame: amrFrame)
        }
    }

    // MARK: - Playback (Downlink)

    /// 开始播放
    func startPlaying() async -> Result<Void, Error> {
        guard !isPlaying else {
            return .success(())
        }

        do {
            // 只有在 audioEngine 没有运行时才配置音频会话
            if !audioEngine.isRunning {
                try configureAudioSession(mode: currentMode)
            }

            // 启动音频引擎
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            // 启动播放节点并设置增益
            playerNode.play()
            playerNode.volume = playbackGain

            // 启动播放定时器
            startPlaybackTimer()

            isPlaying = true
            firstFrameScheduled = false
            Log("AudioPipeline", "Playback started (gain: \(playbackGain)x)")

            return .success(())

        } catch {
            Log("AudioPipeline", "Failed to start playback: \(error)")
            return .failure(error)
        }
    }

    /// 停止播放
    func stopPlaying() async -> Result<Void, Error> {
        guard isPlaying else {
            return .success(())
        }

        // 停止播放定时器
        stopPlaybackTimer()

        // 停止播放节点
        playerNode.stop()

        // 清空播放队列
        playbackLock.lock()
        playbackQueue.removeAll()
        playbackLock.unlock()

        isPlaying = false
        print("[AudioPipelineManager] ✅ Playback stopped")

        return .success(())
    }

    /// 输入下行 AMR 帧进行解码播放
    @MainActor
    private var lastDownlinkTime: Date?

    func feedDownlinkAmr(_ amrData: Data) {
        let now = Date()

        // 计算与上一帧的时间间隔
        if let lastTime = lastDownlinkTime {
            let interval = now.timeIntervalSince(lastTime) * 1000  // 转换为毫秒
            // 打印前 20 帧的间隔，或间隔异常时
            if decodeFrameCount <= 20 || abs(interval - 20) > 10 {
                Log("AudioPipeline", "DL frame #\(decodeFrameCount), interval: \(String(format: "%.1f", interval))ms")
            }
        }
        lastDownlinkTime = now

        decodeFrameCount += 1

        // 1. AMR → PCM 解码
        let pcmData = amrDecoder.decode(amrData: amrData)

        guard !pcmData.isEmpty else {
            if decodeFrameCount <= 5 {
                Log("AudioPipeline", "AMR decoding failed, empty PCM (frame #\(decodeFrameCount))")
            }
            return
        }

        if decodeFrameCount == 1 {
            Log("AudioPipeline", "First AMR decoded, size: \(pcmData.count)B")
        } else if decodeFrameCount % 100 == 0 {
            Log("AudioPipeline", "Decoded \(decodeFrameCount) frames")
        }

        // 记录音频包（如果启用）
        if isRecordingPackets {
            packetRecorder.recordDownlink(pcmData)
        }

        // 2. 回调下行 PCM (用于录音)
        delegate?.audioPipeline(self, didDecodeDownlinkPcm: pcmData)

        // 3. 添加到播放队列
        playbackLock.lock()
        playbackQueue.append(pcmData)

        // 限制队列大小
        let maxQueueSize = Constants.maxPlaybackQueueFrames * TargetAudioFormat.bytesPerFrame
        if playbackQueue.count > maxQueueSize {
            let excess = playbackQueue.count - maxQueueSize
            playbackQueue.removeFirst(excess)
            print("[AudioPipeline] ⚠️ Playback queue overflow, dropped \(excess) bytes")
        }
        playbackLock.unlock()

        // 确保音频引擎保持运行状态
        if !audioEngine.isRunning {
            print("[AudioPipeline] ⚠️⚠️⚠️ WARNING: audioEngine stopped! Trying to restart...")
            do {
                try audioEngine.start()
                print("[AudioPipeline] ✅ audioEngine restarted")
            } catch {
                print("[AudioPipeline] ❌ Failed to restart audioEngine: \(error)")
            }
        }

        // 确保播放节点保持播放状态
        if !playerNode.isPlaying {
            print("[AudioPipeline] ⚠️⚠️⚠️ WARNING: playerNode stopped! Trying to restart...")
            playerNode.play()
            print("[AudioPipeline] ✅ playerNode restarted")
        }
    }

    /// 启动播放定时器
    private func startPlaybackTimer() {
        stopPlaybackTimer()

        // 创建一个 RunLoop 定时器（不依赖 Task，更可靠）
        playbackTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(Constants.playbackIntervalMs) / 1000.0,
            repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            // 直接在主线程调用，不使用 Task
            if Thread.isMainThread {
                self.playNextFrame()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.playNextFrame()
                }
            }
        }

        // 添加状态监控定时器 - 每 100ms 检查一次
        playbackMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if !self.isPlaying {
                timer.invalidate()
                return
            }

            // 检查 audioEngine 状态，如果停止了尝试重启
            if !self.audioEngine.isRunning {
                print("[AudioPipeline-Monitor] ⚠️ audioEngine stopped! Restarting...")
                do {
                    try self.audioEngine.start()
                    print("[AudioPipeline-Monitor] ✅ audioEngine restarted, isRunning: \(self.audioEngine.isRunning)")
                } catch {
                    print("[AudioPipeline-Monitor] ❌ Failed to restart: \(error)")
                }
            }
        }

        playbackTimer?.tolerance = 0.001
        playbackMonitorTimer?.tolerance = 0.05
    }

    /// 停止播放定时器
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil

        playbackMonitorTimer?.invalidate()
        playbackMonitorTimer = nil
    }

    /// 播放下一帧（按固定 20ms 间隔）
    private var playbackFrameCount = 0

    private func playNextFrame() {
        guard isPlaying else { return }

        playbackLock.lock()
        let queueSize = playbackQueue.count
        let framesAvailable = queueSize / TargetAudioFormat.bytesPerFrame

        // 队列为空，跳过此帧（静音）
        guard playbackQueue.count >= TargetAudioFormat.bytesPerFrame else {
            playbackLock.unlock()
            if playbackFrameCount > 0 && playbackFrameCount % 50 == 0 {
                Log("AudioPipeline", "Queue underrun at frame #\(playbackFrameCount), frames: \(framesAvailable)")
            }
            return
        }

        // 提取一帧
        let frame = playbackQueue.prefix(TargetAudioFormat.bytesPerFrame)
        playbackQueue.removeFirst(TargetAudioFormat.bytesPerFrame)
        playbackLock.unlock()

        playbackFrameCount += 1
        if playbackFrameCount == 1 {
            Log("AudioPipeline", "First frame playing (gain: \(playbackGain)x)")
        } else if playbackFrameCount % 100 == 0 {
            Log("AudioPipeline", "Playing frame #\(playbackFrameCount), queue: \(framesAvailable)")
        }

        // 创建音频缓冲区并播放
        playPcmData(frame)
    }

    /// 播放 PCM 数据 (8kHz PCM → 48kHz 转换后播放)
    private func playPcmData(_ pcmData: Data) {
        // 确保音频引擎在运行
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                Log("AudioPipeline", "Failed to restart audioEngine: \(error)")
                return
            }
        }

        // 确保播放节点已启动
        if !playerNode.isPlaying {
            playerNode.play()
        }

        // 将 8kHz PCM 转换为 48kHz PCM 并播放
        guard let buffer48kHz = convertToPlaybackFormat(pcmData: pcmData) else {
            return
        }

        playerNode.scheduleBuffer(buffer48kHz, at: nil, options: .interrupts)

        if !firstFrameScheduled {
            firstFrameScheduled = true
            Log("AudioPipeline", "First frame scheduled (\(buffer48kHz.frameLength) samples, gain: \(playbackGain)x)")
        }
    }

    /// 将 8kHz PCM 转换为 48kHz PCM，并应用音量增益
    ///
    /// 使用线性插值来改善音频质量，避免"阶梯感"
    private func convertToPlaybackFormat(pcmData: Data) -> AVAudioPCMBuffer? {
        // 输入: 8kHz, 16-bit, mono (320 bytes = 160 samples)
        // 输出: 48kHz, 16-bit, mono (960 samples)

        let inputSamples = pcmData.count / 2  // 16-bit = 2 bytes per sample
        let outputSamples = inputSamples * 6  // 8kHz → 48kHz = 6x

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(outputSamples)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(outputSamples)

        // 线性插值 + 软增益（避免硬削波）
        let gain = playbackGain
        pcmData.withUnsafeBytes { src in
            guard let srcPtr = src.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let dstPtr = buffer.int16ChannelData![0]

            for i in 0..<inputSamples {
                let currentSample = Float(srcPtr[i])

                // 线性插值：每个输入样本产生 6 个输出样本
                for j in 0..<6 {
                    let t = Float(j) / 6.0

                    // 获取下一个样本（用于插值）
                    let nextSample: Float
                    if i < inputSamples - 1 {
                        nextSample = Float(srcPtr[i + 1])
                    } else {
                        nextSample = currentSample
                    }

                    // 线性插值
                    let interpolated = currentSample * (1.0 - t) + nextSample * t

                    // 应用软增益（使用 tanh 避免硬削波）
                    let gained = interpolated * gain
                    let softClipped = tanh(gained / 32768.0) * 32767.0

                    dstPtr[i * 6 + j] = Int16(max(-32768, min(32767, softClipped)))
                }
            }
        }

        return buffer
    }

    /// 从 Data 创建 AVAudioPCMBuffer
    private func createPcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / 2)  // 16-bit = 2 bytes per frame

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(buffer.int16ChannelData![0], base, data.count)
        }

        return buffer
    }

    // MARK: - Audio Mode

    /// 设置播放增益 (1.0 - 4.0)
    func setPlaybackGain(_ gain: Float) {
        let clampedGain = max(1.0, min(4.0, gain))
        AudioProcessingConfig.playbackGain = clampedGain
        playerNode.volume = clampedGain
        Log("AudioPipeline", "Playback gain set to \(clampedGain)x")
    }

    /// 设置录音增益 (1.0 - 4.0)
    func setRecordingGain(_ gain: Float) {
        let clampedGain = max(1.0, min(4.0, gain))
        AudioProcessingConfig.recordingGain = clampedGain
        Log("AudioPipeline", "Recording gain set to \(clampedGain)x")
    }

    /// 获取当前音频处理配置
    func getAudioProcessingConfig() -> (aec: Bool, agc: Bool, ans: Bool, playbackGain: Float, recordingGain: Float) {
        return (
            AudioProcessingConfig.aecEnabled,
            AudioProcessingConfig.agcEnabled,
            AudioProcessingConfig.ansEnabled,
            AudioProcessingConfig.playbackGain,
            AudioProcessingConfig.recordingGain
        )
    }

    // MARK: - Audio Packet Recording (Debug)

    /// 开始记录音频包（用于调试音质）
    func startPacketRecording() {
        isRecordingPackets = true
        packetRecorder.clear()
        Log("AudioPipeline", "Packet recording STARTED")
    }

    /// 停止记录音频包
    func stopPacketRecording() {
        isRecordingPackets = false
        Log("AudioPipeline", "Packet recording STOPPED")
    }

    /// 保存记录的音频包到文件
    func saveRecordedPackets() {
        packetRecorder.saveToFile()
    }

    /// 获取记录状态
    func isRecordingPacketsActive() -> Bool {
        return isRecordingPackets
    }

    /// 设置音频模式
    func setAudioMode(_ mode: AudioMode) async -> Result<Void, Error> {
        guard mode != currentMode else {
            return .success(())
        }

        do {
            let wasRecording = isRecording
            let wasPlaying = isPlaying

            // 需要先停止音频
            if wasRecording {
                _ = await stopRecording()
            }
            if wasPlaying {
                _ = await stopPlaying()
            }

            // 更新模式
            currentMode = mode

            // 重新配置音频会话
            try configureAudioSession(mode: mode)

            // 重新启动音频
            if wasRecording {
                _ = await startRecording()
            }
            if wasPlaying {
                _ = await startPlaying()
            }

            print("[AudioPipelineManager] ✅ Audio mode changed to \(mode)")
            return .success(())

        } catch {
            print("[AudioPipelineManager] ❌ Failed to set audio mode: \(error)")
            return .failure(error)
        }
    }

    // MARK: - Cleanup

    /// 清理资源
    private func cleanup() {
        stopPlaybackTimer()
        stopDebugTimer()

        if isRecording {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        playerNode.stop()
        audioEngine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("[AudioPipelineManager] ⚠️ Failed to deactivate audio session: \(error)")
        }

        print("[AudioPipelineManager] Cleaned up")
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension AudioPipelineManager {

    /// 获取当前播放队列大小 (帧数)
    var playbackQueueFrames: Int {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        return playbackQueue.count / TargetAudioFormat.bytesPerFrame
    }

    /// 打印状态
    func printStatus() {
        print("[AudioPipelineManager] Status:")
        print("  - isRecording: \(isRecording)")
        print("  - isPlaying: \(isPlaying)")
        print("  - currentMode: \(currentMode)")
        print("  - uplinkBuffer: \(uplinkFrameBuffer.count) bytes (\(uplinkFrameBuffer.availableFrames) frames)")
        print("  - playbackQueue: \(playbackQueueFrames) frames")
        print("  - audioEngine.isRunning: \(audioEngine.isRunning)")
    }
}
#endif

// MARK: - Audio Pipeline Error

enum AudioPipelineError: LocalizedError {
    case permissionDenied
    case notRecording
    case notPlaying
    case resamplingFailed
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "麦克风权限被拒绝"
        case .notRecording:
            return "未在录音状态"
        case .notPlaying:
            return "未在播放状态"
        case .resamplingFailed:
            return "音频重采样失败"
        case .encodingFailed:
            return "AMR 编码失败"
        case .decodingFailed:
            return "AMR 解码失败"
        }
    }
}
