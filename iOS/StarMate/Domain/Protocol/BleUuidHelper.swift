import Foundation
import CoreBluetooth

// MARK: - BLE UUID Helper
/// Helper functions for BLE UUID handling
enum BleUuidHelper {

    /// Build 128-bit UUID from 16-bit short UUID.
    /// Standard Bluetooth Base UUID: 0000XXXX-0000-1000-8000-00805F9B34FB
    /// - Parameter shortUuid: 16-bit UUID value
    /// - Returns: CBUUID for the 128-bit UUID
    static func uuid(from16Bit shortUuid: UInt16) -> CBUUID {
        return CBUUID(string: String(format: "%04X", shortUuid))
    }

    /// Build 128-bit UUID string from 16-bit short UUID
    /// - Parameter shortUuid: 16-bit UUID value
    /// - Returns: Full 128-bit UUID string
    static func uuidString(from16Bit shortUuid: UInt16) -> String {
        return String(format: "0000%04X-0000-1000-8000-00805F9B34FB", shortUuid)
    }

    /// Extract 16-bit short UUID from CBUUID
    /// - Parameter uuid: CBUUID value
    /// - Returns: 16-bit UUID value or nil
    static func extract16Bit(from uuid: CBUUID) -> UInt16? {
        let uuidString = uuid.uuidString

        // Standard 16-bit UUID (4 hex characters)
        if uuidString.count == 4 {
            return UInt16(uuidString, radix: 16)
        }

        // 128-bit UUID - extract the 16-bit part
        if uuidString.count == 36 {
            let shortPart = String(uuidString.prefix(8).suffix(4))
            return UInt16(shortPart, radix: 16)
        }

        return nil
    }
}

// MARK: - UUID Debug Extension
extension CBUUID {
    /// Short UUID string for logging (e.g., "ABFC" instead of full 128-bit)
    var shortString: String {
        let str = uuidString
        if str.count == 4 {
            return "0x\(str)"
        } else if str.count == 36 {
            // Extract the XXXX part from 0000XXXX-0000-1000-8000-00805F9B34FB
            let shortPart = String(str.prefix(8).suffix(4))
            return "0x\(shortPart)"
        }
        return str
    }
}
