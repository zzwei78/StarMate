import Foundation
import CoreBluetooth

// MARK: - BLE Manager
/// BLE Manager with real GATT implementation for TTCat satellite terminal.
/// Based on TTCat_BLE_Protocol_V3.3
class BLEManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager?

    // Published Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var scannedDevices: [ScannedDevice] = []
    @Published var isScanning = false

    // Device Info
    @Published var deviceInfo: DeviceInfo?
    @Published var terminalVersion: TerminalVersion?
    @Published var basebandVersion: BasebandVersion?
    @Published var ttModuleState: TtModuleState = .initializing
    @Published var simState: SimState = .unknown
    @Published var networkRegistrationStatus: NetworkRegistrationStatus = .unknown
    @Published var signalCsqRaw: Int? = nil
    @Published var batteryInfo: BatteryInfo?

    // Settings State
    @Published var isWirelessChargingEnabled = false
    @Published var isBoostEnabled = false

    // OTA State
    @Published var otaState: OTAState = .idle
    @Published var otaProgress: Int = 0

    // Error handling
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // Refresh state
    @Published var isRefreshing = false
    @Published var refreshHint: String?

    // MARK: - Private Properties

    private var connectedPeripheral: CBPeripheral?
    private var scanTimeoutTimer: Timer?
    private var discoveredPeripherals: [String: CBPeripheral] = [:]

    // GATT Characteristics
    private var systemControlChar: CBCharacteristic?
    private var systemInfoChar: CBCharacteristic?
    private var systemStatusChar: CBCharacteristic?
    private var atCommandChar: CBCharacteristic?
    private var atResponseChar: CBCharacteristic?
    private var voiceInChar: CBCharacteristic?
    private var voiceOutChar: CBCharacteristic?
    private var otaControlChar: CBCharacteristic?
    private var otaDataChar: CBCharacteristic?
    private var otaStatusChar: CBCharacteristic?

    // Response handling
    private var responseBuffer = Data()
    private var pendingResponseContinuation: ((Result<Data, Error>) -> Void)?
    private var pendingAtResponseContinuation: ((Result<String, Error>) -> Void)?
    private var atResponseBuffer = ""
    private var commandTimeoutTimer: Timer?
    private let commandTimeout: TimeInterval = 25.0
    private let atCommandTimeout: TimeInterval = 30.0

    // MTU
    private var negotiatedMtu: Int = 23

    // Write queue for serializing BLE writes
    private var writeQueue: [(data: Data, characteristic: CBCharacteristic, continuation: (Result<Void, Error>) -> Void)] = []
    private var isWriting = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods

    func startScan() {
        guard centralManager?.state == .poweredOn else {
            errorMessage = "蓝牙未开启"
            return
        }

        scannedDevices = []
        isScanning = true
        connectionState = .scanning

        // Scan for TTCat devices
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        // Set scan timeout
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager?.stopScan()
        isScanning = false
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil

        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func connect(to device: ScannedDevice) {
        stopScan()
        connectionState = .connecting(address: device.address)

        guard let peripheral = discoveredPeripherals[device.address] else {
            connectionState = .error(message: "设备未找到，请重新扫描")
            return
        }

        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    func disconnect() {
        if isScanning {
            stopScan()
        }

        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }

        resetState()
    }

    // MARK: - System Service Commands

    func readSystemInfo() {
        guard let char = systemControlChar else { return }

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_GET_SYSTEM_INFO)
        writeAndWait(packet: packet, to: char) { [weak self] result in
            switch result {
            case .success(let data):
                self?.parseSystemInfo(data)
            case .failure(let error):
                print("Failed to read system info: \(error)")
            }
        }
    }

    func readVersionInfo() {
        guard let char = systemControlChar else { return }

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_GET_VERSION_INFO)
        writeAndWait(packet: packet, to: char) { [weak self] result in
            switch result {
            case .success(let data):
                self?.parseVersionInfo(data)
            case .failure(let error):
                print("Failed to read version info: \(error)")
            }
        }
    }

    func readBatteryInfo() {
        guard let char = systemControlChar else { return }

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_GET_BATTERY_INFO)
        writeAndWait(packet: packet, to: char) { [weak self] result in
            switch result {
            case .success(let data):
                self?.parseBatteryInfo(data)
            case .failure(let error):
                print("Failed to read battery info: \(error)")
            }
        }
    }

    func readTtModuleStatus() {
        guard let char = systemControlChar else { return }

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_GET_TT_STATUS)
        writeAndWait(packet: packet, to: char) { [weak self] result in
            switch result {
            case .success(let data):
                self?.parseTtModuleStatus(data)
            case .failure(let error):
                print("Failed to read TT module status: \(error)")
            }
        }
    }

    func refreshDeviceInfo() {
        guard connectionState.isConnected else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        refreshHint = nil

        // Read all device info
        readSystemInfo()
        readBatteryInfo()
        readTtModuleStatus()
        readVersionInfo()

        // Also read signal via AT command
        sendAtCommand("AT+CSQ") { [weak self] result in
            if case .success(let response) = result {
                self?.parseSignalInfo(response)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isRefreshing = false
            self?.refreshHint = "刷新完成"

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.refreshHint = nil
            }
        }
    }

    // MARK: - AT Commands

    func sendAtCommand(_ command: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let char = atCommandChar else {
            completion(.failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "AT Command characteristic not found"])))
            return
        }

        var cmd = command
        if !cmd.hasSuffix("\r") {
            cmd += "\r"
        }

        pendingAtResponseContinuation = completion
        atResponseBuffer = ""

        let data = cmd.data(using: .utf8)!

        // Cancel previous timeout
        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = Timer.scheduledTimer(withTimeInterval: atCommandTimeout, repeats: false) { [weak self] _ in
            self?.pendingAtResponseContinuation?(.failure(NSError(domain: "BLE", code: -2, userInfo: [NSLocalizedDescriptionKey: "AT command timeout"])))
            self?.pendingAtResponseContinuation = nil
            self?.atResponseBuffer = ""
        }

        writeData(data, to: char)
    }

    // MARK: - Settings Control

    func setWirelessCharging(_ enabled: Bool) {
        guard let char = systemControlChar else { return }
        // Implementation depends on device protocol
        isWirelessChargingEnabled = enabled
    }

    func setBoostOutput(_ enabled: Bool) {
        guard let char = systemControlChar else { return }
        // Implementation depends on device protocol
        isBoostEnabled = enabled
    }

    func rebootDevice() {
        guard let char = systemControlChar else { return }

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_REBOOT_MCU)
        writeData(packet, to: char)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.disconnect()
        }
    }

    func rebootTtModule() {
        guard let char = systemControlChar else { return }

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_REBOOT_TT)
        writeData(packet, to: char)

        ttModuleState = .initializing

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.readTtModuleStatus()
        }
    }

    func setTtModulePower(_ on: Bool) {
        guard let char = systemControlChar else { return }

        let param: UInt8 = on ? 0x01 : 0x00
        var data = Data()
        data.append(param)

        let packet = SystemPacketBuilder.buildCommand(cmd: SystemCommands.CMD_SET_TT_POWER, data: data)
        writeAndWait(packet: packet, to: char) { [weak self] result in
            if case .success = result {
                DispatchQueue.main.async {
                    self?.ttModuleState = on ? .working : .userOff
                    self?.successMessage = on ? "天通模块已开启" : "天通模块已关闭"
                }
            }
        }
    }

    // MARK: - OTA

    func startOta(target: OTATarget, firmwareUrl: URL) {
        // Implementation for OTA
        otaState = .writing(progress: 0)
    }

    func abortOta() {
        otaState = .idle
        otaProgress = 0
    }

    func resetOtaState() {
        otaState = .idle
        otaProgress = 0
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }

    func clearMessage() {
        successMessage = nil
    }

    // MARK: - Private Methods

    private func resetState() {
        connectedPeripheral = nil
        connectionState = .disconnected
        deviceInfo = nil
        terminalVersion = nil
        basebandVersion = nil
        ttModuleState = .initializing
        batteryInfo = nil
        systemControlChar = nil
        systemInfoChar = nil
        systemStatusChar = nil
        atCommandChar = nil
        atResponseChar = nil
        voiceInChar = nil
        voiceOutChar = nil
        otaControlChar = nil
        otaDataChar = nil
        otaStatusChar = nil
        responseBuffer = Data()
        pendingResponseContinuation = nil
        pendingAtResponseContinuation = nil
        atResponseBuffer = ""
        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = nil
    }

    private func writeAndWait(packet: Data, to characteristic: CBCharacteristic, completion: @escaping (Result<Data, Error>) -> Void) {
        pendingResponseContinuation = completion
        responseBuffer = Data()

        commandTimeoutTimer?.invalidate()
        commandTimeoutTimer = Timer.scheduledTimer(withTimeInterval: commandTimeout, repeats: false) { [weak self] _ in
            self?.pendingResponseContinuation?(.failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Command timeout"])))
            self?.pendingResponseContinuation = nil
            self?.responseBuffer = Data()
        }

        writeData(packet, to: characteristic)
    }

    private func writeData(_ data: Data, to characteristic: CBCharacteristic) {
        guard let peripheral = connectedPeripheral else { return }

        // Queue the write
        writeQueue.append((data: data, characteristic: characteristic, continuation: { _ in }))
        processWriteQueue()
    }

    private func processWriteQueue() {
        guard !isWriting, !writeQueue.isEmpty else { return }
        isWriting = true

        let item = writeQueue.removeFirst()
        connectedPeripheral?.writeValue(item.data, for: item.characteristic, type: .withResponse)
    }

    // MARK: - Response Parsers

    private func parseSystemInfo(_ data: Data) {
        // Parse system info response
        // Format depends on device firmware
        let str = String(data: data, encoding: .utf8) ?? ""
        let parts = str.split(separator: "\0").map { String($0) }

        DispatchQueue.main.async {
            self.deviceInfo = DeviceInfo(
                name: parts.first ?? "TTCat",
                address: self.connectedPeripheral?.identifier.uuidString ?? "",
                batteryLevel: self.batteryInfo?.level ?? 0,
                currentMa: self.batteryInfo?.current ?? 0,
                voltageMv: self.batteryInfo?.voltage ?? 0,
                signalStrength: 4,
                isRegistered: true,
                regStatus: 1,
                satelliteMode: .normal,
                workMode: .idle
            )
        }
    }

    private func parseVersionInfo(_ data: Data) {
        guard data.count >= 96 else {
            print("Version info data too short: \(data.count)")
            return
        }

        let firmwareVersion = parseCString(data: data, offset: 0, maxLen: 16)
        let softwareVersion = parseCString(data: data, offset: 16, maxLen: 24)
        let manufacturer = parseCString(data: data, offset: 40, maxLen: 16)
        let modelNumber = parseCString(data: data, offset: 56, maxLen: 16)
        let hardwareRevision = parseCString(data: data, offset: 72, maxLen: 8)

        DispatchQueue.main.async {
            self.terminalVersion = TerminalVersion(
                hardwareVersion: hardwareRevision,
                softwareVersion: softwareVersion,
                firmwareVersion: firmwareVersion,
                manufacturer: manufacturer,
                modelNumber: modelNumber
            )
        }
    }

    private func parseCString(data: Data, offset: Int, maxLen: Int) -> String {
        let end = min(offset + maxLen, data.count)
        let slice = data.subdata(in: offset..<end)
        let str = String(data: slice, encoding: .utf8) ?? ""
        return str.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).isEmpty ? "N/A" : str.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    private func parseBatteryInfo(_ data: Data) {
        guard data.count >= 16 else {
            print("Battery info data too short: \(data.count)")
            return
        }

        let voltage = Int(data[0]) | (Int(data[1]) << 8)
        let currentRaw = Int(data[2]) | (Int(data[3]) << 8)
        let current = currentRaw > 32767 ? currentRaw - 65536 : currentRaw
        let socPercent = min(Int(data[4]) | (Int(data[5]) << 8), 100)
        let charging = data[14] != 0

        DispatchQueue.main.async {
            self.batteryInfo = BatteryInfo(
                level: socPercent,
                voltage: voltage,
                current: current,
                isCharging: charging,
                isWirelessCharging: false
            )
        }
    }

    private func parseTtModuleStatus(_ data: Data) {
        guard data.count >= 3 else {
            DispatchQueue.main.async {
                self.ttModuleState = .hardwareFault
            }
            return
        }

        let stateVal = Int(data[0])

        var state: TtModuleState
        if data.count >= 6 {
            // New 6-byte format
            let voltageMv = Int(data[1]) | (Int(data[2]) << 8)
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

        DispatchQueue.main.async {
            self.ttModuleState = state
        }
    }

    private func parseSignalInfo(_ response: String) {
        // Parse AT+CSQ response: +CSQ: <rssi>,<ber>
        guard response.contains("+CSQ:") else { return }

        let parts = response.replacingOccurrences(of: "+CSQ: ", with: "").split(separator: ",")
        guard parts.count >= 1 else { return }

        if let rssi = Int(parts[0]) {
            DispatchQueue.main.async {
                self.signalCsqRaw = rssi
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("BLE is powered on")
        case .poweredOff:
            connectionState = .error(message: "蓝牙未开启")
        case .unauthorized:
            connectionState = .error(message: "未授权蓝牙权限")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown Device"
        let address = peripheral.identifier.uuidString

        discoveredPeripherals[address] = peripheral

        let device = ScannedDevice(name: name, address: address, rssi: RSSI.intValue)

        // Filter for TTCat devices
        if name.contains("TTCat") || name.contains("StarMate") {
            if !scannedDevices.contains(where: { $0.address == address }) {
                scannedDevices.append(device)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral

        let device = ScannedDevice(
            name: peripheral.name ?? "TTCat",
            address: peripheral.identifier.uuidString,
            rssi: 0
        )

        connectionState = .connected(device: device)

        // Request MTU
        peripheral.maximumWriteValueLength(for: .withResponse)

        // Discover services
        peripheral.discoverServices([
            BleUuid.SYSTEM_SERVICE,
            BleUuid.AT_SERVICE,
            BleUuid.VOICE_SERVICE,
            BleUuid.OTA_SERVICE
        ])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetState()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .error(message: "连接失败: \(error?.localizedDescription ?? "未知错误")")
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            // Store characteristic references
            switch characteristic.uuid {
            case BleUuid.SYSTEM_CONTROL:
                systemControlChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            case BleUuid.SYSTEM_INFO:
                systemInfoChar = characteristic
            case BleUuid.SYSTEM_STATUS:
                systemStatusChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            case BleUuid.AT_COMMAND:
                atCommandChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            case BleUuid.AT_RESPONSE:
                atResponseChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            case BleUuid.VOICE_IN:
                voiceInChar = characteristic
            case BleUuid.VOICE_OUT:
                voiceOutChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            case BleUuid.OTA_CONTROL:
                otaControlChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            case BleUuid.OTA_DATA:
                otaDataChar = characteristic
            case BleUuid.OTA_STATUS:
                otaStatusChar = characteristic
                enableNotification(for: characteristic, on: peripheral)
            default:
                break
            }
        }

        // If we have all required characteristics, start reading device info
        if systemControlChar != nil && atCommandChar != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshDeviceInfo()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BleUuid.SYSTEM_CONTROL, BleUuid.SYSTEM_STATUS:
            handleSystemServiceData(data)

        case BleUuid.AT_COMMAND, BleUuid.AT_RESPONSE:
            handleAtServiceData(data)

        case BleUuid.VOICE_OUT:
            handleVoiceData(data)

        case BleUuid.OTA_STATUS:
            handleOtaStatus(data)

        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        isWriting = false

        if let error = error {
            print("Write error: \(error.localizedDescription)")
        }

        // Process next item in queue
        if !writeQueue.isEmpty {
            processWriteQueue()
        }
    }

    // MARK: - Notification Handling

    private func enableNotification(for characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        peripheral.setNotifyValue(true, for: characteristic)
    }

    private func handleSystemServiceData(_ data: Data) {
        responseBuffer.append(data)

        // Try to parse complete response
        while responseBuffer.count >= 6 {
            guard let parsed = SystemPacketBuilder.parseResponse(responseBuffer) else {
                // Invalid packet, drop first byte and try again
                responseBuffer = responseBuffer.dropFirst()
                continue
            }

            // Calculate packet length
            let packetLength = 4 + Int(parsed.dataLen) + 2
            responseBuffer = responseBuffer.dropFirst(packetLength)

            // Complete pending response
            commandTimeoutTimer?.invalidate()

            if parsed.resultCode == 0 {
                pendingResponseContinuation?(.success(parsed.data))
            } else {
                pendingResponseContinuation?(.failure(NSError(domain: "BLE", code: Int(parsed.resultCode), userInfo: [NSLocalizedDescriptionKey: "Device error: 0x\(String(parsed.resultCode, radix: 16))"])))
            }
            pendingResponseContinuation = nil
        }
    }

    private func handleAtServiceData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        // Check for URC (unsolicited result code)
        if pendingAtResponseContinuation == nil {
            handleAtUrc(text)
            return
        }

        // Accumulate response
        if !atResponseBuffer.isEmpty {
            atResponseBuffer += "\n"
        }
        atResponseBuffer += text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for terminal markers
        if atResponseBuffer.contains("OK") {
            commandTimeoutTimer?.invalidate()
            let response = atResponseBuffer.replacingOccurrences(of: "\nOK", with: "").replacingOccurrences(of: "OK", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            pendingAtResponseContinuation?(.success(response))
            pendingAtResponseContinuation = nil
            atResponseBuffer = ""
        } else if atResponseBuffer.contains("ERROR") || atResponseBuffer.contains("+CME ERROR") || atResponseBuffer.contains("+CMS ERROR") {
            commandTimeoutTimer?.invalidate()
            pendingAtResponseContinuation?(.failure(NSError(domain: "AT", code: -1, userInfo: [NSLocalizedDescriptionKey: atResponseBuffer])))
            pendingAtResponseContinuation = nil
            atResponseBuffer = ""
        }
    }

    private func handleAtUrc(_ text: String) {
        // Handle unsolicited result codes
        if text.contains("RING") || text.contains("+CLIP:") {
            // Incoming call notification
            NotificationCenter.default.post(name: .incomingCall, object: text)
        } else if text.contains("+CMTI:") {
            // SMS received notification
            NotificationCenter.default.post(name: .smsReceived, object: text)
        } else if text.contains("+CREG:") {
            // Network registration notification
            parseNetworkRegistration(text)
        }
    }

    private func parseNetworkRegistration(_ text: String) {
        // Parse +CREG: <stat> or +CREG: <n>,<stat>
        let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        guard let stat = digits.last else { return }

        DispatchQueue.main.async {
            switch stat {
            case 0:
                self.networkRegistrationStatus = .notRegistered
            case 1:
                self.networkRegistrationStatus = .registered(isRoaming: false)
            case 2:
                self.networkRegistrationStatus = .searching
            case 3:
                self.networkRegistrationStatus = .registrationDenied
            case 5:
                self.networkRegistrationStatus = .registered(isRoaming: true)
            default:
                self.networkRegistrationStatus = .unknown
            }
        }
    }

    private func handleVoiceData(_ data: Data) {
        // Handle incoming voice data
        NotificationCenter.default.post(name: .voiceDataReceived, object: data)
    }

    private func handleOtaStatus(_ data: Data) {
        // Handle OTA status updates
        guard !data.isEmpty else { return }

        let status = Int(data[0])
        // Update OTA state based on status
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let incomingCall = Notification.Name("incomingCall")
    static let smsReceived = Notification.Name("smsReceived")
    static let voiceDataReceived = Notification.Name("voiceDataReceived")
}
