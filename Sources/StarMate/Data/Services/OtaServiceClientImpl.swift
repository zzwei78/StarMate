import Foundation
import CoreBluetooth
import Combine

// MARK: - OTA Service Client Implementation
/// GATT OTA Service client (UUID: 0xABF8).
/// Handles MCU and TT Module firmware upgrades.
///
/// Service Characteristics:
/// - OTA Control (0xABF9): Write - start/abort commands
/// - OTA Data (0xABFA): Write - firmware packets
/// - OTA Status (0xABFB): Notify - progress updates
///
/// Protocol:
/// 1. Enable OTA service via System Service (CMD_SERVICE_START to 0xABFD)
/// 2. Subscribe to OTA Control (0xABF9) and Status (0xABFB) notifications
/// 3. Write OTA START packet to 0xABF9
/// 4. Wait 1 second for device to prepare
/// 5. Send firmware packets to 0xABFA
/// 6. Device sends status updates via 0xABFB
@MainActor
final class OtaServiceClientImpl: OtaServiceClientProtocol {

    // MARK: - Constants
    private enum Constants {
        // OTA Control Commands
        static let OTA_CMD_START_MCU: UInt8 = 0x01
        static let OTA_CMD_START_TT: UInt8 = 0x02
        static let OTA_CMD_ABORT: UInt8 = 0x03

        // OTA Status Codes (from device)
        static let OTA_STATUS_IDLE: UInt8 = 0x00
        static let OTA_STATUS_WRITING: UInt8 = 0x01
        static let OTA_STATUS_VERIFYING: UInt8 = 0x02
        static let OTA_STATUS_SUCCESS: UInt8 = 0x03
        static let OTA_STATUS_FAILED: UInt8 = 0x04

        // Packet Configuration
        static let OTA_PACKET_DATA_SIZE = 480  // Max data per packet (protocol spec: 0-500)
        static let OTA_START_PACKET_SIZE = 12   // CMD + reserved + size + crc32

        // Timing
        static let START_DELAY_MS: UInt64 = 1000  // 1s gap after START command
        static let PACKET_DELAY_MS: UInt64 = 20    // 20ms between packets
        static let WRITE_TIMEOUT_MS: Int64 = 5000  // 5s write timeout
    }

    // MARK: - Published State
    private let _otaState = CurrentValueSubject<OtaState, Never>(.idle)
    var otaState: CurrentValueSubject<OtaState, Never> { _otaState }

    // MARK: - Progress Stream
    private var progressContinuation: AsyncStream<Int>.Continuation?
    lazy var progressStream: AsyncStream<Int> = {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }()

    // MARK: - Private Properties
    private weak var peripheral: CBPeripheral?
    private var otaControlChar: CBCharacteristic?
    private var otaDataChar: CBCharacteristic?
    private var otaStatusChar: CBCharacteristic?

    private var isOtaInProgress = false
    private var currentTarget: OtaTarget?
    private var firmwareData: Data?
    private var firmwareCrc32: UInt32 = 0
    private var currentPacketSeq: Int = 0
    private var totalPackets: Int = 0

    // MARK: - Initialization
    init() {}

    // MARK: - GATT Setup

    /// Set peripheral and characteristics after discovery
    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral

        for char in characteristics {
            switch char.uuid {
            case BleUuid.OTA_CONTROL:
                otaControlChar = char
                peripheral.setNotifyValue(true, for: char)
                print("[OtaService] ✅ OTA Control characteristic found, notifications enabled (0xABF9)")
            case BleUuid.OTA_DATA:
                otaDataChar = char
                print("[OtaService] ✅ OTA Data characteristic found (0xABFA)")
            case BleUuid.OTA_STATUS:
                otaStatusChar = char
                peripheral.setNotifyValue(true, for: char)
                print("[OtaService] ✅ OTA Status characteristic found, notifications enabled (0xABFB)")
            default:
                break
            }
        }
    }

    /// Clear GATT references on disconnect
    func clearGattReferences() {
        peripheral = nil
        otaControlChar = nil
        otaDataChar = nil
        otaStatusChar = nil

        // If OTA was in progress, mark as failed
        if isOtaInProgress {
            _otaState.send(.failed(reason: "BLE disconnected"))
            isOtaInProgress = false
            print("[OtaService] OTA aborted: BLE disconnected")
        }
    }

    // MARK: - Protocol: OtaServiceClientProtocol

    func onGattClosed() {
        clearGattReferences()
    }

    // MARK: - Notification Handling

    /// Handle notification data from BLEManager
    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        guard !data.isEmpty else { return }

        let statusByte = data[0]
        let newState: OtaState

        switch statusByte {
        case Constants.OTA_STATUS_IDLE:
            newState = .idle

        case Constants.OTA_STATUS_WRITING:
            let progress = data.count >= 2 ? Int(data[1]) : 0
            newState = .writing(progress: progress)
            progressContinuation?.yield(progress)

        case Constants.OTA_STATUS_VERIFYING:
            newState = .verifying

        case Constants.OTA_STATUS_SUCCESS:
            newState = .success
            isOtaInProgress = false

        case Constants.OTA_STATUS_FAILED:
            let reason = data.count >= 2 ? "Error code: \(data[1])" : "Unknown"
            newState = .failed(reason: reason)
            isOtaInProgress = false

        default:
            newState = .failed(reason: "Unknown status: 0x\(String(statusByte, radix: 16))")
        }

        _otaState.send(newState)
        print("[OtaService] OTA status: \(newState)")
    }

    // MARK: - Start OTA

    func startMcuOta(_ firmware: Data, crc32: Int) async -> Result<Void, Error> {
        return await startOta(cmd: Constants.OTA_CMD_START_MCU, firmware: firmware, crc32: crc32)
    }

    func startTtOta(_ firmware: Data, crc32: Int) async -> Result<Void, Error> {
        return await startOta(cmd: Constants.OTA_CMD_START_TT, firmware: firmware, crc32: crc32)
    }

    private func startOta(cmd: UInt8, firmware: Data, crc32: Int) async -> Result<Void, Error> {
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        guard let controlChar = otaControlChar else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "OTA Control characteristic not found"]))
        }

        guard let dataChar = otaDataChar else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "OTA Data characteristic not found"]))
        }

        // Store firmware info
        self.firmwareData = firmware
        self.firmwareCrc32 = UInt32(crc32)
        self.currentTarget = cmd == Constants.OTA_CMD_START_MCU ? .mcu : .ttModule
        self.currentPacketSeq = 0
        self.totalPackets = (firmware.count + Constants.OTA_PACKET_DATA_SIZE - 1) / Constants.OTA_PACKET_DATA_SIZE
        self.isOtaInProgress = true

        print("[OtaService] Starting OTA: size=\(firmware.count), crc32=\(crc32), target=\(currentTarget!)")

        // Step 1: Build and send START packet (12 bytes)
        let startPacket = buildStartPacket(cmd: cmd, firmwareSize: firmware.count, crc32: crc32)
        let hexStr = startPacket.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        print("[OtaService] Sending OTA START to 0xABF9 (12 bytes): [\(hexStr)]")

        peripheral.writeValue(startPacket, for: controlChar, type: .withResponse)

        // Wait 1 second for device to prepare
        try? await Task.sleep(nanoseconds: Constants.START_DELAY_MS * 1_000_000)
        print("[OtaService] Delay 1s complete, now sending firmware to 0xABFA")

        _otaState.send(.writing(progress: 0))

        // Step 2: Send firmware packets
        for seq in 0..<totalPackets {
            // Check if still connected
            guard self.peripheral != nil else {
                _otaState.send(.failed(reason: "BLE disconnected during OTA"))
                return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "BLE disconnected during OTA"]))
            }

            // Check if OTA was aborted or failed
            if case .failed(let reason) = _otaState.value {
                return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: reason]))
            }
            if case .success = _otaState.value {
                // Device already reported success
                print("[OtaService] Device already reported Success")
                return .success(())
            }

            // Get chunk
            let offset = seq * Constants.OTA_PACKET_DATA_SIZE
            let length = min(Constants.OTA_PACKET_DATA_SIZE, firmware.count - offset)
            let chunk = firmware.subdata(in: offset..<offset+length)

            // Send packet
            let result = await sendFirmwarePacket(seq: seq, data: chunk)
            switch result {
            case .success:
                break
            case .failure(let error):
                // Check if device already reported status
                if case .success = _otaState.value {
                    print("[OtaService] Packet write failed but device reported Success")
                    return .success(())
                }
                if case .failed(let reason) = _otaState.value {
                    return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: reason]))
                }
                return .failure(error)
            }

            // Update progress
            currentPacketSeq = seq + 1
            let progress = (currentPacketSeq * 100) / totalPackets
            _otaState.send(.writing(progress: progress))
            progressContinuation?.yield(progress)

            // Delay between packets
            try? await Task.sleep(nanoseconds: Constants.PACKET_DELAY_MS * 1_000_000)
        }

        print("[OtaService] Firmware upload complete, waiting for verification")
        _otaState.send(.verifying)

        return .success(())
    }

    // MARK: - Abort OTA

    func abortOta() async -> Result<Void, Error> {
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        guard let controlChar = otaControlChar else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "OTA Control characteristic not found"]))
        }

        let abortPacket = Data([Constants.OTA_CMD_ABORT])
        peripheral.writeValue(abortPacket, for: controlChar, type: .withResponse)

        _otaState.send(.idle)
        isOtaInProgress = false
        print("[OtaService] OTA aborted")

        return .success(())
    }

    // MARK: - Reset State

    func resetOtaState() {
        _otaState.send(.idle)
        isOtaInProgress = false
        firmwareData = nil
        currentPacketSeq = 0
        print("[OtaService] OTA state reset to Idle (can retry)")
    }

    // MARK: - Send Firmware Packet

    func sendFirmwarePacket(seq: Int, data: Data) async -> Result<Void, Error> {
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        guard let dataChar = otaDataChar else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "OTA Data characteristic not found"]))
        }

        guard seq >= 0 else {
            return .failure(NSError(domain: "OtaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "OTA packet seq must be >= 0"]))
        }

        // Build packet: [SEQ(2,LE)][LENGTH(2,LE)][DATA][CRC16-MODBUS(2,LE)]
        let packet = buildFirmwarePacket(seq: seq, data: data)

        // Write with response to ensure ordered delivery
        peripheral.writeValue(packet, for: dataChar, type: .withResponse)

        if seq == 0 {
            print("[OtaService] First OTA data packet: seq=0 (device requirement)")
        }

        return .success(())
    }

    // MARK: - Packet Building

    /// Build OTA START packet (12 bytes)
    /// Format: [CMD(1)][0x00 0x00 0x00][size(4,LE)][crc32(4,LE)]
    private func buildStartPacket(cmd: UInt8, firmwareSize: Int, crc32: Int) -> Data {
        var packet = Data()
        packet.append(cmd)
        packet.append(0x00)  // reserved
        packet.append(0x00)
        packet.append(0x00)

        // Size (4 bytes, Little Endian)
        var size = UInt32(firmwareSize).littleEndian
        packet.append(contentsOf: withUnsafeBytes(of: &size) { Array($0) })

        // CRC32 (4 bytes, Little Endian)
        var crc = UInt32(crc32).littleEndian
        packet.append(contentsOf: withUnsafeBytes(of: &crc) { Array($0) })

        return packet
    }

    /// Build firmware data packet
    /// Format: [SEQ(2,LE)][LENGTH(2,LE)][DATA(0-480)][CRC16-MODBUS(2,LE)]
    private func buildFirmwarePacket(seq: Int, data: Data) -> Data {
        var packet = Data()

        // SEQ (2 bytes, Little Endian)
        var seqValue = UInt16(seq).littleEndian
        packet.append(contentsOf: withUnsafeBytes(of: &seqValue) { Array($0) })

        // LENGTH (2 bytes, Little Endian)
        var length = UInt16(data.count).littleEndian
        packet.append(contentsOf: withUnsafeBytes(of: &length) { Array($0) })

        // DATA
        packet.append(data)

        // CRC16-MODBUS (2 bytes, Little Endian)
        let crc = Crc16Modbus.calculate(packet)
        var crcValue = crc.littleEndian
        packet.append(contentsOf: withUnsafeBytes(of: &crcValue) { Array($0) })

        return packet
    }
}

// MARK: - CRC32 Extension

extension Data {
    /// Calculate CRC32 checksum
    func crc32() -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = [
            0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
            0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
            0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
            0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
            0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
            0x35B5A8FA, 0x42B2986C, 0xDBBBBBD6, 0xACBCCB40, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
            0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
            0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
            0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
            0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
            0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
            0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
            0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
            0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
            0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
            0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
            0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
            0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
            0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
            0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
            0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
            0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
            0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
            0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
            0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
            0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
            0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
            0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
            0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
            0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
            0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD706B3, 0x54DE5729, 0x23D967BF,
            0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
        ]

        for byte in self {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }

        return crc ^ 0xFFFFFFFF
    }
}
