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
        // Simulate loading device info
        deviceInfo = DeviceInfo(
            name: "TTCat",
            address: "AA:BB:CC:DD:EE:FF",
            batteryLevel: 85,
            currentMa: 450,
            voltageMv: 3800,
            signalStrength: 4,
            isRegistered: true,
            regStatus: 1,
            satelliteMode: .normal,
            workMode: .idle
        )

        terminalVersion = TerminalVersion(
            hardwareVersion: "v1.2",
            softwareVersion: "v2.0.1",
            firmwareVersion: "v1.0.5",
            manufacturer: "TTCat",
            modelNumber: "TC-100"
        )

        ttModuleState = .working
        simState = .ready
        networkRegistrationStatus = .registered(isRoaming: false)
        signalCsqRaw = 20
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
            return
        }

        // Discover characteristics for all services
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        // You can now interact with characteristics
        // Implement your specific communication logic here
        print("Discovered characteristics for service: \(service.uuid)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value: \(error.localizedDescription)")
            return
        }

        // Handle incoming data from device
        print("Received data from characteristic: \(characteristic.uuid)")
    }
}
