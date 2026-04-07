import Foundation

// MARK: - SIM State

/// SIM 卡状态
enum SimState: Equatable {
    /// 未知状态
    case unknown
    /// 就绪 (已解锁)
    case ready
    /// 需要 PIN 码
    case pinRequired
    /// 需要 PUK 码
    case pukRequired
    /// SIM 卡不存在
    case notPresent
    /// SIM 卡错误
    case error
    /// 正在初始化
    case initializing

    /// 是否可以拨打电话
    var canMakeCall: Bool {
        return self == .ready
    }
}

// MARK: - Baseband Version

/// 基带版本信息
struct BasebandVersion: Equatable {
    /// 软件版本
    let swVersion: String

    /// 硬件版本
    let hwVersion: String?

    /// 制造商
    let manufacturer: String?

    /// 型号
    let model: String?

    /// 修订版本
    let revision: String?

    /// IMEI
    let imei: String?

    /// IMSI
    let imsi: String?

    /// ICCID (SIM 卡序列号)
    let iccid: String?
}

// MARK: - Network Registration

/// 网络注册状态
enum NetworkRegState: Equatable {
    /// 未注册
    case notRegistered
    /// 已注册，本地网络
    case registeredHome
    /// 正在搜索
    case searching
    /// 注册被拒绝
    case registrationDenied
    /// 未知
    case unknown
    /// 已注册，漫游
    case registeredRoaming
}

// MARK: - Signal Strength

/// 信号强度信息
struct SignalInfo: Equatable {
    /// 信号强度 (0-31, 99 表示未知)
    let rssi: Int

    /// 误码率 (0-7, 99 表示未知)
    let ber: Int

    /// 信号等级 (0-4, 用于 UI 显示)
    var signalLevel: Int {
        if rssi == 99 { return 0 }
        if rssi >= 20 { return 4 }
        if rssi >= 15 { return 3 }
        if rssi >= 10 { return 2 }
        if rssi >= 5 { return 1 }
        return 0
    }

    /// 信号描述
    var signalDescription: String {
        if rssi == 99 { return "未知" }
        if rssi >= 20 { return "极好" }
        if rssi >= 15 { return "良好" }
        if rssi >= 10 { return "一般" }
        if rssi >= 5 { return "较弱" }
        return "极弱"
    }
}

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
    var networkRegState: NetworkRegState { get }

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
    func getNetworkRegState() async -> Result<NetworkRegState, Error>

    /// 获取信号强度
    func getSignalInfo() async -> Result<SignalInfo, Error>

    // MARK: - Convenience

    /// 是否准备好拨打电话
    func isReadyForCall() -> Bool

    /// 刷新所有状态
    func refreshAllStatus() async
}
