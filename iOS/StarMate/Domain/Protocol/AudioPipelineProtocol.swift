import Foundation

// MARK: - Audio Pipeline Delegate

/// 音频流水线代理协议
///
/// 接收上行 AMR 帧和下行 PCM 数据的回调
protocol AudioPipelineDelegate: AnyObject {

    /// 上行 AMR 帧已编码完成 (发送给设备)
    ///
    /// - Parameters:
    ///   - pipeline: 音频流水线实例
    ///   - frame: AMR 帧数据 (32 bytes, MR122 模式)
    func audioPipeline(_ pipeline: AudioPipelineManager, didEncodeAmrFrame frame: Data)

    /// 上行 PCM 已采集 (送给录音器)
    ///
    /// - Parameters:
    ///   - pipeline: 音频流水线实例
    ///   - pcm: PCM 数据 (8kHz 16-bit Mono)
    func audioPipeline(_ pipeline: AudioPipelineManager, didCaptureUplinkPcm pcm: Data)

    /// 下行 PCM 已解码 (送给录音器)
    ///
    /// - Parameters:
    ///   - pipeline: 音频流水线实例
    ///   - pcm: PCM 数据 (8kHz 16-bit Mono)
    func audioPipeline(_ pipeline: AudioPipelineManager, didDecodeDownlinkPcm pcm: Data)
}

// MARK: - AudioPipelineDelegate Optional Implementation

extension AudioPipelineDelegate {
    func audioPipeline(_ pipeline: AudioPipelineManager, didEncodeAmrFrame frame: Data) {}
    func audioPipeline(_ pipeline: AudioPipelineManager, didCaptureUplinkPcm pcm: Data) {}
    func audioPipeline(_ pipeline: AudioPipelineManager, didDecodeDownlinkPcm pcm: Data) {}
}

// MARK: - Audio Pipeline Protocol

/// 音频流水线协议
///
/// 管理录音、播放、编解码的完整音频流水线
protocol AudioPipelineProtocol: AnyObject {

    // MARK: - Properties

    /// 代理
    var delegate: AudioPipelineDelegate? { get set }

    /// 是否正在录音
    var isRecording: Bool { get }

    /// 是否正在播放
    var isPlaying: Bool { get }

    /// 当前音频模式
    var currentMode: AudioMode { get }

    // MARK: - Recording (Uplink)

    /// 开始录音
    func startRecording() async -> Result<Void, Error>

    /// 停止录音
    func stopRecording() async -> Result<Void, Error>

    // MARK: - Playback (Downlink)

    /// 开始播放
    func startPlaying() async -> Result<Void, Error>

    /// 停止播放
    func stopPlaying() async -> Result<Void, Error>

    /// 输入 AMR 帧进行解码并播放
    ///
    /// - Parameter amrData: Raw AMR 帧数据 (无文件头)
    func feedDownlinkAmr(_ amrData: Data)

    // MARK: - Audio Mode

    /// 设置音频模式 (听筒/扬声器)
    func setAudioMode(_ mode: AudioMode) async -> Result<Void, Error>
}
