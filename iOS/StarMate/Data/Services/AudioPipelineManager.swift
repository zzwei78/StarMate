import AVFoundation
import Foundation

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
        static let playbackIntervalMs: UInt64 = 5
        static let maxPlaybackQueueFrames: Int = 30
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

    /// 是否正在录音
    private(set) var isRecording = false

    /// 是否正在播放
    private(set) var isPlaying = false

    /// 当前音频模式
    private(set) var currentMode: AudioMode = .earpiece

    /// 目标格式: 8kHz, 16bit, Mono
    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: TargetAudioFormat.sampleRate,
            channels: TargetAudioFormat.channels,
            interleaved: true
        )!
    }()

    /// 播放定时器
    private var playbackTimer: Timer?

    #if DEBUG
    private var encodeFrameCount = 0
    #endif

    // MARK: - Initialization

    init() {
        setupAudioEngine()
        print("[AudioPipelineManager] Initialized")
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

        // 连接播放节点到输出 (使用目标格式)
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(playerNode, to: mainMixer, format: targetFormat)

        print("[AudioPipeline] ✅ Audio engine configured")
        print("[AudioPipeline]    - Target format: \(TargetAudioFormat.sampleRate)Hz, \(TargetAudioFormat.channels)ch, Int16")
    }

    /// 配置音频会话
    private func configureAudioSession(mode: AudioMode) throws {
        let session = AVAudioSession.sharedInstance()

        print("[AudioPipeline] 🔧 Configuring audio session for \(mode)...")

        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .defaultToSpeaker
        ])

        // 设置首选采样率 (尝试使用硬件原生采样率)
        try session.setPreferredSampleRate(44100)

        // 设置缓冲区时长 (降低延迟)
        try session.setPreferredIOBufferDuration(0.005)

        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // 切换听筒/扬声器
        switch mode {
        case .earpiece:
            try session.overrideOutputAudioPort(.none)  // 使用听筒
        case .speaker:
            try session.overrideOutputAudioPort(.speaker)
        }

        print("[AudioPipeline] ✅ Audio session configured: \(mode)")
        print("[AudioPipeline]    - Category: \(session.category)")
        print("[AudioPipeline]    - SampleRate: \(session.sampleRate)Hz")
        print("[AudioPipeline]    - IOBufferDuration: \(session.ioBufferDuration)s")
    }

    // MARK: - Recording (Uplink)

    /// 开始录音
    func startRecording() async -> Result<Void, Error> {
        guard !isRecording else {
            print("[AudioPipeline] ⚠️ Already recording")
            return .success(())
        }

        do {
            print("[AudioPipeline] 🎤 Starting recording...")

            // 配置音频会话
            try configureAudioSession(mode: currentMode)

            // 启动音频引擎
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            // 获取输入节点
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            print("[AudioPipeline] 📊 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, \(inputFormat.commonFormat)")

            // 安装 tap 捕获音频
            // 注意: tap 回调在实时音频线程上执行，需要调度到主线程
            inputNode.installTap(
                onBus: 0,
                bufferSize: Constants.audioBufferSize,
                format: inputFormat
            ) { [weak self] buffer, _ in
                // 复制缓冲区数据，因为 buffer 在回调返回后可能被重用
                let bufferCopy = buffer.copy() as? AVAudioPCMBuffer
                Task { @MainActor [weak self] in
                    guard let bufferCopy = bufferCopy else { return }
                    self?.processUplinkBuffer(bufferCopy)
                }
            }

            isRecording = true
            print("[AudioPipeline] ✅ Recording started")
            print("[AudioPipeline]    - Buffer size: \(Constants.audioBufferSize) frames")
            print("[AudioPipeline]    - Delegate set: \(delegate != nil)")

            return .success(())

        } catch {
            print("[AudioPipeline] ❌ Failed to start recording: \(error)")
            return .failure(error)
        }
    }

    /// 停止录音
    func stopRecording() async -> Result<Void, Error> {
        guard isRecording else {
            return .success(())
        }

        do {
            // 移除 tap
            audioEngine.inputNode.removeTap(onBus: 0)

            // 停止音频引擎
            if audioEngine.isRunning {
                audioEngine.stop()
            }

            isRecording = false

            // 清空缓冲区
            uplinkFrameBuffer.clear()

            // 停用音频会话
            try AVAudioSession.sharedInstance().setActive(false)

            print("[AudioPipelineManager] ✅ Recording stopped")
            return .success(())

        } catch let error {
            print("[AudioPipelineManager] ❌ Failed to stop recording: \(error)")
            return .failure(error)
        }
    }

    /// 处理上行音频缓冲区
    private func processUplinkBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. 重采样到 8kHz
        guard let resampledData = resampler.resample(buffer: buffer) else {
            return
        }

        // 2. 添加到帧缓冲区
        uplinkFrameBuffer.append(resampledData)

        // 3. 提取完整的 320 字节帧并编码
        while let pcmFrame = uplinkFrameBuffer.popFrame() {
            // 3a. 回调上行 PCM (用于录音)
            delegate?.audioPipeline(self, didCaptureUplinkPcm: pcmFrame)

            // 3b. 编码为 AMR
            let amrFrame = amrEncoder.encode(pcmData: pcmFrame)

            guard !amrFrame.isEmpty else {
                print("[AudioPipeline] ⚠️ AMR encoding failed, empty frame")
                continue
            }

            #if DEBUG
            encodeFrameCount += 1
            if encodeFrameCount % 250 == 0 {  // 每5秒
                print("[AudioPipeline] 🔊 Encoded AMR frames: \(encodeFrameCount), size: \(amrFrame.count)B")
            }
            #endif

            // 3c. 回调 AMR 帧 (发送给设备)
            delegate?.audioPipeline(self, didEncodeAmrFrame: amrFrame)
        }
    }

    // MARK: - Playback (Downlink)

    /// 开始播放
    func startPlaying() async -> Result<Void, Error> {
        guard !isPlaying else {
            print("[AudioPipelineManager] ⚠️ Already playing")
            return .success(())
        }

        do {
            // 确保音频会话已配置
            if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
                try configureAudioSession(mode: currentMode)
            }

            // 启动音频引擎
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            // 启动播放节点
            playerNode.play()

            // 启动播放定时器
            startPlaybackTimer()

            isPlaying = true
            print("[AudioPipelineManager] ✅ Playback started")

            return .success(())

        } catch {
            print("[AudioPipelineManager] ❌ Failed to start playback: \(error)")
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
    func feedDownlinkAmr(_ amrData: Data) {
        // 1. AMR → PCM 解码
        let pcmData = amrDecoder.decode(amrData: amrData)

        guard !pcmData.isEmpty else {
            print("[AudioPipeline] ⚠️ AMR decoding failed, empty PCM")
            return
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
    }

    /// 启动播放定时器
    private func startPlaybackTimer() {
        stopPlaybackTimer()

        playbackTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(Constants.playbackIntervalMs) / 1000.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playNextFrame()
            }
        }

        playbackTimer?.tolerance = 0.001
    }

    /// 停止播放定时器
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// 播放下一帧
    private func playNextFrame() {
        guard isPlaying else { return }

        playbackLock.lock()
        guard playbackQueue.count >= TargetAudioFormat.bytesPerFrame else {
            playbackLock.unlock()
            return
        }

        // 提取一帧
        let frame = playbackQueue.prefix(TargetAudioFormat.bytesPerFrame)
        playbackQueue.removeFirst(TargetAudioFormat.bytesPerFrame)
        playbackLock.unlock()

        // 创建音频缓冲区并播放
        playPcmData(frame)
    }

    /// 播放 PCM 数据
    private func playPcmData(_ pcmData: Data) {
        guard let buffer = createPcmBuffer(from: pcmData) else {
            return
        }

        // 确保播放节点已启动
        guard playerNode.isPlaying else {
            return
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
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
