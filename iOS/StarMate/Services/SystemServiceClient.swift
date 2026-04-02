import Foundation
import CoreBluetooth

// MARK: - System Service Client
/// GATT System Service client (UUID: 0xABFC)
/// Handles device info, battery, signal, service management, TT Module status.
protocol SystemServiceClientDelegate: AnyObject {
    func systemServiceClient(_ client: SystemServiceClient, didUpdateDeviceInfo info: DeviceInfo)
    func systemServiceClient(_ client: SystemServiceClient, didUpdateBatteryInfo info: BatteryInfo)
    func systemServiceClient(_ client: SystemServiceClient, didUpdateTtModuleState state: TtModuleState)
    func systemServiceClient(_ client: SystemServiceClient, didUpdateTerminalVersion version: TerminalVersion)
    func systemServiceClient(_ client: SystemServiceClient, didEncounterError error: Error)
}

class SystemServiceClient: NSObject {
    weak var delegate: SystemServiceClientDelegate?

    // GATT references
    private weak var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var infoCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?

    // Response handling
    private var responseBuffer = Data()
    private var pendingResponseContinuations: [UInt8: (Result<Data, Error>) -> Void] = [:]
    private var currentSequenceNumber: UInt8 = 0
    private var commandTimeoutTimer: Timer?
    private let commandTimeout: TimeInterval = 25.0

    // Published state
    @Published var deviceInfo: DeviceInfo?
    @Published var batteryInfo: BatteryInfo?
    @Published var ttModuleState: TtModuleState = .initializing
    @Published var terminalVersion: TerminalVersion?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - GATT Setup

    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral
        responseBuffer = Data()
        pendingResponseContinuations = [:]

        for char in characteristics {
            switch char.uuid {
            case BleUuid.SYSTEM_CONTROL:
                controlCharacteristic = char
                print("✅ System Control characteristic found")
            case BleUuid.SYSTEM_INFO:
                infoCharacteristic = char
                print("✅ System Info characteristic found")
            case BleUuid.SYSTEM_STATUS:
                statusCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("✅ System Status characteristic found, notifications enabled")
            default:
                break
            }
        }

        if controlCharacteristic == nil {
            print("❌ System Control characteristic NOT found")
        }
    }

    func clearGattReferences() {
        peripheral = nil
        controlCharacteristic = nil
        infoCharacteristic = nil
        statusCharacteristic = nil
        responseBuffer = Data()
        pendingResponseContinuations = [:]
        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = nil
    }

    // MARK: - Commands

    /// Read system info (CMD 0x01)
    func readSystemInfo(completion: @escaping (Result<SystemInfo, Error>) -> Void) {
        sendCommand(cmd: SystemCommands.CMD_GET_SYSTEM_INFO) { [weak self] result in
            switch result {
            case .success(let data):
                let info = self?.parseSystemInfo(data)
                completion(.success(info))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Read version info (CMD 0x31)
    func readVersionInfo(completion: @escaping (Result<TerminalVersion, Error>) -> Void) {
        sendCommand(cmd: SystemCommands.CMD_GET_VERSION_INFO) { [weak self] result in
            switch result {
            case .success(let data):
                let version = self?.parseVersionInfo(data)
                if let version = version {
                    self?.terminalVersion = version
                    completion(.success(version))
                } else {
                    completion(.failure(NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse version info"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Read battery info (CMD 0x02)
    func readBatteryInfo(completion: @escaping (Result<BatteryInfo, Error>) -> Void) {
        sendCommand(cmd: SystemCommands.CMD_GET_BATTERY_INFO) { [weak self] result in
            switch result {
            case .success(let data):
                let battery = self?.parseBatteryInfo(data)
                if let battery = battery {
                    self?.batteryInfo = battery
                    completion(.success(battery))
                } else {
                    completion(.failure(NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse battery info"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get TT Module status (CMD 0x60)
    func getTtModuleStatus(completion: @escaping (Result<TtModuleStatus, Error>) -> Void) {
        sendCommand(cmd: SystemCommands.CMD_GET_TT_STATUS) { [weak self] result in
            switch result {
            case .success(let data):
                let status = self?.parseTtModuleStatus(data)
                if let status = status {
                    self?.ttModuleState = status.state
                    completion(.success(status))
                } else {
                    completion(.failure(NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse TT module status"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Set TT Module power (CMD 0x61)
    func setTtModulePower(enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let param: UInt8 = enabled ? 0x01 : 0x00
        var data = Data()
        data.append(param)

        sendCommand(cmd: SystemCommands.CMD_SET_TT_POWER, data: data) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Start voice service (CMD 0x10)
    func startVoiceService(completion: @escaping (Result<Void, Error>) -> Void) {
        var data = Data()
        data.append(0x01) // param count
        data.append(ServiceId.SPP_VOICE)

        sendCommand(cmd: SystemCommands.CMD_SERVICE_START, data: data) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Stop voice service (CMD 0x11)
    func stopVoiceService(completion: @escaping (Result<Void, Error>) -> Void) {
        var data = Data()
        data.append(0x01) // param count
        data.append(ServiceId.SPP_VOICE)

        sendCommand(cmd: SystemCommands.CMD_SERVICE_STOP, data: data) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Reboot MCU (CMD 0x20)
    func rebootMcu(completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(cmd: SystemCommands.CMD_REBOOT_MCU) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Reboot TT module (CMD 0x21)
    func rebootTtModule(completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(cmd: SystemCommands.CMD_REBOOT_TT) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Notification Handling

    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        responseBuffer.append(data)
        processResponseBuffer()
    }

    private func processResponseBuffer() {
        while responseBuffer.count >= 6 {
            guard let parsed = SystemPacketBuilder.parseResponse(responseBuffer) else {
                // Invalid packet, drop first byte and try again
                responseBuffer = responseBuffer.dropFirst()
                continue
            }

            // Calculate actual packet length
            var packetLength: Int
            if parsed.resultCode != 0 || parsed.dataLen == 0 {
                // 4-byte header: SEQ + RESP + LEN + DATA + CRC
                packetLength = 4 + Int(parsed.dataLen) + 2
            } else {
                // 5-byte header: SEQ + RESP + RESULT + LEN + DATA + CRC
                packetLength = 5 + Int(parsed.dataLen) + 2
            }

            // Remove processed packet from buffer
            responseBuffer = responseBuffer.dropFirst(packetLength)

            // Find and complete pending response
            if let continuation = pendingResponseContinuations[parsed.seq] {
                pendingResponseContinuations.removeValue(forKey: parsed.seq)
                commandTimeoutTimer?.invalidate()

                if parsed.resultCode == 0 {
                    continuation(.success(parsed.data))
                } else {
                    continuation(.failure(NSError(
                        domain: "SystemService",
                        code: Int(parsed.resultCode),
                        userInfo: [NSLocalizedDescriptionKey: "Device error: 0x\(String(parsed.resultCode, radix: 16))"]
                    )))
                }
            }
        }
    }

    // MARK: - Private Methods

    private func sendCommand(cmd: UInt8, data: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
        guard let char = controlCharacteristic else {
            let error = NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "System Control characteristic not found"])
            completion(.failure(error))
            return
        }

        guard let peripheral = peripheral else {
            let error = NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"])
            completion(.failure(error))
            return
        }

        // Clear stale response data
        responseBuffer = Data()

        // Build packet
        currentSequenceNumber = (currentSequenceNumber &+ 1) & 0xFF
        let packet = buildPacket(seq: currentSequenceNumber, cmd: cmd, data: data)

        // Store completion handler
        pendingResponseContinuations[currentSequenceNumber] = completion

        // Set timeout
        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = Timer.scheduledTimer(withTimeInterval: commandTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let continuation = self.pendingResponseContinuations[self.currentSequenceNumber] {
                self.pendingResponseContinuations.removeValue(forKey: self.currentSequenceNumber)
                continuation(.failure(NSError(domain: "SystemService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Command timeout"])))
            }
        }

        // Write to characteristic
        peripheral.writeValue(packet, for: char, type: .withResponse)
    }

    private func buildPacket(seq: UInt8, cmd: UInt8, data: Data) -> Data {
        var packet = Data()
        packet.append(seq)
        packet.append(cmd)
        packet.append(UInt8(data.count))
        packet.append(data)

        let crc = Crc16.calculate(packet)
        packet.append(UInt8(crc & 0xFF))
        packet.append(UInt8((crc >> 8) & 0xFF))

        return packet
    }

    // MARK: - Parsers

    private func parseSystemInfo(_ data: Data) -> SystemInfo {
        // Try parsing as null-terminated strings
        let str = String(data: data, encoding: .utf8) ?? ""
        let parts = str.split(separator: "\0").map { String($0) }

        return SystemInfo(
            deviceName: parts.first ?? "TTCat",
            hardwareVersion: parts.count > 1 ? parts[1] : "Unknown",
            softwareVersion: parts.count > 2 ? parts[2] : "Unknown",
            mcuVersion: parts.count > 3 ? parts[3] : "Unknown",
            moduleVersion: parts.count > 4 ? parts[4] : "Unknown"
        )
    }

    private func parseVersionInfo(_ data: Data) -> TerminalVersion {
        guard data.count >= 96 else {
            return TerminalVersion(
                hardwareVersion: "N/A",
                softwareVersion: "N/A",
                firmwareVersion: "N/A",
                manufacturer: "N/A",
                modelNumber: "N/A"
            )
        }

        let firmwareVersion = parseCString(data: data, offset: 0, maxLen: 16)
        let softwareVersion = parseCString(data: data, offset: 16, maxLen: 24)
        let manufacturer = parseCString(data: data, offset: 40, maxLen: 16)
        let modelNumber = parseCString(data: data, offset: 56, maxLen: 16)
        let hardwareRevision = parseCString(data: data, offset: 72, maxLen: 8)

        return TerminalVersion(
            hardwareVersion: hardwareRevision,
            softwareVersion: softwareVersion,
            firmwareVersion: firmwareVersion,
            manufacturer: manufacturer,
            modelNumber: modelNumber
        )
    }

    private func parseCString(data: Data, offset: Int, maxLen: Int) -> String {
        let end = min(offset + maxLen, data.count)
        let slice = data.subdata(in: offset..<end)
        let str = String(data: slice, encoding: .utf8) ?? ""
        return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            .isEmpty ? "N/A" : str.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    private func parseBatteryInfo(_ data: Data) -> BatteryInfo? {
        guard data.count >= 16 else { return nil }

        let voltage = Int(data[0]) | (Int(data[1]) << 8)
        let currentRaw = Int(data[2]) | (Int(data[3]) << 8)
        let current = currentRaw > 32767 ? currentRaw - 65536 : currentRaw
        let socPercent = min(Int(data[4]) | (Int(data[5]) << 8), 100)
        let charging = data[14] != 0

        return BatteryInfo(
            level: socPercent,
            voltage: voltage,
            current: current,
            isCharging: charging,
            isWirelessCharging: false
        )
    }

    private func parseTtModuleStatus(_ data: Data) -> TtModuleStatus? {
        guard data.count >= 3 else { return nil }

        let stateVal = Int(data[0])

        var state: TtModuleState
        var voltageMv = 0

        if data.count >= 6 {
            // New 6-byte format: state(1) + voltage_mv_lo(1) + voltage_mv_hi(1) + error_code(1) + reserved(2)
            voltageMv = Int(data[1]) | (Int(data[2]) << 8)
            let errCode = Int(data[3])

            switch stateVal {
            case 0: state = .hardwareFault
            case 1: state = .initializing
            case 2: state = .waitingMuxResp
            case 3: state = .lowBatteryOff
            case 4: state = .userOff
            case 5: state = .working
            case 6: state = .updating
            default: state = .error(errorCode: stateVal)
            }
        } else {
            // Legacy 3-byte format
            switch stateVal {
            case 0x00: state = .poweredOff
            case 0x01: state = .initializing
            case 0x02: state = .working
            case 0x03: state = .updating
            default: state = .error(errorCode: stateVal)
            }
        }

        return TtModuleStatus(state: state, voltageMv: voltageMv)
    }
}

// MARK: - Supporting Types

struct TtModuleStatus {
    let state: TtModuleState
    let voltageMv: Int
    var isPoweredOn: Bool = false
    var isMuxReady: Bool = false
    var isSimReady: Bool = false
    var isNetworkReady: Bool = false
}
