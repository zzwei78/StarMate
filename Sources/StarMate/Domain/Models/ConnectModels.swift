import Foundation

// MARK: - BLE Connection State
/// BLE connection state machine
enum ConnectState: Equatable {
    case disconnected
    case connecting(deviceAddress: String)
    case connected(deviceAddress: String, mtu: Int)
    case error(errorCode: Int, message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var deviceAddress: String? {
        switch self {
        case .connecting(let addr), .connected(let addr, _):
            return addr
        default:
            return nil
        }
    }
}

// MARK: - Device Connection State
/// Device connection state including scanning phase
enum DeviceConnectionState: Equatable {
    case disconnected
    case scanning(devices: [ScannedDevice])
    case connecting(deviceAddress: String)
    case connected(device: DeviceInfo)
    case error(error: DeviceError)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Scanned Device
/// Scanned BLE device info
struct ScannedDevice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String
    let rssi: Int
}

// MARK: - Device Error
/// Device error types
enum DeviceError: Equatable {
    case connectionFailed(reason: String)
    case serviceNotFound(uuid: String)
    case scanTimeout
    case bleDisabled
    case unknown(message: String)
}
