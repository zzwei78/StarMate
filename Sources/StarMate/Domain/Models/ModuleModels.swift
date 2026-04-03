import Foundation

// MARK: - TT Module State
/// TT Module state from CMD_GET_TT_STATUS (0x60).
/// Firmware state values 0~6 (see TT_MODULE_STATUS.md).
/// Sub-states (SIM, network) are queried by app via AT+CPIN? / AT+CREG? when state is Working.
enum TtModuleState: Equatable {
    /// Hardware fault; check errorCode. Firmware state 0.
    case hardwareFault(errorCode: Int)
    /// Module initializing. Firmware state 1.
    case initializing
    /// Internal transient (waiting MUX response). Firmware state 2.
    case waitingMuxResp
    /// Auto low-battery shutdown. Firmware state 3.
    case lowBatteryOff
    /// User manual off (NVS persistent). Firmware state 4.
    case userOff
    /// Normal operation. Firmware state 5.
    case working
    /// OTA firmware update. Firmware state 6.
    case updating
    /// Unknown or legacy state.
    case error(errorCode: Int)
    /// Backward compat: treat as powered-off for UI (legacy 3-byte response).
    case poweredOff(reason: PowerOffReason)

    var displayText: String {
        switch self {
        case .hardwareFault(let code): return "硬件异常 (\(code))"
        case .initializing: return "正在初始化..."
        case .waitingMuxResp: return "初始化中..."
        case .lowBatteryOff: return "低电关机"
        case .userOff: return "已关闭"
        case .working: return "工作中"
        case .updating: return "正在升级..."
        case .error(let code): return "错误 (\(code))"
        case .poweredOff(let reason):
            switch reason {
            case .userRequest: return "已关闭"
            case .lowBattery: return "低电关机"
            case .hardwareFault: return "硬件异常"
            }
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var isPoweredOff: Bool {
        switch self {
        case .userOff, .lowBatteryOff, .poweredOff:
            return true
        default:
            return false
        }
    }
}

// MARK: - Power Off Reason
/// Reason for TT Module power off
enum PowerOffReason: String, Codable {
    case userRequest
    case lowBattery
    case hardwareFault
}

// MARK: - TT Module Status
/// Complete TT Module status from GET_TT_STATUS (0x60).
/// Sub-states (SIM, network) are queried separately via AT when state is Working.
struct TtModuleStatus: Equatable {
    let state: TtModuleState
    let voltageMv: Int

    @available(*, deprecated, message: "No longer reported by firmware; use AT+CPIN?/CREG? sub-state")
    var isPoweredOn: Bool = false

    @available(*, deprecated, message: "No longer reported by firmware")
    var isMuxReady: Bool = false

    @available(*, deprecated, message: "No longer reported by firmware; use simState from AT+CPIN?")
    var isSimReady: Bool = false

    @available(*, deprecated, message: "No longer reported by firmware; use networkReg from AT+CREG?")
    var isNetworkReady: Bool = false
}

// MARK: - SIM State
/// SIM card state from AT+CPIN
enum SimState: Equatable {
    case ready
    case simPinRequired(remainingAttempts: Int)
    case simPukRequired(remainingAttempts: Int)
    case simPin2Required(remainingAttempts: Int)
    case simPuk2Required(remainingAttempts: Int)
    case phSimPinRequired(remainingAttempts: Int)
    case absent
    case error
    case unknown

    var displayText: String {
        switch self {
        case .ready: return "就绪"
        case .simPinRequired: return "需要PIN"
        case .simPukRequired: return "需要PUK"
        case .simPin2Required: return "需要PIN2"
        case .simPuk2Required: return "需要PUK2"
        case .phSimPinRequired: return "需要电话PIN"
        case .absent: return "无卡"
        case .error, .unknown: return "-"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isAbsent: Bool {
        if case .absent = self { return true }
        return false
    }
}

// MARK: - Network Registration Status
/// Network registration status from AT+CREG
enum NetworkRegistrationStatus: Equatable {
    case notRegistered
    case registered(isRoaming: Bool)
    case searching
    case registrationDenied
    case unknown
    case networkLost

    var displayText: String {
        switch self {
        case .notRegistered: return "未注册"
        case .registered(let isRoaming): return isRoaming ? "漫游" : "登网"
        case .searching: return "搜网"
        case .registrationDenied: return "拒绝"
        case .unknown: return "未知"
        case .networkLost: return "掉网"
        }
    }

    var isRegistered: Bool {
        if case .registered = self { return true }
        return false
    }
}

// MARK: - Module State
/// Satellite module state machine
enum ModuleState: Equatable {
    case off
    case initializing
    case ready
    case error(error: ModuleError)
}

// MARK: - Module Error
/// Module error types
enum ModuleError: Equatable {
    case muxFailed
    case commTimeout
    case simNotReady
    case networkRegFailed
    case lowBattery
    case hardwareFault
    case unknown(code: Int)
}

// MARK: - Baseband Version
/// Baseband info from AT commands (IMEI, IMSI, CCID, software/hardware version)
struct BasebandVersion: Equatable {
    let imei: String
    let imsi: String
    let ccid: String
    let softwareVersion: String
    let hardwareVersion: String
    let model: String
    let manufacturer: String
}
