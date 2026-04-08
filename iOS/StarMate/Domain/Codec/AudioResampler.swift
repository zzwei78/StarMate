import AVFoundation

// MARK: - Audio Format Constants

/// 目标音频格式参数
enum TargetAudioFormat {
    /// 采样率: 8000 Hz
    static let sampleRate: Double = 8000

    /// 声道数: Mono
    static let channels: UInt32 = 1

    /// 位深: 16-bit
    static let bitsPerSample: Int = 16

    /// 每帧采样点数 (20ms @ 8kHz)
    static let samplesPerFrame: Int = 160

    /// 每帧字节数 (160 samples × 2 bytes)
    static let bytesPerFrame: Int = 320

    /// 帧时长 (毫秒)
    static let frameDurationMs: Int = 20
}

// MARK: - Audio Resampler

/// 音频重采样器
///
/// 将任意采样率的 PCM 音频转换为 8kHz 16-bit Mono 格式。
///
/// ## 功能
/// - 支持任意输入采样率 (44.1kHz, 48kHz 等)
/// - 输出固定为 8kHz 16-bit Mono
/// - 内置帧缓冲，确保输出为精确的 320 字节 (20ms)
///
/// ## 使用示例
/// ```swift
/// let resampler = AudioResampler()
///
/// // 在 AudioEngine tap 回调中
/// inputNode.installTap(...) { buffer, time in
///     if let pcmData = resampler.resample(buffer: buffer) {
///         // pcmData.count 可能是任意长度
///         // 使用 frameBuffer 提取 320 字节帧
///     }
/// }
/// ```
final class AudioResampler {

    // MARK: - Properties

    /// 目标音频格式: 8kHz, 16-bit, Mono, Interleaved
    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: TargetAudioFormat.sampleRate,
            channels: TargetAudioFormat.channels,
            interleaved: true
        )!
    }()

    /// 重采样转换器 (懒加载)
    private var converter: AVAudioConverter?

    /// 上次输入格式的采样率 (用于检测格式变化)
    private var lastInputSampleRate: Double = 0

    // MARK: - Initialization

    init() {
        print("[AudioResampler] Initialized")
        print("[AudioResampler] Target format: \(Int(TargetAudioFormat.sampleRate))Hz, \(TargetAudioFormat.bitsPerSample)-bit, Mono")
    }

    // MARK: - Public API

    /// 重采样 AVAudioPCMBuffer 到目标格式
    ///
    /// - Parameter buffer: 输入音频缓冲区 (任意格式)
    /// - Returns: 重采样后的 PCM Data (8kHz 16-bit Mono)，可能不是完整的 320 字节帧
    func resample(buffer: AVAudioPCMBuffer) -> Data? {
        let inputFormat = buffer.format

        // 检测格式变化，重新创建转换器
        if converter == nil || inputFormat.sampleRate != lastInputSampleRate {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            lastInputSampleRate = inputFormat.sampleRate

            if let cvt = converter {
                // 优化转换质量
                cvt.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
                // sampleRateConverterAlgorithm is read-only, set quality instead

                print("[AudioResampler] Created converter: \(Int(inputFormat.sampleRate))Hz → \(Int(TargetAudioFormat.sampleRate))Hz")
            }
        }

        guard let converter = converter else {
            print("[AudioResampler] ❌ Failed to create converter")
            return nil
        }

        // 计算输出帧数
        let ratio = TargetAudioFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard outputFrameCount > 0 else {
            return nil
        }

        // 创建输出缓冲区
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            print("[AudioResampler] ❌ Failed to create output buffer")
            return nil
        }

        // 执行转换
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("[AudioResampler] ❌ Conversion error: \(error.localizedDescription)")
            return nil
        }

        // 提取 Int16 数据
        guard let channelData = outputBuffer.int16ChannelData else {
            print("[AudioResampler] ❌ No channel data")
            return nil
        }

        let dataLength = Int(outputBuffer.frameLength) * 2  // 16-bit = 2 bytes per sample
        let data = Data(bytes: channelData[0], count: dataLength)

        return data
    }

    /// 获取目标格式
    var outputFormat: AVAudioFormat {
        return targetFormat
    }
}

// MARK: - PCM Frame Buffer

/// PCM 帧缓冲区
///
/// 将不固定长度的 PCM 数据切分为精确的 20ms 帧 (320 bytes)。
///
/// ## 使用示例
/// ```swift
/// let frameBuffer = PcmFrameBuffer()
///
/// // 添加重采样后的数据
/// frameBuffer.append(resampledData)
///
/// // 提取完整的 320 字节帧
/// while let frame = frameBuffer.popFrame() {
///     // frame.count == 320
///     // 发送给 AMR 编码器
/// }
/// ```
final class PcmFrameBuffer {

    // MARK: - Properties

    /// 内部缓冲区
    private var buffer = Data()

    /// 缓冲区最大容量 (防止内存无限增长)
    private let maxBufferSize: Int

    /// 线程锁
    private let lock = NSLock()

    /// 帧大小 (320 bytes = 160 samples × 2 bytes)
    private let frameSize: Int = TargetAudioFormat.bytesPerFrame

    // MARK: - Computed Properties

    /// 当前缓冲区大小
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// 可用帧数
    var availableFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count / frameSize
    }

    // MARK: - Initialization

    /// 初始化帧缓冲区
    ///
    /// - Parameter maxBufferSize: 最大缓冲区大小 (默认 4800 bytes = 15 帧 = 300ms)
    init(maxBufferSize: Int = 4800) {
        self.maxBufferSize = maxBufferSize
    }

    // MARK: - Public API

    /// 添加 PCM 数据到缓冲区
    ///
    /// - Parameter data: PCM 数据 (8kHz 16-bit Mono)
    func append(_ data: Data) {
        guard !data.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)

        // 防止缓冲区无限增长
        if buffer.count > maxBufferSize {
            let excess = buffer.count - maxBufferSize
            buffer.removeFirst(excess)
            print("[PcmFrameBuffer] ⚠️ Buffer overflow, dropped \(excess) bytes")
        }
    }

    /// 弹出一个完整的帧 (320 bytes)
    ///
    /// - Returns: 完整帧数据，如果数据不足返回 nil
    func popFrame() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard buffer.count >= frameSize else {
            return nil
        }

        let frame = buffer.prefix(frameSize)
        buffer.removeFirst(frameSize)

        return frame
    }

    /// 查看但不移除下一个帧
    ///
    /// - Returns: 完整帧数据，如果数据不足返回 nil
    func peekFrame() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard buffer.count >= frameSize else {
            return nil
        }

        return buffer.prefix(frameSize)
    }

    /// 清空缓冲区
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        buffer.removeAll()
    }
}

// MARK: - Audio Level Calculator

/// 音频电平计算器
///
/// 计算 PCM 数据的 RMS 电平 (用于 UI 显示)
final class AudioLevelCalculator {

    /// 计算 PCM 数据的 RMS 电平
    ///
    /// - Parameter pcmData: PCM 数据 (16-bit signed integer)
    /// - Returns: 电平值 (0.0 ~ 1.0)
    static func calculateRMS(_ pcmData: Data) -> Float {
        guard pcmData.count >= 2 else { return 0 }

        let sampleCount = pcmData.count / 2
        var sumSquares: Float = 0

        pcmData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }

            for i in 0..<sampleCount {
                let sample = Float(base[i])
                sumSquares += sample * sample
            }
        }

        let meanSquare = sumSquares / Float(sampleCount)
        let rms = sqrt(meanSquare)

        // 归一化到 0~1 (Int16 最大值 = 32767)
        let normalized = rms / 32767.0

        return min(1.0, max(0.0, normalized))
    }

    /// 计算 PCM 数据的峰值电平
    ///
    /// - Parameter pcmData: PCM 数据 (16-bit signed integer)
    /// - Returns: 峰值电平 (0.0 ~ 1.0)
    static func calculatePeak(_ pcmData: Data) -> Float {
        guard pcmData.count >= 2 else { return 0 }

        let sampleCount = pcmData.count / 2
        var peak: Float = 0

        pcmData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }

            for i in 0..<sampleCount {
                let sample = abs(Float(base[i]))
                if sample > peak {
                    peak = sample
                }
            }
        }

        // 归一化到 0~1
        return min(1.0, peak / 32767.0)
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension AudioResampler {
    /// 打印格式信息
    func printFormatInfo(_ format: AVAudioFormat) {
        print("[AudioResampler] Format: \(format)")
        print("  - Sample Rate: \(format.sampleRate) Hz")
        print("  - Channels: \(format.channelCount)")
        print("  - Common Format: \(format.commonFormat)")
        print("  - Interleaved: \(format.isInterleaved)")
    }
}
#endif
