import AVFoundation
import Foundation
import QuickLook

// MARK: - WAV File Helper

/// 将 PCM 数据保存为 WAV 文件 (8kHz, 16-bit, mono)
func saveAsWavFile(pcmData: Data, sampleRate: Int, filePath: String) -> Bool {
    let fileSize = UInt32(pcmData.count + 44) // 44 = WAV header size

    // WAV 文件头
    var header = Data()

    // RIFF header
    header.append("RIFF".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
    header.append("WAVE".data(using: .ascii)!)

    // fmt chunk (16-bit PCM)
    header.append("fmt ".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
    header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // audio format (PCM)
    header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // channels
    header.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })  // sample rate
    let byteRate = sampleRate * 2  // sampleRate * channels * bitsPerSample/8
    header.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
    header.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })  // block align
    header.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample

    // data chunk
    header.append("data".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Data($0) })

    // 合并头部和 PCM 数据
    let wavData = header + pcmData

    do {
        try wavData.write(to: URL(fileURLWithPath: filePath))
        print("[WAV] Saved \(pcmData.count) bytes to \(filePath)")
        return true
    } catch {
        print("[WAV] Failed to write file: \(error)")
        return false
    }
}

// MARK: - AMR Test Audio Data Helper

/// 获取预编码的 AMR-NB 音频数据（来自 amr_source_file.h）
///
/// 该文件包含预编码的 AMR-NB 音频数据，每个包 32 字节
func getAmrTestData() -> (data: Data, frameCount: Int) {
    // 使用 C 辅助函数获取数据指针和长度
    guard let dataPtr = get_amr_test_data() else {
        return (Data(), 0)
    }

    let totalBytes = Int(get_amr_test_data_length())
    let frameSize = 32
    let frameCount = totalBytes / frameSize

    // 从 C 数组创建 Data
    let data = Data(bytes: dataPtr, count: totalBytes)

    return (data, frameCount)
}

// MARK: - Audio Test Manager

/// 音频测试管理器（与主代码解耦的测试模块）
///
/// 功能：
/// 1. 播放测试 AMR-NB 音频文件
/// 2. BLE 回环传输测试
@MainActor
final class AudioTestManager: NSObject, ObservableObject {

    // MARK: - Published State

    /// 是否正在播放测试音频
    @Published private(set) var isPlayingTestAudio = false

    /// 是否正在进行回环测试
    @Published private(set) var isLoopbackTestActive = false

    /// 回环测试统计信息（不用 @Published，减少主线程切换）
    private(set) var loopbackStats = LoopbackStats()

    /// 获取当前回环统计（用于 UI 显示）
    func getLoopbackStats() -> LoopbackStats {
        return loopbackStats
    }

    /// 测试状态消息
    @Published private(set) var statusMessage: String = ""

    /// 保存的 WAV 文件路径（用于预览）
    @Published private(set) var savedWavFilePath: URL?

    // MARK: - Properties

    private var voiceClient: VoiceServiceClientImpl?
    private var bleManager: BleManagerImpl?  // 用于设置连接优先级
    private var audioPlayer: AVAudioPlayer?  // 用于测试音频播放
    private var playbackTimer: Timer?

    /// UI 刷新定时器（用于回环统计显示）
    private var statsUpdateTimer: Timer?

    /// 播放缓冲补充定时器
    private var refillTimer: Timer?

    /// 高精度发送定时器（用于 BLE 回环测试）
    private var loopbackSendTimer: DispatchSourceTimer?

    private let amrDecoder = AmrNbDecoder()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var testAmrFrames: [Data] = []
    private var loopbackFramesSent = 0
    private var loopbackFramesReceived = 0
    private var lastLoopbackTime: Date?

    private var loopbackIsPlaying = false
    private var loopbackPlayerNode = AVAudioPlayerNode()
    private var loopbackAudioEngine = AVAudioEngine()

    // MARK: - Loopback Stats

    struct LoopbackStats {
        var framesSent: Int = 0
        var framesReceived: Int = 0
        var averageLatency: Double = 0
        var maxLatency: Double = 0
        var minLatency: Double = Double.infinity
    }

    // MARK: - Initialization

    init(voiceClient: VoiceServiceClientImpl? = nil, bleManager: BleManagerImpl? = nil) {
        super.init()
        self.voiceClient = voiceClient
        self.bleManager = bleManager
        setupAudioEngine()
        setupLoopbackAudioEngine()
        print("[AudioTest] Initialized")
    }

    func updateBleManager(_ bleManager: BleManagerImpl?) {
        self.bleManager = bleManager
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode

        // 直接使用 8kHz 播放格式
        guard let playbackFormat8kHz = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8000,
            channels: 1,
            interleaved: true
        ) else {
            print("[AudioTest] Failed to create playback format")
            return
        }

        // 连接时明确指定 8kHz 格式
        audioEngine.connect(playerNode, to: mainMixer, format: playbackFormat8kHz)
        playerNode.volume = 1.0

        do {
            try audioEngine.start()
            print("[AudioTest] Audio engine started (8kHz direct playback)")
        } catch {
            print("[AudioTest] Failed to start audio engine: \(error)")
        }
    }

    /// 更新 Voice Client（当 BLE Manager 切换时）
    func updateVoiceClient(_ voiceClient: VoiceServiceClientImpl?) {
        self.voiceClient = voiceClient
        print("[AudioTest] Updated voice client")
    }

    /// 设置回环测试的独立音频引擎
    private func setupLoopbackAudioEngine() {
        loopbackAudioEngine.attach(loopbackPlayerNode)
        let mainMixer = loopbackAudioEngine.mainMixerNode

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 8000,
            channels: 1,
            interleaved: true
        ) else {
            print("[AudioTest] Failed to create loopback audio format")
            return
        }

        loopbackAudioEngine.connect(loopbackPlayerNode, to: mainMixer, format: format)
        loopbackPlayerNode.volume = 1.0

        do {
            try loopbackAudioEngine.start()
            print("[AudioTest] Loopback audio engine started")
        } catch {
            print("[AudioTest] Failed to start loopback audio engine: \(error)")
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

        // 先生成 WAV 文件，然后用 AVAudioPlayer 播放
        guard let frames = loadTestAmrSequence() else {
            statusMessage = "无法加载测试音频"
            return
        }

        // 解码所有帧
        var allPcmData = Data()
        for frame in frames {
            let pcmData = amrDecoder.decode(amrData: frame)
            allPcmData.append(pcmData)
        }

        // 保存为临时 WAV 文件
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let documentsDirectory = paths.first else { return }

        let wavPath = documentsDirectory + "/temp_audio.wav"
        if saveAsWavFile(pcmData: allPcmData, sampleRate: 8000, filePath: wavPath) {
            // 使用 AVAudioPlayer 播放
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: wavPath))
                audioPlayer?.numberOfLoops = -1  // 循环播放
                audioPlayer?.play()
                isPlayingTestAudio = true
                statusMessage = "正在播放 (AVAudioPlayer)"
                print("[AudioTest] Playing WAV with AVAudioPlayer")
            } catch {
                print("[AudioTest] Failed to create AVAudioPlayer: \(error)")
                statusMessage = "播放失败"
            }
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

    /// 播放 AMR 帧序列（预解码 + 连续播放）
    private func playAmrFrames(_ frames: [Data], loop: Bool) {
        isPlayingTestAudio = true
        statusMessage = "正在播放测试音频..."

        // 预解码所有帧为 PCM 缓冲区
        let pcmBuffers = frames.compactMap { amrFrame -> AVAudioPCMBuffer? in
            let pcmData = amrDecoder.decode(amrData: amrFrame)
            return createPcmBuffer(from: pcmData)
        }

        guard !pcmBuffers.isEmpty else {
            print("[AudioTest] Failed to decode frames")
            isPlayingTestAudio = false
            statusMessage = "解码失败"
            return
        }

        print("[AudioTest] Pre-decoded \(pcmBuffers.count) frames, scheduling continuous playback")

        // 启动播放节点
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

        // 使用 completion handler 连续调度所有缓冲区
        scheduleBuffersSequentially(buffers: pcmBuffers, startIndex: 0, loop: loop)

        print("[AudioTest] Started playback of \(pcmBuffers.count) frames")
    }

    /// 递归调度 PCM 缓冲区（带循环支持）
    private func scheduleBuffersSequentially(buffers: [AVAudioPCMBuffer], startIndex: Int, loop: Bool) {
        guard isPlayingTestAudio, startIndex < buffers.count else {
            if loop && isPlayingTestAudio {
                // 循环：从头开始
                scheduleBuffersSequentially(buffers: buffers, startIndex: 0, loop: true)
            }
            return
        }

        let buffer = buffers[startIndex]

        // 调度当前缓冲区，播放完成后调度下一个
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let self = self else { return }
            self.scheduleBuffersSequentially(buffers: buffers, startIndex: startIndex + 1, loop: loop)
        }

        // 如果是第一帧且播放节点未启动，启动它
        if startIndex == 0 && !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// 播放单个 AMR 帧
    private func playAmrFrame(_ amrFrame: Data) {
        // 解码 AMR → PCM (8kHz)
        let pcmData = amrDecoder.decode(amrData: amrFrame)
        guard !pcmData.isEmpty else { return }

        // 直接创建 8kHz PCM 缓冲区播放
        guard let buffer = createPcmBuffer(from: pcmData) else { return }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// 加载测试 AMR 帧序列（从预编码的音频文件）
    private func loadTestAmrSequence() -> [Data]? {
        let (data, frameCount) = getAmrTestData()
        let frameSize = 32

        guard frameCount > 0 else {
            print("[AudioTest] No AMR test data available")
            return nil
        }

        var frames: [Data] = []

        // 从 Data 中提取每一帧
        for frameIndex in 0..<frameCount {
            let offset = frameIndex * frameSize

            // 确保不超出数据范围
            guard offset + frameSize <= data.count else {
                break
            }

            // 提取一帧
            let frameData = data.subdata(in: offset..<offset + frameSize)
            frames.append(frameData)
        }

        print("[AudioTest] Loaded \(frames.count) AMR frames from test file (\(frames.count * 20 / 1000)s)")
        return frames.isEmpty ? nil : frames
    }

    /// 解码 AMR 帧并保存为 WAV 文件（用于调试）
    func decodeAndSaveAsWav() {
        guard let frames = loadTestAmrSequence() else {
            statusMessage = "无法加载 AMR 数据"
            return
        }

        print("[AudioTest] Decoding \(frames.count) AMR frames to WAV...")

        var allPcmData = Data()
        for (index, frame) in frames.enumerated() {
            let pcmData = amrDecoder.decode(amrData: frame)
            allPcmData.append(pcmData)

            if index == 0 {
                print("[AudioTest] First frame: AMR \(frame.count) bytes → PCM \(pcmData.count) bytes")
            }
        }

        // 保存到文档目录
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        if let documentsDirectory = paths.first {
            let wavPath = documentsDirectory + "/amr_decoded_8k16bit.wav"
            let wavURL = URL(fileURLWithPath: wavPath)

            if saveAsWavFile(pcmData: allPcmData, sampleRate: 8000, filePath: wavPath) {
                savedWavFilePath = wavURL
                statusMessage = "已保存，可预览播放"
                print("[AudioTest] ========== WAV file saved successfully! ==========")
                print("[AudioTest] File path: \(wavPath)")
                print("[AudioTest] Total: \(allPcmData.count) bytes = \(allPcmData.count / 320) frames")
                print("[AudioTest] Duration: \(allPcmData.count / 320 * 20 / 1000)s")
                print("[AudioTest] ==================================================")
            } else {
                statusMessage = "保存失败"
            }
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

        // 设置 BLE 连接为高优先级模式（降低延迟）
        // priority: 2 = high priority for low latency
        bleManager?.requestConnectionPriority(2)
        print("[AudioTest] Set BLE connection priority to HIGH (low latency mode)")

        // 重置统计
        loopbackStats = LoopbackStats()
        loopbackFramesSent = 0
        loopbackFramesReceived = 0
        lastLoopbackTime = nil

        // 启动 UI 刷新定时器（每 500ms 刷新一次统计显示）
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 通过更新 statusMessage 来触发 UI 刷新
            self.statusMessage = self.statusMessage  // 触发 objectWillChange
        }

        // 生成测试 AMR 帧
        testAmrFrames = loadTestAmrSequence() ?? []
        guard !testAmrFrames.isEmpty else {
            statusMessage = "无法生成测试帧"
            isLoopbackTestActive = false
            return
        }

        // 设置接收回调
        setupLoopbackCallback(voiceClient: voiceClient)

        // 开始发送到 BLE（不播放本地测试音频，只播放回环接收到的）
        startLoopbackSending(voiceClient: voiceClient)

        print("[AudioTest] Loopback test started - sending frames, waiting for BLE echo...")
    }

    /// 停止 BLE 回环测试
    func stopLoopbackTest() {
        print("[AudioTest] Stopping loopback test...")

        // 恢复 BLE 连接为正常优先级模式
        // priority: 0 = normal priority
        bleManager?.requestConnectionPriority(0)
        print("[AudioTest] Restored BLE connection priority to NORMAL")

        // 停止高精度发送定时器
        loopbackSendTimer?.cancel()
        loopbackSendTimer = nil

        // 停止发送
        loopbackFramesSent = 0

        // 停止 UI 刷新定时器
        statsUpdateTimer?.invalidate()
        statsUpdateTimer = nil

        loopbackPlayerNode.stop()
        loopbackIsPlaying = false

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

    /// 设置回环回调（来一帧播放一帧，不缓冲）
    private func setupLoopbackCallback(voiceClient: VoiceServiceClientImpl) {
        // 保存原始回调
        let originalCallback = voiceClient.onAmrFrameReceived

        // 来一帧播放一帧，不缓冲
        voiceClient.onAmrFrameReceived = { [weak self] amrData in
            guard let self = self else { return }

            guard self.isLoopbackTestActive else {
                voiceClient.onAmrFrameReceived = originalCallback
                return
            }

            let receiveTime = Date()

            // 立即解码 AMR → PCM
            let pcmData = self.amrDecoder.decode(amrData: amrData)

            // 立即播放，不缓冲
            self.playLoopbackFrameImmediate(pcmData)

            // 在主线程更新统计
            Task { @MainActor in
                self.loopbackFramesReceived += 1

                if let lastTime = self.lastLoopbackTime {
                    let latency = receiveTime.timeIntervalSince(lastTime) * 1000
                    self.loopbackStats.averageLatency = latency
                    self.loopbackStats.maxLatency = max(self.loopbackStats.maxLatency, latency)
                    self.loopbackStats.minLatency = min(self.loopbackStats.minLatency, latency)
                }
                self.lastLoopbackTime = receiveTime
                self.loopbackStats.framesReceived = self.loopbackFramesReceived
                self.loopbackStats.framesSent = self.loopbackStats.framesSent

                if self.loopbackFramesReceived % 50 == 0 {
                    print("[AudioTest] Loopback: \(self.loopbackStats.framesSent) sent, \(self.loopbackFramesReceived) received")
                }
            }
        }

        print("[AudioTest] Loopback callback configured (immediate playback mode, no buffer)")
    }

    /// 立即播放单帧 PCM（无缓冲）
    private func playLoopbackFrameImmediate(_ pcmData: Data) {
        guard let buffer = createPcmBuffer(from: pcmData) else {
            return
        }

        loopbackPlayerNode.scheduleBuffer(buffer, at: nil, options: [])

        if !loopbackPlayerNode.isPlaying {
            loopbackPlayerNode.play()
            loopbackIsPlaying = true
        }
    }

    /// 开始循环发送 AMR 帧到 BLE
    private func startLoopbackSending(voiceClient: VoiceServiceClientImpl) {
        var frameIndex = 0
        let framesPerBatch = 3  // 每次发送 3 帧
        let batchDuration: TimeInterval = 0.06  // 3 帧 = 60ms 音频，每 60ms 发送一次

        // 使用高精度 DispatchSourceTimer 替代 Timer
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.setEventHandler { [weak self, weak voiceClient] in
            guard let self = self, let voiceClient = voiceClient else {
                timer.cancel()
                return
            }

            guard self.isLoopbackTestActive else {
                timer.cancel()
                return
            }

            // 收集 framesPerBatch 个帧进行批量发送
            var batch: [Data] = []
            for _ in 0..<framesPerBatch {
                if frameIndex < self.testAmrFrames.count {
                    batch.append(self.testAmrFrames[frameIndex])
                    frameIndex += 1
                }
            }

            if !batch.isEmpty {
                // 使用 Task { @MainActor in } 确保线程安全
                Task { @MainActor in
                    let result = await voiceClient.sendAmrFrames(batch)
                    if case .success = result {
                        self.loopbackFramesSent += batch.count
                        self.loopbackStats.framesSent = self.loopbackFramesSent
                    }
                }
            }

            // 如果到达末尾，循环
            if frameIndex >= self.testAmrFrames.count {
                frameIndex = 0
            }
        }

        // 设置定时器：leeway 为 1ms，允许少量抖动
        timer.schedule(deadline: .now(), repeating: .milliseconds(Int(batchDuration * 1000)), leeway: .milliseconds(1))
        timer.resume()
        loopbackSendTimer = timer

        print("[AudioTest] High-precision sending timer started: \(batchDuration * 1000)ms interval, \(framesPerBatch) frames/batch (leeway: 1ms)")
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
