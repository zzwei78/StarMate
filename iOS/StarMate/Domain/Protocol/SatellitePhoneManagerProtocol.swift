import Foundation

// MARK: - Satellite Phone Manager Protocol

/// 卫星电话管理器协议
///
/// 负责 SIM 卡管理、基带信息查询、网络状态监控
protocol SatellitePhoneManagerProtocol: AnyObject {

    // MARK: - Published State

    /// SIM 卡状态
    var simState: SimState { get }

    /// 基带版本信息
    var basebandVersion: BasebandVersion? { get }

    /// 网络注册状态
    var networkRegState: NetworkRegistrationStatus { get }

    /// 信号强度
    var signalInfo: SignalInfo? { get }

    // MARK: - SIM Management

    /// 获取 SIM 卡状态
    func getSimState() async -> Result<SimState, Error>

    /// 输入 PIN 码
    func enterPin(_ pin: String) async -> Result<Void, Error>

    /// 解锁 PUK (需要 PUK 码和新 PIN 码)
    func enterPuk(_ puk: String, newPin: String) async -> Result<Void, Error>

    /// 更改 PIN 码
    func changePin(oldPin: String, newPin: String) async -> Result<Void, Error>

    // MARK: - Baseband Info

    /// 获取 IMEI
    func getIMEI() async -> Result<String, Error>

    /// 获取 IMSI
    func getIMSI() async -> Result<String, Error>

    /// 获取 ICCID
    func getICCID() async -> Result<String, Error>

    /// 获取基带软件版本
    func getBasebandSwVersion() async -> Result<String, Error>

    /// 获取完整基带信息
    func getBasebandVersion() async -> Result<BasebandVersion, Error>

    // MARK: - Network

    /// 获取网络注册状态
    func getNetworkRegistrationStatus() async -> Result<NetworkRegistrationStatus, Error>

    /// 获取信号强度
    func getSignalInfo() async -> Result<SignalInfo, Error>

    // MARK: - Convenience

    /// 是否准备好拨打电话
    func isReadyForCall() -> Bool

    /// 刷新所有状态
    func refreshAllStatus() async
}
