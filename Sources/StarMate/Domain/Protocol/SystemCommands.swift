import Foundation

// MARK: - System Service Command Codes
/// System Service command codes for TTCat BLE protocol v3.3
/// All commands are sent via SYSTEM_CONTROL characteristic (0xABFD)
enum SystemCommands {
    // ========== Battery and Charging ==========
    /// Get battery info (voltage, current, SOC, charging status)
    static let CMD_GET_BATTERY_INFO: UInt8 = 0x01
    /// Get charge status
    static let CMD_GET_CHARGE_STATUS: UInt8 = 0x02
    /// Get TT signal (deprecated - use AT+CSQ instead)
    static let CMD_GET_TT_SIGNAL: UInt8 = 0x03

    // ========== Service Management ==========
    /// Start a service (OTA, Voice, etc.)
    static let CMD_SERVICE_START: UInt8 = 0x10
    /// Stop a service
    static let CMD_SERVICE_STOP: UInt8 = 0x11
    /// Get service status
    static let CMD_SERVICE_STATUS: UInt8 = 0x12

    // ========== System Control ==========
    /// System reboot
    static let CMD_SYSTEM_REBOOT: UInt8 = 0x20
    /// Reboot MCU
    static let CMD_REBOOT_MCU: UInt8 = 0x22
    /// Reboot TT Module
    static let CMD_REBOOT_TT: UInt8 = 0x23

    // ========== System Info ==========
    /// Get system info (device name, versions)
    static let CMD_GET_SYSTEM_INFO: UInt8 = 0x30
    /// Get version info (96-byte system_version_info_t)
    static let CMD_GET_VERSION_INFO: UInt8 = 0x31

    // ========== TT Module Management (v3.1) ==========
    /// Get TT Module status (state, voltage, error code)
    static let CMD_GET_TT_STATUS: UInt8 = 0x60
    /// Set TT Module power (on/off)
    static let CMD_SET_TT_POWER: UInt8 = 0x61
}

// MARK: - Service IDs
/// Service ID definitions for CMD_SERVICE_START / CMD_SERVICE_STOP / CMD_SERVICE_STATUS
/// Request format: [seq][cmd][0x01][service_id][crc16]
enum ServiceId {
    /// OTA service (0xABF8)
    static let OTA: UInt8 = 0x01
    /// Log service
    static let LOG: UInt8 = 0x02
    /// AT service (0xABF2)
    static let AT: UInt8 = 0x03
    /// SPP voice service (GATT 0xABF0)
    static let SPP_VOICE: UInt8 = 0x04
    /// Voice task control
    static let VOICE_TASK: UInt8 = 0x05
}

// MARK: - Response Codes
/// System Service response codes
enum SystemResponseCode: UInt8 {
    /// Success
    case success = 0x00
    /// Invalid command
    case invalidCmd = 0x01
    /// Invalid parameter
    case invalidParam = 0x02
    /// Not supported
    case notSupported = 0x03
    /// Timeout
    case timeout = 0x04
    /// Busy
    case busy = 0x05
    /// Error
    case error = 0xFF
}

// MARK: - Audio Configuration
/// Audio configuration constants for Voice Service
enum AudioConfig {
    /// Sample rate: 8kHz
    static let SAMPLE_RATE = 8000
    /// Bit depth: 16-bit
    static let BIT_DEPTH = 16
    /// Channels: Mono
    static let CHANNELS = 1
    /// Frame duration: 20ms
    static let FRAME_DURATION_MS = 20
    /// PCM frame size: 320 bytes (20ms @ 8kHz 16bit)
    static let PCM_FRAME_SIZE = 320
    /// AMR frame size: ~33 bytes (AMR-NB 12.2kbps)
    static let AMR_FRAME_SIZE = 33
}
