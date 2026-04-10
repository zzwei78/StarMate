import AVFoundation
import Foundation

// MARK: - Audio Test Manager

/// 音频测试管理器（与主代码解耦的测试模块）
///
/// 功能：
/// 1. 播放测试 AMR-NB 音频文件
/// 2. BLE 回环传输测试
@MainActor
final class AudioTestManager: ObservableObject {

    // MARK: - Published State

    /// 是否正在播放测试音频
    @Published private(set) var isPlayingTestAudio = false

    /// 是否正在进行回环测试
    @Published private(set) var isLoopbackTestActive = false

    /// 回环测试统计信息
    @Published private(set) var loopbackStats = LoopbackStats()

    /// 测试状态消息
    @Published private(set) var statusMessage: String = ""

    // MARK: - Properties

    private var voiceClient: VoiceServiceClientImpl?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    private let amrDecoder = AmrNbDecoder()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var testAmrFrames: [Data] = []
    private var loopbackFramesSent = 0
    private var loopbackFramesReceived = 0
    private var lastLoopbackTime: Date?

    // MARK: - Loopback Stats

    struct LoopbackStats {
        var framesSent: Int = 0
        var framesReceived: Int = 0
        var averageLatency: Double = 0
        var maxLatency: Double = 0
        var minLatency: Double = Double.infinity
    }

    // MARK: - Initialization

    init(voiceClient: VoiceServiceClientImpl? = nil) {
        self.voiceClient = voiceClient
        setupAudioEngine()
        print("[AudioTest] Initialized")
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(playerNode, to: mainMixer, format: nil)
        playerNode.volume = 1.0

        do {
            try audioEngine.start()
            print("[AudioTest] Audio engine started")
        } catch {
            print("[AudioTest] Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Test 1: Play Test AMR Audio

    /// 播放测试 AMR 音频文件
    func playTestAmrAudio() {
        guard !isPlayingTestAudio else {
            stopTestAmrAudio()
            return
        }

        print("[AudioTest] Starting test AMR audio playback...")

        // 使用内置测试音频或从 Bundle 加载
        if let testAmrData = generateTestAmrSequence() {
            playAmrFrames(testAmrData, loop: true)
        } else {
            statusMessage = "无法生成测试音频"
            print("[AudioTest] Failed to generate test AMR data")
        }
    }

    /// 停止播放测试音频
    func stopTestAmrAudio() {
        print("[AudioTest] Stopping test audio playback...")

        playbackTimer?.invalidate()
        playbackTimer = nil

        playerNode.stop()
        audioPlayer?.stop()
        audioPlayer = nil

        isPlayingTestAudio = false
        statusMessage = "已停止"
    }

    /// 播放 AMR 帧序列
    private func playAmrFrames(_ frames: [Data], loop: Bool) {
        isPlayingTestAudio = true
        statusMessage = "正在播放测试音频..."

        if audioEngine.isRunning {
            playerNode.play()
        } else {
            do {
                try audioEngine.start()
                playerNode.play()
            } catch {
                print("[AudioTest] Failed to start audio engine: \(error)")
                isPlayingTestAudio = false
                statusMessage = "音频引擎启动失败"
                return
            }
        }

        var frameIndex = 0
        let frameDuration: TimeInterval = 0.02  // 20ms per frame

        playbackTimer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            guard self.isPlayingTestAudio else { return }

            if frameIndex < frames.count {
                let amrFrame = frames[frameIndex]
                self.playAmrFrame(amrFrame)
                frameIndex += 1
            } else if loop {
                frameIndex = 0
            } else {
                self.stopTestAmrAudio()
            }
        }

        playbackTimer?.tolerance = 0.001
        print("[AudioTest] Playing \(frames.count) AMR frames, loop: \(loop)")
    }

    /// 播放单个 AMR 帧
    private func playAmrFrame(_ amrFrame: Data) {
        // 解码 AMR → PCM
        let pcmData = amrDecoder.decode(amrData: amrFrame)
        guard !pcmData.isEmpty else { return }

        // 播放 PCM
        guard let buffer = createPcmBuffer(from: pcmData) else { return }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// 生成测试 AMR 帧序列（生成简单的测试音调）
    private func generateTestAmrSequence() -> [Data]? {
        // 生成 3 秒的测试音频（150 帧 @ 20ms/frame）
        var frames: [Data] = []
        let encoder = AmrNbEncoder(dtx: false)

        // 生成 440Hz (A4) 测试音调
        let sampleRate: Double = 8000
        let frequency: Double = 440
        let samplesPerFrame = 160

        for frameIndex in 0..<150 {
            var pcmSamples = [Int16](repeating: 0, count: samplesPerFrame)

            for i in 0..<samplesPerFrame {
                let t = Double(frameIndex * samplesPerFrame + i) / sampleRate
                let amplitude = Double(Int16.max) * 0.3  // 30% 音量

                // 生成正弦波
                let sample = sin(2.0 * .pi * frequency * t) * amplitude
                pcmSamples[i] = Int16(sample)
            }

            let pcmData = Data(bytes: pcmSamples, count: samplesPerFrame * 2)
            if let amrFrame = encodeFrameDirectly(pcmData: pcmData) {
                frames.append(amrFrame)
            }
        }

        print("[AudioTest] Generated \(frames.count) test AMR frames")
        return frames.isEmpty ? nil : frames
    }

    /// 直接编码 PCM 到 AMR
    private func encodeFrameDirectly(pcmData: Data) -> Data? {
        guard pcmData.count >= 320 else { return nil }

        return pcmData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                return nil
            }

            let encoder = AmrNbEncoder(dtx: false)
            return encoder.encode(pcmData: pcmData)
        }
    }

    /// 从 Data 创建 PCM 缓冲区
    private func createPcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / 2)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8000,
            channels: 1,
            interleaved: true
        ) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(buffer.int16ChannelData![0], base, data.count)
        }

        return buffer
    }

    // MARK: - Test 2: BLE Loopback Test

    /// 开始 BLE 回环测试
    func startLoopbackTest() {
        guard !isLoopbackTestActive else {
            stopLoopbackTest()
            return
        }

        guard let voiceClient = voiceClient else {
            statusMessage = "未连接 BLE"
            print("[AudioTest] Voice client not available")
            return
        }

        print("[AudioTest] Starting BLE loopback test...")
        isLoopbackTestActive = true
        statusMessage = "回环测试中..."

        // 重置统计
        loopbackStats = LoopbackStats()
        loopbackFramesSent = 0
        loopbackFramesReceived = 0
        lastLoopbackTime = nil

        // 生成测试 AMR 帧
        testAmrFrames = generateTestAmrSequence() ?? []
        guard !testAmrFrames.isEmpty else {
            statusMessage = "无法生成测试帧"
            isLoopbackTestActive = false
            return
        }

        // 设置接收回调
        setupLoopbackCallback(voiceClient: voiceClient)

        // 启动播放
        playAmrFrames(testAmrFrames, loop: true)

        // 开始发送到 BLE
        startLoopbackSending(voiceClient: voiceClient)
    }

    /// 停止 BLE 回环测试
    func stopLoopbackTest() {
        print("[AudioTest] Stopping loopback test...")
        stopTestAmrAudio()
        isLoopbackTestActive = false
        statusMessage = "回环测试已停止"

        // 打印统计
        print("[AudioTest] Loopback Stats:")
        print("  Sent: \(loopbackStats.framesSent) frames")
        print("  Received: \(loopbackStats.framesReceived) frames")
        print("  Avg Latency: \(String(format: "%.2f", loopbackStats.averageLatency))ms")
        print("  Min Latency: \(String(format: "%.2f", loopbackStats.minLatency))ms")
        print("  Max Latency: \(String(format: "%.2f", loopbackStats.maxLatency))ms")
    }

    /// 设置回环回调
    private func setupLoopbackCallback(voiceClient: VoiceServiceClientImpl) {
        // 保存原始回调
        let originalCallback = voiceClient.onAmrFrameReceived

        // 设置新的回调来接收回环数据
        voiceClient.onAmrFrameReceived = { [weak self] amrData in
            guard let self = self else { return }

            guard self.isLoopbackTestActive else {
                // 如果测试停止，恢复原始回调
                voiceClient.onAmrFrameReceived = originalCallback
                return
            }

            let receiveTime = Date()
            self.loopbackFramesReceived += 1

            // 计算延迟
            if let lastTime = self.lastLoopbackTime {
                let latency = receiveTime.timeIntervalSince(lastTime) * 1000
                self.loopbackStats.averageLatency = latency
                self.loopbackStats.maxLatency = max(self.loopbackStats.maxLatency, latency)
                self.loopbackStats.minLatency = min(self.loopbackStats.minLatency, latency)
            }
            self.lastLoopbackTime = receiveTime

            // 更新统计
            self.loopbackStats.framesReceived = self.loopbackFramesReceived
            self.loopbackStats.framesSent = self.loopbackFramesSent

            // 打印进度
            if self.loopbackFramesReceived % 50 == 0 {
                print("[AudioTest] Loopback: \(self.loopbackFramesSent) sent, \(self.loopbackFramesReceived) received")
            }

            // 播放接收到的音频
            self.playAmrFrame(amrData)
        }

        print("[AudioTest] Loopback callback configured")
    }

    /// 开始循环发送 AMR 帧到 BLE
    private func startLoopbackSending(voiceClient: VoiceServiceClientImpl) {
        var frameIndex = 0
        let frameDuration: TimeInterval = 0.02  // 20ms

        Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            guard self.isLoopbackTestActive else {
                timer.invalidate()
                return
            }

            if frameIndex < self.testAmrFrames.count {
                let frame = self.testAmrFrames[frameIndex]

                Task {
                    let result = await voiceClient.sendAmrFrame(frame)
                    if case .success = result {
                        self.loopbackFramesSent += 1
                        self.loopbackStats.framesSent = self.loopbackFramesSent
                    }
                }

                frameIndex += 1
            } else {
                frameIndex = 0  // 循环
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopTestAmrAudio()
        stopLoopbackTest()
        audioEngine.stop()
    }

    deinit {
        // cleanup() 需要 @MainActor，在 deinit 中无法调用
        // 实际清理由 stopTestAmrAudio 和 stopLoopbackTest 处理
    }
}

// MARK: - Logging Helper

private func Log(_ module: String, _ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    print("[\(timestamp)] [\(module)] \(message)")
}
