import Foundation

// MARK: - CRC16-CCITT
/// CRC16-CCITT checksum calculator for System Service packets.
/// Polynomial: 0x1021, Initial: 0xFFFF, Little Endian output
struct Crc16Ccitt {
    private static let POLYNOMIAL: UInt16 = 0x1021
    private static let INITIAL: UInt16 = 0xFFFF

    /// Calculate CRC16-CCITT checksum
    /// - Parameter data: Input data
    /// - Returns: CRC16 value as UInt16 (Little Endian when written to packet)
    static func calculate(_ data: Data) -> UInt16 {
        var crc = INITIAL
        for byte in data {
            crc = crc ^ (UInt16(byte) << 8)
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ POLYNOMIAL
                } else {
                    crc = crc << 1
                }
                crc = crc & 0xFFFF
            }
        }
        return crc
    }

    /// Calculate CRC16-CCITT and append as Little Endian bytes
    /// - Parameter data: Input data
    /// - Returns: CRC16 as 2 bytes (Little Endian: LSB first)
    static func calculateBytes(_ data: Data) -> Data {
        let crc = calculate(data)
        var result = Data()
        result.append(UInt8(crc & 0xFF))        // LSB first
        result.append(UInt8((crc >> 8) & 0xFF)) // MSB second
        return result
    }
}

// MARK: - CRC16-MODBUS
/// CRC16-MODBUS checksum calculator for OTA data packets.
/// Polynomial: 0xA001, Initial: 0xFFFF
struct Crc16Modbus {
    private static let POLYNOMIAL: UInt16 = 0xA001
    private static let INITIAL: UInt16 = 0xFFFF

    /// Calculate CRC16-MODBUS checksum
    /// - Parameter data: Input data
    /// - Returns: CRC16 value as UInt16
    static func calculate(_ data: Data) -> UInt16 {
        var crc = INITIAL
        for byte in data {
            crc = crc ^ UInt16(byte)
            for _ in 0..<8 {
                if (crc & 0x0001) != 0 {
                    crc = (crc >> 1) ^ POLYNOMIAL
                } else {
                    crc = crc >> 1
                }
            }
        }
        return crc
    }

    /// Calculate CRC16-MODBUS and append as Little Endian bytes
    /// - Parameter data: Input data
    /// - Returns: CRC16 as 2 bytes (Little Endian: LSB first)
    static func calculateBytes(_ data: Data) -> Data {
        let crc = calculate(data)
        var result = Data()
        result.append(UInt8(crc & 0xFF))        // LSB first
        result.append(UInt8((crc >> 8) & 0xFF)) // MSB second
        return result
    }
}
