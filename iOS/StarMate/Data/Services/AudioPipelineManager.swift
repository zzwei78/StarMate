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
/// AudioQueue (48k) → AudioResampler (8k) → PcmFrameBuffer (320B)
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
        static let playbackIntervalMs: UInt64 = 100  // 100ms 间隔
        static let framesPerPlayback: Int = 5   // 每次播放 5 帧 = 100ms (与间隔匹配)
        static let maxPlaybackQueueFrames: Int = 50  // 最大缓冲 50 帧 = 1秒
        static let minQueueFramesBeforePlay: Int = 10   // 最小缓冲 10 帧 = 200ms 再开始播放
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

    /// 音频引擎 (仅用于播放)
    private let audioEngine = AVAudioEngine()

    /// 播放节点
    private let playerNode = AVAudioPlayerNode()

    /// AudioQueue (用于录音)
    private var audioQueue: AudioQueueRef?
    private var audioQueueFormat: AudioStreamBasicDescription?
    private var audioQueueCallbackCount = 0
    private var lastAudioQueueCallbackTime: Date?

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

    /// 配置音频引擎（仅用于播放）
    private func setupAudioEngine() {
        // 附加播放节点
        audioEngine.attach(playerNode)

        // 使用 8kHz 格式连接播放节点
        let mainMixer = audioEngine.mainMixerNode

        // 创建 8kHz 播放格式
        guard let playbackFormat8kHz = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8000.0,
            channels: 1,
            interleaved: true
        ) else {
            Log("AudioPipeline", "Failed to create 8kHz playback format")
            return
        }

        audioEngine.connect(playerNode, to: mainMixer, format: playbackFormat8kHz)

        // 设置播放增益
        playerNode.volume = playbackGain
        mainMixer.outputVolume = 1.0

        Log("AudioPipeline", "Player engine configured (8kHz direct playback)")
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
        // 尝试更小的值 (5ms) 以获得更频繁的回调
        // 注意: 系统可能会根据硬件调整实际值
        try session.setPreferredIOBufferDuration(0.005)  // 5ms

        // 设置首选输入输出通道数
        try session.setPreferredInputNumberOfChannels(1)
        try session.setPreferredOutputNumberOfChannels(1)

        // 激活音频会话
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        Log("AudioPipeline", "Session configured: \(mode)")
        Log("AudioPipeline", "  - Mode: \(session.mode.rawValue) (voiceChat enables AEC/AGC/ANS)")
        Log("AudioPipeline", "  - SampleRate: \(session.sampleRate)Hz")
        Log("AudioPipeline", "  - IOBufferDuration: \(session.ioBufferDuration * 1000)ms (requested: 5ms)")
        Log("AudioPipeline", "  - InputChannels: \(session.inputNumberOfChannels)")
        Log("AudioPipeline", "  - OutputChannels: \(session.outputNumberOfChannels)")
        Log("AudioPipeline", "  - Route: \(session.currentRoute.outputs.map { $0.portName }.joined(separator: ", "))")
        Log("AudioPipeline", "  - OutputVolume: \(session.outputVolume)")
    }

    // MARK: - Recording (Uplink)

    /// 开始录音 - 使用 AudioQueue 实现稳定的 20ms 回调
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

            // 设置音频格式描述: 48kHz, 16bit, Mono
            var streamFormat = AudioStreamBasicDescription(
                mSampleRate: 48000,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: 2,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            audioQueueFormat = streamFormat

            Log("AudioPipeline", "Creating AudioQueue: 48000Hz, 16bit, Mono")

            // 创建上下文，传递 self 引用
            let context = Unmanaged.passUnretained(self).toOpaque()
            var queue: AudioQueueRef?

            // AudioQueue 回调函数
            let audioQueueInputCallback: AudioQueueInputCallback = { (
                userData: UnsafeMutableRawPointer?,
                queue: AudioQueueRef,
                buffer: AudioQueueBufferRef,
                startTime: UnsafePointer<AudioTimeStamp>,
                numFrames: UInt32,
                packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
            ) in
                guard let userData = userData else { return }

                // 从上下文中恢复 AudioPipelineManager 实例
                let audioPipeline = Unmanaged<AudioPipelineManager>.fromOpaque(userData).takeUnretainedValue()

                // 在单独的线程处理回调
                audioPipeline.handleAudioQueueCallback(buffer: buffer)
            }

            let status = AudioQueueNewInput(
                &streamFormat,
                audioQueueInputCallback,
                context,
                nil,
                nil,
                0,
                &queue
            )

            guard status == noErr, let queue = queue else {
                return .failure(AudioPipelineError.recordingFailed)
            }

            audioQueue = queue

            // 分配 3 个缓冲区，每个 480 帧 = 10ms @ 48kHz
            // 使用更小的缓冲区以获得更频繁的回调
            let framesPerBuffer: UInt32 = 480  // 10ms @ 48kHz
            let bufferSizeInBytes = framesPerBuffer * 2  // 480 frames * 2 bytes (16-bit)

            Log("AudioPipeline", "Allocating buffers: \(framesPerBuffer) frames = 10ms")

            for i in 0..<3 {
                var buffer: AudioQueueBufferRef?
                let allocStatus = AudioQueueAllocateBuffer(
                    queue,
                    bufferSizeInBytes,
                    &buffer
                )
                if allocStatus == noErr, let buffer = buffer {
                    // 注意: 不设置 mAudioDataByteSize，让 AudioQueue 填充实际大小
                    AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
                    Log("AudioPipeline", "  Buffer #\(i) allocated: \(bufferSizeInBytes)B")
                } else {
                    Log("AudioPipeline", "  Failed to allocate buffer #\(i)")
                }
            }

            // 启动音频队列
            let startStatus = AudioQueueStart(queue, nil)
            if startStatus != noErr {
                return .failure(AudioPipelineError.recordingFailed)
            }

            isRecording = true
            encodeFrameCount = 0
            resampleCount = 0
            audioQueueCallbackCount = 0
            lastAudioQueueCallbackTime = nil
            Log("AudioPipeline", "AudioQueue recording started (20ms callbacks expected)")

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

        // 停止并释放音频队列
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            audioQueue = nil
        }

        audioQueueFormat = nil

        isRecording = false
        Log("AudioPipeline", "AudioQueue recording stopped (encoded: \(encodeFrameCount) frames)")

        uplinkFrameBuffer.clear()

        // 停用音频会话
        try? AVAudioSession.sharedInstance().setActive(false)

        return .success(())
    }

    /// AudioQueue 回调处理
    private func handleAudioQueueCallback(buffer: AudioQueueBufferRef) {
        guard let audioQueue = audioQueue else { return }

        let now = Date()
        audioQueueCallbackCount += 1

        // 从 AudioQueue 缓冲区读取音频数据
        let audioBuffer = buffer.pointee
        let frameCount = UInt32(audioBuffer.mAudioDataByteSize / 2)  // 16-bit = 2 bytes per frame
        guard frameCount > 0 else { return }

        // 打印回调间隔和帧数（前 30 次）
        if audioQueueCallbackCount <= 30 {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = formatter.string(from: now)

            var intervalStr = ""
            if let lastTime = lastAudioQueueCallbackTime {
                let interval = now.timeIntervalSince(lastTime) * 1000
                intervalStr = ", interval: \(String(format: "%.1f", interval))ms"
            }
            print("[\(timestamp)] [AudioQueue] Callback #\(audioQueueCallbackCount), frames: \(frameCount)\(intervalStr)")
        }
        lastAudioQueueCallbackTime = now

        // 创建 AVAudioPCMBuffer
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        ) else {
            return
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return
        }

        pcmBuffer.frameLength = frameCount

        // 复制音频数据从 AudioQueue 缓冲区到 AVAudioPCMBuffer
        let srcPtr = audioBuffer.mAudioData.assumingMemoryBound(to: Int16.self)
        pcmBuffer.int16ChannelData![0].update(from: srcPtr, count: Int(frameCount))

        // 调用现有的处理函数（保持兼容）
        processUplinkBuffer(pcmBuffer)

        // 重新入队缓冲区以继续录音
        AudioQueueEnqueueBuffer(audioQueue, buffer, 0, nil)
    }

    // MARK: - Processing

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
                // if encodeFrameCount <= 20 || abs(interval - 20) > 10 {
                //     Log("AudioPipeline", "UL encode #\(encodeFrameCount), interval: \(String(format: "%.1f", interval))ms")
                // }
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
            // if decodeFrameCount <= 20 || abs(interval - 20) > 10 {
            //     Log("AudioPipeline", "DL frame #\(decodeFrameCount), interval: \(String(format: "%.1f", interval))ms")
            // }
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
        let queueFrames = playbackQueue.count / TargetAudioFormat.bytesPerFrame

        // 限制队列大小
        let maxQueueSize = Constants.maxPlaybackQueueFrames * TargetAudioFormat.bytesPerFrame
        if playbackQueue.count > maxQueueSize {
            let excess = playbackQueue.count - maxQueueSize
            playbackQueue.removeFirst(excess)
            print("[AudioPipeline] ⚠️ Playback queue overflow, dropped \(excess) bytes")
        }
        playbackLock.unlock()

        // 每 50 帧打印缓冲状态
        if decodeFrameCount % 50 == 0 {
            print("[AudioPipeline] 📊 DL buffer: \(queueFrames) frames (\(queueFrames * 20)ms)")
        }

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

        // 队列为空，停止播放（没有信号时不播放）
        guard playbackQueue.count >= TargetAudioFormat.bytesPerFrame else {
            playbackLock.unlock()
            if playerNode.isPlaying {
                playerNode.stop()
                if playbackFrameCount > 0 && playbackFrameCount % 50 == 0 {
                    print("[AudioPipeline] ⚠️ No signal, stopped playback (buffer: \(framesAvailable) frames)")
                }
            }
            return
        }

        // 累积多帧一起播放，减少调度间隙
        let framesToSchedule = min(Constants.framesPerPlayback, framesAvailable)
        let totalBytes = framesToSchedule * TargetAudioFormat.bytesPerFrame
        let framesData = playbackQueue.prefix(totalBytes)
        playbackQueue.removeFirst(totalBytes)
        let remainingFrames = playbackQueue.count / TargetAudioFormat.bytesPerFrame
        playbackLock.unlock()

        playbackFrameCount += framesToSchedule
        if playbackFrameCount <= framesToSchedule {
            print("[AudioPipeline] 🎵 First frame playing (batch: \(framesToSchedule) frames = \(framesToSchedule * 20)ms, buffer: \(remainingFrames) frames)")
        } else if playbackFrameCount % 100 == 0 {
            print("[AudioPipeline] 🎵 Playing frame #\(playbackFrameCount), buffer: \(remainingFrames) frames (\(remainingFrames * 20)ms)")
        }

        // 创建音频缓冲区并播放（一次性调度多帧）
        playPcmData(Data(framesData))
    }

    /// 播放 PCM 数据 (累积多帧后调度，减少间隙)
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

        // 直接创建 8kHz PCM 缓冲区并播放
        guard let buffer = createPcmBuffer(from: pcmData) else {
            return
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)

        if !firstFrameScheduled {
            firstFrameScheduled = true
            Log("AudioPipeline", "First frame scheduled (\(buffer.frameLength) samples at 8kHz)")
        }
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

        // 停止 AudioQueue 录音
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            audioQueue = nil
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
    case recordingFailed

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
        case .recordingFailed:
            return "录音失败"
        }
    }
}
