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

// MARK: - Complete UUID Definitions with 128-bit Format
/// Complete BLE UUID definitions for TTCat GATT services and characteristics.
/// Based on TTCat_BLE_Protocol_V3.3
/// All UUIDs use the standard Bluetooth Base: 0000XXXX-0000-1000-8000-00805F9B34FB
enum BleUuid {
    // ========== Services (128-bit) ==========
    /// System Service: 0xABFC
    static let SYSTEM_SERVICE: CBUUID = CBUUID(string: "ABFC")
    /// AT Command Service: 0xABF2
    static let AT_SERVICE: CBUUID = CBUUID(string: "ABF2")
    /// Voice Service: 0xABF0
    static let VOICE_SERVICE: CBUUID = CBUUID(string: "ABF0")
    /// OTA Service: 0xABF8
    static let OTA_SERVICE: CBUUID = CBUUID(string: "ABF8")

    // ========== System Service Characteristics (0xABFC) ==========
    /// System Control - Write + Notify (0xABFD)
    static let SYSTEM_CONTROL: CBUUID = CBUUID(string: "ABFD")
    /// System Info - Read only, 96 bytes (0xABFE)
    static let SYSTEM_INFO: CBUUID = CBUUID(string: "ABFE")
    /// System Status - Notify (0xABFF)
    static let SYSTEM_STATUS: CBUUID = CBUUID(string: "ABFF")

    // ========== AT Service Characteristics (0xABF2) ==========
    /// AT Command - Write + Notify (0xABF3)
    static let AT_COMMAND: CBUUID = CBUUID(string: "ABF3")
    /// AT Response - Notify (0xABF1)
    /// Note: Also used by Voice Service for voice data when under Voice Service context
    static let AT_RESPONSE: CBUUID = CBUUID(string: "ABF1")

    // ========== Voice Service Characteristics (0xABF0) ==========
    /// Voice In - Write (send audio to device) (0xABEE)
    static let VOICE_IN: CBUUID = CBUUID(string: "ABEE")
    /// Voice Out - Notify (receive audio from device) (0xABEF)
    static let VOICE_OUT: CBUUID = CBUUID(string: "ABEF")
    /// Voice Data - Write + Notify (fallback when device exposes only one char) (0xABF1)
    /// Note: Same UUID as AT_RESPONSE, distinguish by service UUID
    static let VOICE_DATA: CBUUID = CBUUID(string: "ABF1")

    // ========== OTA Service Characteristics (0xABF8) ==========
    /// OTA Control - Write (start/abort commands) (0xABF9)
    static let OTA_CONTROL: CBUUID = CBUUID(string: "ABF9")
    /// OTA Data - Write (firmware packets) (0xABFA)
    static let OTA_DATA: CBUUID = CBUUID(string: "ABFA")
    /// OTA Status - Notify (progress updates) (0xABFB)
    static let OTA_STATUS: CBUUID = CBUUID(string: "ABFB")

    // ========== Standard Descriptors ==========
    /// Client Characteristic Configuration Descriptor (0x2902)
    static let CCC_DESCRIPTOR: CBUUID = CBUUID(string: "2902")

    // ========== Device Filter ==========
    /// Device name prefix for scanning
    static let DEVICE_NAME_FILTER = "TTCat"

    // ========== Service UUID Arrays for Discovery ==========
    /// All service UUIDs for discovery
    static let ALL_SERVICES: [CBUUID] = [
        SYSTEM_SERVICE,
        AT_SERVICE,
        VOICE_SERVICE,
        OTA_SERVICE
    ]
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
