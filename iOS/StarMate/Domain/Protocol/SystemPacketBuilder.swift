import Foundation

// MARK: - System Packet Builder
/// Builder for System Service command packets.
///
/// Command packet format (device expects SEQ first, then CMD):
/// ┌──────┬──────┬──────────┬──────┬───────┐
/// │ SEQ  │ CMD  │ DATA_LEN │ DATA │ CRC16 │
/// │ 1字节│ 1字节│   1字节  │ N字节│ 2字节 │
/// └──────┴──────┴──────────┴──────┴───────┘
/// Minimum packet size: 5 bytes (no data)
///
/// Response packet format:
/// ┌──────┬──────────┬────────┬──────────┬──────┬───────┐
/// │ SEQ  │ RESP_CODE│ RESULT │ DATA_LEN │ DATA │ CRC16 │
/// │ 1字节│   1字节  │  1字节 │   1字节  │ N字节│ 2字节 │
/// └──────┴──────────┴────────┴──────────┴──────┴───────┘
/// Note: Some responses may have 4-byte header (no RESULT byte).
/// Data always starts at offset 4.
///
/// CRC on response is not verified (GATT system/OTA server may ignore CRC).
///
final class SystemPacketBuilder {
    // MARK: - Constants

    /// Maximum data size per protocol
    private static let MAX_DATA_SIZE = 240

    /// Maximum response data length
    private static let MAX_RESPONSE_DATA_LEN = 96

    /// Response data offset (data always at index 4)
    private static let RESPONSE_DATA_OFFSET = 4

    /// Response CRC size
    private static let RESPONSE_CRC_SIZE = 2

    /// Minimum header size: SEQ + RESP_CODE + RESULT + DATA_LEN
    private static let MIN_HEADER_SIZE = 4

    // MARK: - State

    /// Sequence number counter (wraps at 255)
    private static var sequenceNumber: UInt8 = 0

    // MARK: - Command Building

    /// Reset sequence counter (call on new connection)
    static func resetSequence() {
        sequenceNumber = 0
    }

    /// Get current sequence number
    static func currentSequence() -> UInt8 {
        return sequenceNumber
    }

    /// Build a System Service command packet with CRC16-CCITT.
    /// Device firmware expects: SEQ(1) + CMD(1) + DATA_LEN(1) + DATA(0-N) + CRC16(2)
    /// Minimum packet size: 5 bytes (no data)
    /// - Parameters:
    ///   - cmd: Command byte (see SystemCommands)
    ///   - data: Optional data bytes (max 240 bytes)
    /// - Returns: Tuple of (packet, sequenceNumber)
    static func buildCommand(cmd: UInt8, data: Data = Data()) -> (packet: Data, seq: UInt8) {
        precondition(data.count <= MAX_DATA_SIZE, "Data size exceeds maximum of \(MAX_DATA_SIZE)")

        let seq = sequenceNumber
        sequenceNumber = (sequenceNumber &+ 1) & 0xFF

        // Build header: SEQ first, then CMD (device parses in this order)
        var header = Data()
        header.append(seq)
        header.append(cmd)
        header.append(UInt8(data.count))
        header.append(data)

        // Calculate CRC16-CCITT over header + data
        let crc = Crc16Ccitt.calculate(header)

        // Build final packet with CRC appended (Little Endian)
        var packet = header
        packet.append(UInt8(crc & 0xFF))        // LSB first
        packet.append(UInt8((crc >> 8) & 0xFF)) // MSB second

        return (packet, seq)
    }

    /// Build a service control command (start/stop/status)
    /// - Parameters:
    ///   - cmd: Command byte (CMD_SERVICE_START, CMD_SERVICE_STOP, or CMD_SERVICE_STATUS)
    ///   - serviceId: Service ID (see ServiceId)
    /// - Returns: Complete packet with CRC
    static func buildServiceCommand(cmd: UInt8, serviceId: UInt8) -> (packet: Data, seq: UInt8) {
        var data = Data()
        data.append(0x01)        // param count = 1
        data.append(serviceId)   // service ID
        return buildCommand(cmd: cmd, data: data)
    }

    // MARK: - Response Parsing

    /// Parsed System Service response
    struct ParsedResponse {
        /// Response code (echo of command or response type)
        let respCode: UInt8
        /// Sequence number (matches request)
        let seq: UInt8
        /// Response data bytes
        let data: Data
        /// Result code (0x00 = success)
        let resultCode: UInt8
        /// CRC valid flag (always true - we skip CRC verification per protocol)
        let crcValid: Bool

        /// Check if response indicates success
        var isSuccess: Bool {
            return resultCode == 0x00
        }
    }

    /// Parse a System Service response packet.
    /// Accepts both 4-byte and 5-byte header formats.
    /// Data always at index 4.
    /// - Parameter packet: Raw response packet
    /// - Returns: Parsed response or nil if invalid
    static func parseResponse(_ packet: Data) -> ParsedResponse? {
        print("[SysPacketBuilder] parseResponse called with \(packet.count) bytes: \(packet as NSData)")

        guard packet.count >= 6 else {
            print("[SysPacketBuilder] Response too short: \(packet.count) bytes")
            return nil
        }

        let seq = packet[0]
        let respCode = packet[1]
        let result = packet[2].toInt() & 0xFF
        let dataLen = min(packet[3].toInt(), MAX_RESPONSE_DATA_LEN)

        print("[SysPacketBuilder] seq=\(seq), respCode=\(respCode), result=\(result), dataLen=\(dataLen), totalBytes=\(packet.count)")

        let minExpectedLen = MIN_HEADER_SIZE + dataLen + RESPONSE_CRC_SIZE
        guard packet.count >= minExpectedLen else {
            print("[SysPacketBuilder] Response truncated: expected \(minExpectedLen), got \(packet.count)")
            return nil
        }

        if result != 0x00 {
            print("[SysPacketBuilder] Device returned error code: 0x\(String(result, radix: 16))")
        }

        // GATT System/OTA server: skip CRC verification per product requirement
        let crcMatch = true

        // Extract data bytes (data at offset 4 per doc)
        let dataStart = RESPONSE_DATA_OFFSET
        let dataEnd = min(dataStart + dataLen, packet.count - RESPONSE_CRC_SIZE)
        let data: Data
        if dataLen > 0 && dataEnd > dataStart {
            data = packet.subdata(in: dataStart..<dataEnd)
        } else {
            data = Data()
        }

        return ParsedResponse(
            respCode: respCode,
            seq: seq,
            data: data,
            resultCode: UInt8(result),
            crcValid: crcMatch
        )
    }

    /// Calculate the total packet length for a response
    /// - Parameter parsed: Parsed response
    /// - Returns: Total byte count of the packet
    static func packetLength(for parsed: ParsedResponse) -> Int {
        // 4-byte header + data + 2-byte CRC
        return MIN_HEADER_SIZE + parsed.data.count + RESPONSE_CRC_SIZE
    }
}

// MARK: - Data Extension for Safe Int Conversion

internal extension UInt8 {
    func toInt() -> Int {
        return Int(self)
    }
}
