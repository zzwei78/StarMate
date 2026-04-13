import Foundation
import CoreBluetooth
import Combine

// MARK: - System Service Client Implementation
/// GATT System Service client (UUID: 0xABFC).
/// Handles device info, battery, signal, service management, TT Module status.
final class SystemServiceClientImpl: SystemServiceClientProtocol {

    // MARK: - Published State
    let connectionState = CurrentValueSubject<ConnectState, Never>(.disconnected)
    let deviceInfo = CurrentValueSubject<SystemInfo?, Never>(nil)
    let ttModuleState = CurrentValueSubject<TtModuleState?, Never>(nil)

    // MARK: - Private Properties
    private weak var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var infoCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?

    // Response handling
    private var responseBuffer = Data()
    private var pendingResponses: [UInt8: CheckedContinuation<Result<Data, Error>, Never>] = [:]
    private var responseQueue = DispatchQueue(label: "com.starmate.system.response")
    private var timeoutTasks: [UInt8: Task<Void, Never>] = [:]  // Track timeout tasks per sequence

    // Sequence tracking
    private var expectedSequence: UInt8 = 0

    // MARK: - Initialization
    init() {}

    // MARK: - GATT Setup

    /// Set peripheral and characteristics after discovery
    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral
        responseBuffer = Data()
        pendingResponses.removeAll()
        expectedSequence = 0
        SystemPacketBuilder.resetSequence()

        for char in characteristics {
            switch char.uuid {
            case BleUuid.SYSTEM_CONTROL:
                controlCharacteristic = char
                print("[SystemService] ✅ Control characteristic found (0xABFD)")
            case BleUuid.SYSTEM_INFO:
                infoCharacteristic = char
                print("[SystemService] ✅ Info characteristic found (0xABFE)")
            case BleUuid.SYSTEM_STATUS:
                statusCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[SystemService] ✅ Status characteristic found, notifications enabled")
            default:
                break
            }
        }

        if controlCharacteristic == nil {
            print("[SystemService] ❌ Control characteristic NOT found")
        }
    }

    /// Clear GATT references on disconnect
    func clearGattReferences() {
        peripheral = nil
        controlCharacteristic = nil
        infoCharacteristic = nil
        statusCharacteristic = nil
        responseBuffer = Data()

        // Cancel all timeout tasks and fail pending responses
        responseQueue.sync {
            // Cancel timeout tasks first
            for (_, task) in timeoutTasks {
                task.cancel()
            }
            timeoutTasks.removeAll()

            // Fail all pending responses
            for (_, continuation) in pendingResponses {
                continuation.resume(returning: .failure(NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "GATT disconnected"])))
            }
            pendingResponses.removeAll()
        }
    }

    // MARK: - Protocol: SystemServiceClientProtocol

    func onGattClosed() {
        clearGattReferences()
        connectionState.send(.disconnected)
    }

    func readInfo() async -> Result<SystemInfo, Error> {
        let result = await sendCommand(SystemCommands.CMD_GET_SYSTEM_INFO)
        switch result {
        case .success(let data):
            let info = parseSystemInfo(data)
            deviceInfo.send(info)
            return .success(info)
        case .failure(let error):
            return .failure(error)
        }
    }

    func readVersionInfo() async -> Result<TerminalVersion, Error> {
        let result = await sendCommand(SystemCommands.CMD_GET_VERSION_INFO)
        switch result {
        case .success(let data):
            guard let version = parseVersionInfo(data) else {
                return .failure(NSError(domain: "SystemService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse version info"]))
            }
            return .success(version)
        case .failure(let error):
            return .failure(error)
        }
    }

    func readBattery() async -> Result<BatteryInfo, Error> {
        let result = await sendCommand(SystemCommands.CMD_GET_BATTERY_INFO)
        switch result {
        case .success(let data):
            guard let battery = parseBatteryInfo(data) else {
                return .failure(NSError(domain: "SystemService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse battery info"]))
            }
            return .success(battery)
        case .failure(let error):
            return .failure(error)
        }
    }

    func startVoiceService() async -> Result<Void, Error> {
        return await sendServiceCommand(SystemCommands.CMD_SERVICE_START, serviceId: ServiceId.SPP_VOICE)
    }

    func stopVoiceService() async -> Result<Void, Error> {
        return await sendServiceCommand(SystemCommands.CMD_SERVICE_STOP, serviceId: ServiceId.SPP_VOICE)
    }

    func getServiceStatus(_ serviceId: UInt8) async -> Result<Bool, Error> {
        let result = await sendServiceCommand(SystemCommands.CMD_SERVICE_STATUS, serviceId: serviceId)
        // TODO: Parse response to determine if service is started
        return result.map { _ in false }
    }

    func startOtaService() async -> Result<Void, Error> {
        return await sendServiceCommand(SystemCommands.CMD_SERVICE_START, serviceId: ServiceId.OTA)
    }

    func rebootMcu() async -> Result<Void, Error> {
        let result = await sendCommand(SystemCommands.CMD_REBOOT_MCU)
        return result.map { _ in () }
    }

    func rebootModule() async -> Result<Void, Error> {
        let result = await sendCommand(SystemCommands.CMD_REBOOT_TT)
        return result.map { _ in () }
    }

    func getTtModuleStatus() async -> Result<TtModuleStatus, Error> {
        let result = await sendCommand(SystemCommands.CMD_GET_TT_STATUS)
        switch result {
        case .success(let data):
            guard let status = parseTtModuleStatus(data) else {
                return .failure(NSError(domain: "SystemService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse TT module status"]))
            }
            ttModuleState.send(status.state)
            return .success(status)
        case .failure(let error):
            return .failure(error)
        }
    }

    func setTtModulePower(_ enabled: Bool) async -> Result<Void, Error> {
        var data = Data()
        data.append(enabled ? 0x01 : 0x00)
        let result = await sendCommand(SystemCommands.CMD_SET_TT_POWER, data: data)
        return result.map { _ in () }
    }

    // MARK: - Notification Handling

    /// Handle notification data from BLEManager
    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        // Only process notifications from control characteristic (command responses)
        // Status characteristic notifications are handled separately
        guard characteristic.uuid == BleUuid.SYSTEM_CONTROL else {
            print("[SystemService] Ignoring notification from non-control characteristic: \(characteristic.uuid)")
            return
        }

        responseBuffer.append(data)
        processResponseBuffer()
    }

    // MARK: - Private Methods

    private func sendCommand(_ cmd: UInt8, data: Data = Data()) async -> Result<Data, Error> {
        guard let char = controlCharacteristic else {
            return .failure(NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Control characteristic not found"]))
        }
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "SystemService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        // Clear stale response data before sending new command
        responseBuffer = Data()

        // Build packet using SystemPacketBuilder
        let (packet, seq) = SystemPacketBuilder.buildCommand(cmd: cmd, data: data)

        print("[SystemService] SEND cmd=0x\(String(cmd, radix: 16)), seq=\(seq)")

        return await withCheckedContinuation { continuation in
            responseQueue.sync {
                pendingResponses[seq] = continuation
            }

            // Set timeout - track the task for cancellation
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                // Only resume if this task hasn't been cancelled
                guard !Task.isCancelled else { return }

                responseQueue.sync {
                    if let cont = pendingResponses.removeValue(forKey: seq) {
                        cont.resume(returning: .failure(NSError(domain: "SystemService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Command timeout"])))
                    }
                    // Clean up timeout task reference
                    timeoutTasks.removeValue(forKey: seq)
                }
            }

            responseQueue.sync {
                timeoutTasks[seq] = timeoutTask
            }

            peripheral.writeValue(packet, for: char, type: .withResponse)
        }
    }

    private func sendServiceCommand(_ cmd: UInt8, serviceId: UInt8) async -> Result<Void, Error> {
        var data = Data()
        data.append(0x01)       // param count = 1
        data.append(serviceId)  // service ID
        let result = await sendCommand(cmd, data: data)
        return result.map { _ in () }
    }

    private func processResponseBuffer() {
        print("[SystemService] processResponseBuffer: buffer.count=\(responseBuffer.count), bytes: \(responseBuffer.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")

        while responseBuffer.count >= 6 {
            // Ensure we have at least 4 bytes for the header before reading DATA_LEN
            guard responseBuffer.count >= 4 else {
                return
            }

            let rawDataLen = Int(responseBuffer[3])
            let dataLen = max(0, min(rawDataLen, 96))  // Clamp to 0-96 per protocol
            let packetLength = 4 + dataLen + 2  // 4-byte header + data + 2-byte CRC

            guard responseBuffer.count >= packetLength else {
                return
            }

            // Extract packet for parsing
            let packetData = responseBuffer.subdata(in: 0..<packetLength)

            guard let parsed = SystemPacketBuilder.parseResponse(packetData) else {
                // Invalid packet, drop first byte and try again
                responseBuffer = responseBuffer.dropFirst()
                continue
            }

            // Drop the consumed packet - use subdata to create a new copy instead of slice
            let remainingBytes = responseBuffer.count - packetLength
            if remainingBytes > 0 {
                responseBuffer = responseBuffer.subdata(in: packetLength..<responseBuffer.count)
            } else {
                responseBuffer = Data()
            }

            // Find and complete pending response
            responseQueue.sync {
                print("[SystemService] RECV seq=\(parsed.seq), pending keys: \(pendingResponses.keys.map { "0x\($0)" })")

                // Cancel timeout task first
                if let timeoutTask = timeoutTasks.removeValue(forKey: parsed.seq) {
                    timeoutTask.cancel()
                }

                if let continuation = pendingResponses.removeValue(forKey: parsed.seq) {
                    if parsed.isSuccess {
                        continuation.resume(returning: .success(parsed.data))
                    } else {
                        continuation.resume(returning: .failure(NSError(
                            domain: "SystemService",
                            code: Int(parsed.resultCode),
                            userInfo: [NSLocalizedDescriptionKey: "Device error: 0x\(String(parsed.resultCode, radix: 16))"]
                        )))
                    }
                }
            }
        }
    }

    // MARK: - Parsers

    private func parseSystemInfo(_ data: Data) -> SystemInfo {
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

    private func parseVersionInfo(_ data: Data) -> TerminalVersion? {
        guard data.count >= 96 else {
            print("[SystemService] Version info data too short: \(data.count)")
            return nil
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

    private func parseBatteryInfo(_ data: Data) -> BatteryInfo? {
        guard data.count >= 16 else {
            print("[SystemService] Battery info data too short: \(data.count)")
            return nil
        }

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
        guard data.count >= 3 else {
            print("[SystemService] TT module status data too short: \(data.count)")
            return nil
        }

        let stateVal = Int(data[0])
        var state: TtModuleState
        var voltageMv = 0

        if data.count >= 6 {
            // New 6-byte format: state(1) + voltage_mv_lo(1) + voltage_mv_hi(1) + error_code(1) + reserved(2)
            voltageMv = Int(data[1]) | (Int(data[2]) << 8)
            let errCode = Int(data[3])

            switch stateVal {
            case 0: state = .hardwareFault(errorCode: errCode)
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
            case 0x00: state = .poweredOff(reason: .userRequest)
            case 0x01: state = .initializing
            case 0x02: state = .working
            case 0x03: state = .updating
            default: state = .error(errorCode: stateVal)
            }
        }

        return TtModuleStatus(state: state, voltageMv: voltageMv)
    }

    private func parseCString(data: Data, offset: Int, maxLen: Int) -> String {
        let end = min(offset + maxLen, data.count)
        let slice = data.subdata(in: offset..<end)
        let str = String(data: slice, encoding: .utf8) ?? ""
        return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            .isEmpty ? "N/A" : str.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }
}
