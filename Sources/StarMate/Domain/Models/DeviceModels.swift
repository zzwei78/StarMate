import Foundation

// MARK: - Device Info
/// Complete device information from System Service
struct DeviceInfo: Equatable {
    let name: String
    let address: String
    let batteryLevel: Int         // 0-100
    let currentMa: Int            // Current in mA
    let voltageMv: Int            // Voltage in mV
    let signalStrength: Int       // 0-5 bars (from AT+CSQ when TT Working)
    let isRegistered: Bool        // true if regStatus 1 or 5
    let regStatus: Int            // 0=未注册, 1=已注册, 2=搜索中, 3=拒绝, 4=未知, 5=漫游
    let satelliteMode: SatelliteMode
    let workMode: WorkMode
}

// MARK: - Terminal Version
/// Terminal version info from BLE GATT System Service (96 bytes)
struct TerminalVersion: Equatable {
    let hardwareVersion: String
    let softwareVersion: String
    let firmwareVersion: String
    let manufacturer: String
    let modelNumber: String
}

// MARK: - System Info
/// System info from GATT System Service
struct SystemInfo: Equatable {
    let deviceName: String
    let hardwareVersion: String
    let softwareVersion: String
    let mcuVersion: String
    let moduleVersion: String
}

// MARK: - Battery Info
/// Battery info from System Service
struct BatteryInfo: Equatable {
    let level: Int               // 0-100
    let voltage: Int             // mV
    let current: Int             // mA (can be negative when discharging)
    let isCharging: Bool
    let isWirelessCharging: Bool
}

// MARK: - Signal Info
/// Signal info: strength from AT+CSQ, registration from AT+CREG
struct SignalInfo: Equatable {
    let strength: Int            // 0-5 bars (mapped from rssi dBm)
    let ber: Int                 // reserved / 0
    let isRegistered: Bool
    let regStatus: Int           // 0=not, 1=home, 2=searching, 3=denied, 4=unknown, 5=roaming
}

// MARK: - Satellite Mode
/// Satellite working mode
enum SatelliteMode: String, Codable {
    case normal
    case transparent
    case otaUpgrade
}

// MARK: - Work Mode
/// Device work mode
enum WorkMode: String, Codable {
    case idle
    case calling
    case dataTransfer
}
