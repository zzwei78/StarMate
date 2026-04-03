import Foundation
import CoreBluetooth

// MARK: - BLE UUID Definitions
/// Complete BLE UUID definitions for TTCat GATT services and characteristics.
/// Based on TTCat_BLE_Protocol_V3.3
enum BleUuid {
    // ========== Services ==========
    static let SYSTEM_SERVICE: CBUUID = CBUUID(string: "ABFC")
    static let AT_SERVICE: CBUUID = CBUUID(string: "ABF2")
    static let VOICE_SERVICE: CBUUID = CBUUID(string: "ABF0")
    static let OTA_SERVICE: CBUUID = CBUUID(string: "ABF8")

    // ========== System Service Characteristics (0xABFC) ==========
    /// System Control - Write + Notify
    static let SYSTEM_CONTROL: CBUUID = CBUUID(string: "ABFD")
    /// System Info - Read only (96 bytes version info)
    static let SYSTEM_INFO: CBUUID = CBUUID(string: "ABFE")
    /// System Status - Notify
    static let SYSTEM_STATUS: CBUUID = CBUUID(string: "ABFF")

    // ========== AT Service Characteristics (0xABF2) ==========
    /// AT Command - Write + Notify
    static let AT_COMMAND: CBUUID = CBUUID(string: "ABF3")
    /// AT Response - Notify
    static let AT_RESPONSE: CBUUID = CBUUID(string: "ABF1")

    // ========== Voice Service Characteristics (0xABF0) ==========
    /// Voice In - Write (send audio to device)
    static let VOICE_IN: CBUUID = CBUUID(string: "ABEE")
    /// Voice Out - Notify (receive audio from device)
    static let VOICE_OUT: CBUUID = CBUUID(string: "ABEF")
    /// Voice Data - Write + Notify (fallback when device exposes only one char)
    static let VOICE_DATA: CBUUID = CBUUID(string: "ABF1")

    // ========== OTA Service Characteristics (0xABF8) ==========
    /// OTA Control - Write (start/abort commands)
    static let OTA_CONTROL: CBUUID = CBUUID(string: "ABF9")
    /// OTA Data - Write (firmware packets)
    static let OTA_DATA: CBUUID = CBUUID(string: "ABFA")
    /// OTA Status - Notify (progress updates)
    static let OTA_STATUS: CBUUID = CBUUID(string: "ABFB")

    // ========== Client Characteristic Configuration Descriptor ==========
    static let CCC_DESCRIPTOR: CBUUID = CBUUID(string: "2902")

    // Device name filter for scanning
    static let DEVICE_NAME_FILTER = "TTCat"
}

// MARK: - BleUuid Extension for Protocol Usage
extension BleUuid {
    /// All service UUIDs for discovery
    static let ALL_SERVICES: [CBUUID] = [
        SYSTEM_SERVICE,
        AT_SERVICE,
        VOICE_SERVICE,
        OTA_SERVICE
    ]

    /// Voice service characteristics for discovery
    static let VOICE_CHARS: [CBUUID] = [
        VOICE_IN,
        VOICE_OUT,
        VOICE_DATA
    ]

    /// OTA service characteristics for discovery
    static let OTA_CHARS: [CBUUID] = [
        OTA_CONTROL,
        OTA_DATA,
        OTA_STATUS
    ]
}
