import Foundation
import SwiftUI

// MARK: - BLE Connection State
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(address: String)
    case connected(device: ScannedDevice)
    case error(message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Scanned Device
struct ScannedDevice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String
    let rssi: Int

    var signalIcon: String {
        switch rssi {
        case -50...: return "antenna.radiowaves.left.and.right"
        case -65...(-50): return "antenna.radiowaves.left.and.right"
        case -80...(-65): return "antenna.radiowaves.left.and.right"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var signalColor: Color {
        switch rssi {
        case -60...: return .systemBlue
        case -75...(-60): return .systemOrange
        default: return .systemRed
        }
    }
}

// MARK: - Device Info
struct DeviceInfo {
    let name: String
    let address: String
    var batteryLevel: Int         // 0-100
    var currentMa: Int            // Current in mA
    var voltageMv: Int            // Voltage in mV
    var signalStrength: Int       // 0-5 bars
    var isRegistered: Bool
    var regStatus: Int            // 0=未注册, 1=已注册, 2=搜索中, 3=拒绝, 4=未知, 5=漫游
    var satelliteMode: SatelliteMode
    var workMode: WorkMode
}

// MARK: - Terminal Version
struct TerminalVersion {
    let hardwareVersion: String
    let softwareVersion: String
    let firmwareVersion: String
    let manufacturer: String
    let modelNumber: String
}

// MARK: - Battery Info
struct BatteryInfo {
    let level: Int
    let voltage: Int
    let current: Int
    let isCharging: Bool
    let isWirelessCharging: Bool
}

// MARK: - Signal Info
struct SignalInfo {
    let strength: Int       // 0-5 bars
    let ber: Int
    let isRegistered: Bool
    let regStatus: Int
}

// MARK: - Enums
enum SatelliteMode {
    case normal
    case transparent
    case otaUpgrade
}

enum WorkMode {
    case idle
    case calling
    case dataTransfer
}

// MARK: - TT Module State
enum TtModuleState: Equatable {
    case hardwareFault
    case initializing
    case waitingMuxResp
    case lowBatteryOff
    case userOff
    case working
    case updating
    case poweredOff
    case error(errorCode: Int)

    var displayText: String {
        switch self {
        case .hardwareFault: return "硬件异常"
        case .initializing: return "正在初始化..."
        case .waitingMuxResp: return "初始化中..."
        case .lowBatteryOff: return "低电关机"
        case .userOff: return "已关闭"
        case .working: return "工作中"
        case .updating: return "正在升级..."
        case .poweredOff: return "已关闭"
        case .error(let code): return "错误 (0x\(String(code, radix: 16)))"
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

// MARK: - SIM State
enum SimState: Equatable {
    case absent
    case ready
    case simPinRequired
    case simPukRequired
    case simPin2Required
    case simPuk2Required
    case phSimPinRequired
    case error
    case unknown

    var displayText: String {
        switch self {
        case .absent: return "无卡"
        case .ready, .simPinRequired, .simPukRequired, .simPin2Required, .simPuk2Required, .phSimPinRequired: return "有卡"
        case .error, .unknown: return "-"
        }
    }
}

// MARK: - Network Registration Status
enum NetworkRegistrationStatus: Equatable {
    case notRegistered
    case registered(isRoaming: Bool)
    case searching
    case registrationDenied
    case unknown

    var displayText: String {
        switch self {
        case .notRegistered: return "未注册"
        case .registered(let isRoaming): return isRoaming ? "漫游" : "登网"
        case .searching: return "搜网"
        case .registrationDenied: return "拒绝"
        case .unknown: return "未知"
        }
    }
}

// MARK: - Baseband Version
struct BasebandVersion {
    let imsi: String
    let ccid: String
    let softwareVersion: String
    let hardwareVersion: String
}
