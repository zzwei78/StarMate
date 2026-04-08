import Foundation

// MARK: - AMR-NB Constants

/// AMR-NB 编解码常量
enum AmrNbConstants {
    /// 采样率 (Hz)
    static let sampleRate: Int = 8000

    /// 每帧采样点数 (20ms @ 8kHz)
    static let samplesPerFrame: Int = 160

    /// PCM 帧大小 (bytes): 160 samples × 2 bytes
    static let pcmFrameSize: Int = 320

    /// AMR 帧大小 (MR122 模式)
    static let amrFrameSize: Int = 32

    /// 帧时长 (ms)
    static let frameDurationMs: Int = 20

    /// 比特率 (bps)
    static let bitRate: Int = 12200
}

// MARK: - C Function Declarations

/// C 函数声明 (来自 opencore-amrnb)
///
/// 编码器接口:
/// - Encoder_Interface_init(dtx): 初始化编码器
/// - Encoder_Interface_exit(state): 释放编码器
/// - Encoder_Interface_Encode(state, mode, speech, out, forceSpeech): 编码
///
/// 解码器接口:
/// - Decoder_Interface_init(): 初始化解码器
/// - Decoder_Interface_exit(state): 释放解码器
/// - Decoder_Interface_Decode(state, in, out, bfi): 解码

// MARK: - AMR-NB Encoder

/// AMR-NB 编码器
///
/// 使用 opencore-amrnb 库将 PCM 数据编码为 AMR-NB 格式。
///
/// **输入**: 160 个 Int16 样本 (320 bytes, 20ms @ 8kHz)
/// **输出**: 32 字节 raw AMR 帧 (MR122 模式, 无文件头)
///
/// ## 使用示例
/// ```swift
/// let encoder = AmrNbEncoder(dtx: false)
/// let pcmData: Data = ... // 320 bytes
/// let amrFrame = encoder.encode(pcmData: pcmData)
/// // amrFrame.count == 32
/// ```
final class AmrNbEncoder {

    // MARK: - Properties

    /// 编码器状态指针
    private var state: UnsafeMutableRawPointer?

    /// 是否启用 DTX (不连续传输)
    private let dtx: Bool

    /// 是否已初始化
    var isInitialized: Bool {
        return state != nil
    }

    // MARK: - Initialization

    /// 初始化 AMR-NB 编码器
    ///
    /// - Parameter dtx: 是否启用 DTX (Discontinuous Transmission)。
    ///                  DTX 可以在静音时降低比特率，节省带宽。
    init(dtx: Bool = false) {
        self.dtx = dtx
        state = Encoder_Interface_init(dtx ? 1 : 0)

        if state != nil {
            print("[AmrNbEncoder] ✅ Initialized (dtx=\(dtx))")
        } else {
            print("[AmrNbEncoder] ❌ Failed to initialize")
        }
    }

    deinit {
        if let s = state {
            Encoder_Interface_exit(s)
            print("[AmrNbEncoder] Released")
        }
    }

    // MARK: - Encoding

    /// 编码一帧 PCM 数据
    ///
    /// - Parameter pcmData: PCM 数据，至少 320 bytes (160 samples × 2 bytes)
    /// - Returns: AMR 帧数据 (MR122 模式为 32 bytes)，失败返回空 Data
    func encode(pcmData: Data) -> Data {
        // 需要至少 160 个样本
        guard pcmData.count >= AmrNbConstants.pcmFrameSize else {
            print("[AmrNbEncoder] ⚠️ PCM data too short: \(pcmData.count) < \(AmrNbConstants.pcmFrameSize)")
            return Data()
        }

        guard let s = state else {
            print("[AmrNbEncoder] ❌ Encoder not initialized")
            return Data()
        }

        return pcmData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                print("[AmrNbEncoder] ❌ Failed to get PCM pointer")
                return Data()
            }

            // MR122 模式最大输出 32 字节
            let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: AmrNbConstants.amrFrameSize)
            defer { outBuffer.deallocate() }

            // 使用 MR122 (12.2 kbps) 模式
            let size = Encoder_Interface_Encode(s, MR122, base, outBuffer, 0)

            guard size > 0 else {
                print("[AmrNbEncoder] ❌ Encoding failed")
                return Data()
            }

            return Data(bytes: outBuffer, count: Int(size))
        }
    }

    /// 编码一帧 PCM 数据 (指针版本，更高效)
    ///
    /// - Parameter pcm: 指向 160 个 Int16 样本的指针
    /// - Returns: AMR 帧数据
    func encode(pcm: UnsafePointer<Int16>) -> Data {
        guard let s = state else {
            return Data()
        }

        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: AmrNbConstants.amrFrameSize)
        defer { outBuffer.deallocate() }

        let size = Encoder_Interface_Encode(s, MR122, pcm, outBuffer, 0)

        guard size > 0 else { return Data() }

        return Data(bytes: outBuffer, count: Int(size))
    }
}

// MARK: - AMR-NB Decoder

/// AMR-NB 解码器
///
/// 使用 opencore-amrnb 库将 AMR-NB 格式解码为 PCM 数据。
///
/// **输入**: Raw AMR 帧 (32 bytes, MR122 模式, 无文件头)
/// **输出**: 160 个 Int16 样本 (320 bytes, 20ms @ 8kHz)
///
/// ## 使用示例
/// ```swift
/// let decoder = AmrNbDecoder()
/// let amrData: Data = ... // 32 bytes
/// let pcmData = decoder.decode(amrData: amrData)
/// // pcmData.count == 320
/// ```
final class AmrNbDecoder {

    // MARK: - Properties

    /// 解码器状态指针
    private var state: UnsafeMutableRawPointer?

    /// 是否已初始化
    var isInitialized: Bool {
        return state != nil
    }

    // MARK: - Initialization

    /// 初始化 AMR-NB 解码器
    init() {
        state = Decoder_Interface_init()

        if state != nil {
            print("[AmrNbDecoder] ✅ Initialized")
        } else {
            print("[AmrNbDecoder] ❌ Failed to initialize")
        }
    }

    deinit {
        if let s = state {
            Decoder_Interface_exit(s)
            print("[AmrNbDecoder] Released")
        }
    }

    // MARK: - Decoding

    /// 解码一帧 AMR 数据
    ///
    /// - Parameter amrData: Raw AMR 帧数据 (无 `#!AMR\n` 文件头)
    /// - Returns: PCM 数据 (320 bytes = 160 samples)
    func decode(amrData: Data) -> Data {
        guard !amrData.isEmpty else {
            print("[AmrNbDecoder] ⚠️ Empty AMR data")
            return Data()
        }

        guard let s = state else {
            print("[AmrNbDecoder] ❌ Decoder not initialized")
            return Data()
        }

        // AMR-NB 每帧解码为 160 个 Int16 样本
        var pcmBuffer = [Int16](repeating: 0, count: AmrNbConstants.samplesPerFrame)

        amrData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                print("[AmrNbDecoder] ❌ Failed to get AMR pointer")
                return
            }

            // bfi = 0 (没有帧丢失)
            Decoder_Interface_Decode(s, base, &pcmBuffer, 0)
        }

        // 转换为 Data
        return Data(bytes: pcmBuffer, count: AmrNbConstants.pcmFrameSize)
    }

    /// 解码一帧 AMR 数据并返回 Int16 数组
    ///
    /// - Parameter amrData: Raw AMR 帧数据
    /// - Returns: 160 个 Int16 样本
    func decodeToInt16(amrData: Data) -> [Int16] {
        guard !amrData.isEmpty, let s = state else { return [] }

        var pcmBuffer = [Int16](repeating: 0, count: AmrNbConstants.samplesPerFrame)

        amrData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            Decoder_Interface_Decode(s, base, &pcmBuffer, 0)
        }

        return pcmBuffer
    }
}

// MARK: - Convenience: Combined Codec

/// AMR-NB 编解码器 (编码器 + 解码器)
///
/// 便捷类，同时包含编码器和解码器
final class AmrNbCodec {

    private let encoder: AmrNbEncoder
    private let decoder: AmrNbDecoder

    /// 创建编解码器
    ///
    /// - Parameter dtx: 编码器是否启用 DTX
    init(dtx: Bool = false) {
        encoder = AmrNbEncoder(dtx: dtx)
        decoder = AmrNbDecoder()
    }

    /// 编码 PCM → AMR
    func encode(pcmData: Data) -> Data {
        return encoder.encode(pcmData: pcmData)
    }

    /// 解码 AMR → PCM
    func decode(amrData: Data) -> Data {
        return decoder.decode(amrData: amrData)
    }

    /// 是否已初始化
    var isInitialized: Bool {
        return encoder.isInitialized && decoder.isInitialized
    }
}
