import Foundation

// MARK: - Call Manager Protocol

/// 通话管理器协议
///
/// 负责通话生命周期管理
protocol CallManagerProtocol: AnyObject {

    // MARK: - Published State

    /// 当前通话状态
    var callState: CallState { get }

    /// 当前通话信息
    var currentCall: ActiveCall? { get }

    /// 是否开启扬声器
    var isSpeakerOn: Bool { get }

    /// 是否静音
    var isMuted: Bool { get }

    // MARK: - Call Control

    /// 拨打电话
    func makeCall(phoneNumber: String) async -> Result<Void, Error>

    /// 接听来电
    func answerCall() async -> Result<Void, Error>

    /// 挂断电话
    func endCall() async -> Result<Void, Error>

    /// 拒接来电
    func rejectCall() async -> Result<Void, Error>

    // MARK: - In-Call Actions

    /// 发送 DTMF 音
    func sendDtmf(_ key: DtmfKey) async -> Result<Void, Error>

    /// 切换扬声器/听筒
    func toggleSpeaker() async -> Result<Void, Error>

    /// 切换静音
    func toggleMute() async -> Result<Void, Error>

    // MARK: - Call Records

    /// 通话记录列表
    var callRecords: [CallRecord] { get }

    /// 删除通话记录
    func deleteCallRecord(_ id: String) async

    /// 清空所有通话记录
    func clearAllCallRecords() async
}
