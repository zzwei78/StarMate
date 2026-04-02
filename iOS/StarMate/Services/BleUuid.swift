import Foundation
import CoreBluetooth

// MARK: - BLE UUID Definitions
/// Complete BLE UUID definitions for TTCat GATT services and characteristics.
/// Based on TTCat_BLE_Protocol_V3.3
struct BleUuid {
    // ========== Services ==========
    static let SYSTEM_SERVICE = CBUUID(string: "ABFC")
    static let AT_SERVICE = CBUUID(string: "ABF2")
    static let VOICE_SERVICE = CBUUID(string: "ABF0")
    static let OTA_SERVICE = CBUUID(string: "ABF8")

    // ========== System Service Characteristics ==========
    static let SYSTEM_CONTROL = CBUUID(string: "ABFD")
    static let SYSTEM_INFO = CBUUID(string: "ABFE")
    static let SYSTEM_STATUS = CBUUID(string: "ABFF")

    // ========== AT Service Characteristics ==========
    static let AT_COMMAND = CBUUID(string: "ABF3")
    static let AT_RESPONSE = CBUUID(string: "ABF1")

    // ========== Voice Service Characteristics ==========
    static let VOICE_IN = CBUUID(string: "ABEE")
    static let VOICE_OUT = CBUUID(string: "ABEF")
    static let VOICE_DATA = CBUUID(string: "ABF1")  // fallback when device exposes only one char

    // ========== OTA Service Characteristics ==========
    static let OTA_CONTROL = CBUUID(string: "ABF9")
    static let OTA_DATA = CBUUID(string: "ABFA")
    static let OTA_STATUS = CBUUID(string: "ABFB")

    // ========== Client Characteristic Configuration Descriptor ==========
    static let CCC_DESCRIPTOR = CBUUID(string: "2902")

    // Device name filter for scanning
    static let DEVICE_NAME_FILTER = "TTCat"
}

// MARK: - System Commands
struct SystemCommands {
    static let CMD_GET_SYSTEM_INFO: UInt8 = 0x01
    static let CMD_GET_VERSION_INFO: UInt8 = 0x31
    static let CMD_GET_BATTERY_INFO: UInt8 = 0x02
    static let CMD_GET_TT_SIGNAL: UInt8 = 0x03
    static let CMD_SERVICE_START: UInt8 = 0x10
    static let CMD_SERVICE_STOP: UInt8 = 0x11
    static let CMD_SERVICE_STATUS: UInt8 = 0x12
    static let CMD_REBOOT_MCU: UInt8 = 0x20
    static let CMD_REBOOT_TT: UInt8 = 0x21
    static let CMD_GET_TT_STATUS: UInt8 = 0x60
    static let CMD_SET_TT_POWER: UInt8 = 0x61
}

// MARK: - Service IDs
struct ServiceId {
    static let SPP_VOICE: UInt8 = 0x01
    static let OTA: UInt8 = 0x02
}

// MARK: - CRC16-CCITT
struct Crc16 {
    /// Calculate CRC16-CCITT (poly=0x1021, init=0xFFFF)
    static func calculate(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}

// MARK: - System Packet Builder
class SystemPacketBuilder {
    private static var sequenceNumber: UInt8 = 0

    static func resetSequence() {
        sequenceNumber = 0
    }

    /// Build a command packet: SEQ + CMD + DATA_LEN + DATA + CRC16
    static func buildCommand(cmd: UInt8, data: Data = Data()) -> Data {
        var packet = Data()

        // Increment sequence (wrap at 255)
        sequenceNumber = (sequenceNumber &+ 1) & 0xFF
        packet.append(sequenceNumber)

        // Command byte
        packet.append(cmd)

        // Data length (1 byte)
        packet.append(UInt8(data.count))

        // Data
        packet.append(data)

        // CRC16-CCITT
        let crc = Crc16.calculate(packet)
        packet.append(UInt8(crc & 0xFF))
        packet.append(UInt8((crc >> 8) & 0xFF))

        return packet
    }

    /// Parse a response packet
    struct ParsedResponse {
        let seq: UInt8
        let respCode: UInt8
        let resultCode: UInt8
        let dataLen: UInt8
        let data: Data
    }

    /// Parse response: SEQ + RESP_CODE + RESULT + DATA_LEN + DATA + CRC16
    /// Or: SEQ + RESP_CODE + DATA_LEN + DATA + CRC16 (4-byte header)
    static func parseResponse(_ packet: Data) -> ParsedResponse? {
        guard packet.count >= 6 else { return nil }

        let seq = packet[0]
        let respCode = packet[1]

        // Try 5-byte header first (SEQ + RESP + RESULT + LEN + DATA + CRC)
        if packet.count >= 7 {
            let result = packet[2]
            let dataLen = min(packet[3], 96)
            let expectedLen = 5 + Int(dataLen) + 2

            if packet.count >= expectedLen {
                let dataStart = 4
                let dataEnd = dataStart + Int(dataLen)
                let data = packet.subdata(in: dataStart..<dataEnd)

                // Verify CRC
                let crcData = packet.subdata(in: 0..<(expectedLen - 2))
                let receivedCrc = UInt16(packet[expectedLen - 2]) | (UInt16(packet[expectedLen - 1]) << 8)
                let calculatedCrc = Crc16.calculate(crcData)

                if receivedCrc == calculatedCrc {
                    return ParsedResponse(seq: seq, respCode: respCode, resultCode: result, dataLen: dataLen, data: data)
                }
            }
        }

        // Try 4-byte header (SEQ + RESP + LEN + DATA + CRC)
        let dataLen = min(packet[2], 96)
        let expectedLen = 4 + Int(dataLen) + 2

        guard packet.count >= expectedLen else { return nil }

        let dataStart = 3
        let dataEnd = dataStart + Int(dataLen)
        let data = packet.subdata(in: dataStart..<dataEnd)

        // Verify CRC
        let crcData = packet.subdata(in: 0..<(expectedLen - 2))
        let receivedCrc = UInt16(packet[expectedLen - 2]) | (UInt16(packet[expectedLen - 1]) << 8)
        let calculatedCrc = Crc16.calculate(crcData)

        guard receivedCrc == calculatedCrc else { return nil }

        return ParsedResponse(seq: seq, respCode: respCode, resultCode: 0, dataLen: dataLen, data: data)
    }
}
