import Foundation
import CoreBluetooth

// MARK: - BLE Manager
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

    // Settings State
    @Published var isWirelessChargingEnabled = false
    @Published var isBoostEnabled = false

    // OTA State
    @Published var otaState: OTAState = .idle
    @Published var otaProgress: Int = 0

    // Error handling
    @Published var errorMessage: String?

    // Refresh state
    @Published var isRefreshing = false
    @Published var refreshHint: String?

    private var connectedPeripheral: CBPeripheral?
    private var scanTimeoutTimer: Timer?

    // Store discovered peripherals for later connection
    private var discoveredPeripherals: [String: CBPeripheral] = [:]

    // Discovered characteristics
    private var characteristics: [String: CBCharacteristic] = [:]

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

        // Reset connection state if we were scanning
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func connect(to device: ScannedDevice) {
        stopScan()
        connectionState = .connecting(address: device.address)

        // Find the peripheral from discovered devices
        guard let peripheral = discoveredPeripherals[device.address] else {
            connectionState = .error(message: "设备未找到，请重新扫描")
            return
        }

        // Set peripheral delegate before connecting
        peripheral.delegate = self

        // Connect to the peripheral
        centralManager?.connect(peripheral, options: nil)
    }

    func disconnect() {
        // Stop scanning if active
        if isScanning {
            stopScan()
        }

        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectionState = .disconnected
        deviceInfo = nil
        terminalVersion = nil
        basebandVersion = nil
        ttModuleState = .initializing
    }

    func refreshDeviceInfo() {
        guard connectionState.isConnected else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        refreshHint = nil

        // Simulate refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadDeviceInfo()
            self?.isRefreshing = false
            self?.refreshHint = "刷新完成"

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.refreshHint = nil
            }
        }
    }

    // MARK: - Settings Control

    func setWirelessCharging(_ enabled: Bool) {
        isWirelessChargingEnabled = enabled
        // Send command to device
    }

    func setBoostOutput(_ enabled: Bool) {
        isBoostEnabled = enabled
        // Send command to device
    }

    func rebootDevice() {
        // Send reboot command
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.disconnect()
        }
    }

    func rebootTtModule() {
        ttModuleState = .initializing
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.ttModuleState = .working
        }
    }

    func setTtModulePower(_ on: Bool) {
        ttModuleState = on ? .working : .userOff
    }

    // MARK: - OTA

    func startOta(target: OTATarget, firmwareUrl: URL) {
        otaState = .writing(progress: 0)

        // Simulate OTA progress
        var progress = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            progress += 2
            self.otaState = .writing(progress: min(progress, 100))

            if progress >= 100 {
                timer.invalidate()
                self.otaState = .verifying

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.otaState = .success
                }
            }
        }
    }

    func abortOta() {
        otaState = .idle
        otaProgress = 0
    }

    func resetOtaState() {
        otaState = .idle
        otaProgress = 0
    }

    // MARK: - Private Methods

    private func loadDeviceInfo() {
        // Request real device info via Bluetooth
        requestDeviceInfo()
        requestBatteryStatus()
        requestSignalStatus()
        requestModuleStatus()
        requestNetworkStatus()
    }

    private func requestDeviceInfo() {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[BluetoothService.Characteristic.deviceInfo.uuidString] else {
            print("Device info characteristic not found")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    private func requestBatteryStatus() {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[BluetoothService.Characteristic.batteryStatus.uuidString] else {
            print("Battery status characteristic not found")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    private func requestSignalStatus() {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[BluetoothService.Characteristic.signalStatus.uuidString] else {
            print("Signal status characteristic not found")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    private func requestModuleStatus() {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[BluetoothService.Characteristic.moduleStatus.uuidString] else {
            print("Module status characteristic not found")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    private func requestNetworkStatus() {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[BluetoothService.Characteristic.networkStatus.uuidString] else {
            print("Network status characteristic not found")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    private func parseDeviceInfoData(_ data: Data) {
        // Parse device info data based on your device protocol
        // This is a sample implementation - adjust according to actual protocol
        guard data.count >= 6 else { return }

        let batteryLevel = Int(data[0])
        let voltageMv = Int(data[1]) * 100 + Int(data[2]) * 10
        let currentMa = Int(data[3]) * 100 + Int(data[4])
        let signalStrength = Int(data[5])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.deviceInfo = DeviceInfo(
                name: self.connectedPeripheral?.name ?? "TTCat",
                address: self.connectedPeripheral?.identifier.uuidString ?? "",
                batteryLevel: batteryLevel,
                currentMa: currentMa,
                voltageMv: voltageMv,
                signalStrength: min(signalStrength, 5),
                isRegistered: self.networkRegistrationStatus != .notRegistered,
                regStatus: self.getRegStatusValue(),
                satelliteMode: .normal,
                workMode: .idle
            )
        }
    }

    private func parseBatteryData(_ data: Data) {
        // Parse battery status data
        guard data.count >= 3 else { return }

        let level = Int(data[0])
        let voltage = Int(data[1]) << 8 | Int(data[2])

        DispatchQueue.main.async { [weak self] in
            guard let self = self, var info = self.deviceInfo else { return }
            info.batteryLevel = level
            info.voltageMv = voltage
            self.deviceInfo = info
        }
    }

    private func parseSignalData(_ data: Data) {
        // Parse signal status data
        guard data.count >= 2 else { return }

        let csq = Int(data[0])
        let strength = Int(data[1])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.signalCsqRaw = csq
            if var info = self.deviceInfo {
                info.signalStrength = min(strength, 5)
                self.deviceInfo = info
            }
        }
    }

    private func parseModuleData(_ data: Data) {
        // Parse module status data
        guard data.count >= 2 else { return }

        let stateValue = Int(data[0])
        let simValue = Int(data[1])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ttModuleState = TtModuleState(rawValue: stateValue) ?? .initializing
            self.simState = SimState(rawValue: simValue) ?? .unknown
        }
    }

    private func parseNetworkData(_ data: Data) {
        // Parse network status data
        guard data.count >= 1 else { return }

        let statusValue = Int(data[0])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch statusValue {
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

            if var info = self.deviceInfo {
                info.regStatus = statusValue
                self.deviceInfo = info
            }
        }
    }

    private func getRegStatusValue() -> Int {
        switch networkRegistrationStatus {
        case .notRegistered: return 0
        case .registered: return 1
        case .searching: return 2
        case .registrationDenied: return 3
        case .unknown: return 4
        }
    }

    func clearError() {
        errorMessage = nil
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

        // Store peripheral for later connection
        discoveredPeripherals[address] = peripheral

        let device = ScannedDevice(name: name, address: address, rssi: RSSI.intValue)

        // Only add TTCat devices
        if name.contains("TTCat") || name.contains("StarMate") {
            if !scannedDevices.contains(where: { $0.address == address }) {
                scannedDevices.append(device)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral

        // Create device from connected peripheral
        let device = ScannedDevice(
            name: peripheral.name ?? "TTCat",
            address: peripheral.identifier.uuidString,
            rssi: 0
        )

        connectionState = .connected(device: device)

        // Discover services and characteristics
        peripheral.discoverServices(nil)

        // Load device info
        loadDeviceInfo()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil
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
            connectionState = .error(message: "发现服务失败")
            return
        }

        // Discover characteristics for all services
        peripheral.services?.forEach { service in
            print("Discovered service: \(service.uuid)")
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
            // Store characteristic reference
            self.characteristics[characteristic.uuid.uuidString] = characteristic

            print("Discovered characteristic: \(characteristic.uuid)")

            // Enable notification for status characteristics
            if characteristic.uuid == BluetoothService.Characteristic.batteryStatus ||
               characteristic.uuid == BluetoothService.Characteristic.signalStatus ||
               characteristic.uuid == BluetoothService.Characteristic.moduleStatus ||
               characteristic.uuid == BluetoothService.Characteristic.networkStatus {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            print("No data received from characteristic: \(characteristic.uuid)")
            return
        }

        print("Received data from \(characteristic.uuid): \(data as NSData)")

        // Parse data based on characteristic type
        if characteristic.uuid == BluetoothService.Characteristic.deviceInfo {
            parseDeviceInfoData(data)
        } else if characteristic.uuid == BluetoothService.Characteristic.batteryStatus {
            parseBatteryData(data)
        } else if characteristic.uuid == BluetoothService.Characteristic.signalStatus {
            parseSignalData(data)
        } else if characteristic.uuid == BluetoothService.Characteristic.moduleStatus {
            parseModuleData(data)
        } else if characteristic.uuid == BluetoothService.Characteristic.networkStatus {
            parseNetworkData(data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error writing value: \(error.localizedDescription)")
            return
        }

        print("Successfully wrote to characteristic: \(characteristic.uuid)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating notification state: \(error.localizedDescription)")
            return
        }

        print("Notification state updated for \(characteristic.uuid): \(characteristic.isNotifying)")
    }
}
