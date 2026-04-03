import Foundation
import CoreBluetooth

// MARK: - Bluetooth Service UUIDs
struct BluetoothService {
    // TTCat Service UUID - 请根据实际设备修改
    static let serviceUUID = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")

    // Characteristic UUIDs - 请根据实际设备修改
    struct Characteristic {
        static let deviceInfo = CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")      // 设备信息
        static let batteryStatus = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")    // 电池状态
        static let signalStatus = CBUUID(string: "0000FFF3-0000-1000-8000-00805F9B34FB")     // 信号状态
        static let moduleStatus = CBUUID(string: "0000FFF4-0000-1000-8000-00805F9B34FB")     // 模块状态
        static let networkStatus = CBUUID(string: "0000FFF5-0000-1000-8000-00805F9B34FB")    // 网络状态
        static let command = CBUUID(string: "0000FFF6-0000-1000-8000-00805F9B34FB")          // 命令发送
    }

    // Command codes
    struct Command {
        static let getDeviceInfo: Data = Data([0x01, 0x01])
        static let getBatteryStatus: Data = Data([0x01, 0x02])
        static let getSignalStatus: Data = Data([0x01, 0x03])
        static let getModuleStatus: Data = Data([0x01, 0x04])
        static let getNetworkStatus: Data = Data([0x01, 0x05])
    }
}
