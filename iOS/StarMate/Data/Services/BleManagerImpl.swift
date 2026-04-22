import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Manager Implementation
/// BLE Manager implementation using CoreBluetooth.
/// Handles device scanning, GATT connection, service discovery,
/// characteristic notification dispatch, and client management.
@MainActor
final class BleManagerImpl: NSObject, BleManagerProtocol, ObservableObject {

    // MARK: - Published State
    @Published private(set) var connectionState: ConnectState = .disconnected
    @Published private(set) var scannedDevices: [ScannedDevice] = []
    @Published private(set) var isScanning = false

    // MARK: - Private Properties
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var scanTimeoutTask: Task<Void, Never>?

    // GATT Characteristics
    private var systemControlChar: CBCharacteristic?
    private var systemInfoChar: CBCharacteristic?
    private var systemStatusChar: CBCharacteristic?
    private var atCommandChar: CBCharacteristic?
    private var atResponseChar: CBCharacteristic?
    private var voiceInChar: CBCharacteristic?
    private var voiceOutChar: CBCharacteristic?
    private var voiceDataChar: CBCharacteristic?
    private var otaControlChar: CBCharacteristic?
    private var otaDataChar: CBCharacteristic?
    private var otaStatusChar: CBCharacteristic?

    // MTU
    private var negotiatedMtu: Int = 23

    // Write Queue
    private var writeQueue: [(data: Data, characteristic: CBCharacteristic, completion: ((Result<Void, Error>) -> Void)?)] = []
    private var isWriting = false

    // Pending Operations
    private var pendingReadContinuation: CheckedContinuation<Result<Data, Error>, Never>?
    private var pendingWriteContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var pendingDiscoverContinuation: CheckedContinuation<Result<Void, Error>, Never>?

    // MARK: - Service Clients
    private let systemServiceClient: SystemServiceClientImpl
    private let atServiceClient: AtServiceClientImpl
    private let voiceServiceClient: VoiceServiceClientImpl
    private let otaServiceClient: OtaServiceClientImpl
    private let callRecorder: CallRecorderImpl

    // MARK: - Initialization

    override init() {
        self.callRecorder = CallRecorderImpl()
        self.systemServiceClient = SystemServiceClientImpl()
        self.atServiceClient = AtServiceClientImpl()
        self.voiceServiceClient = VoiceServiceClientImpl()
        self.otaServiceClient = OtaServiceClientImpl()
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)

        // Connect call recorder to voice client
        voiceServiceClient.callRecorder = callRecorder
    }

    // MARK: - Protocol: BleManagerProtocol

    func scanDevices() -> AsyncStream<ScannedDevice> {
        return AsyncStream { continuation in
            Task { @MainActor in
                guard centralManager?.state == .poweredOn else {
                    continuation.finish()
                    return
                }

                scannedDevices = []
                isScanning = true

                // Start scan
                centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

                // Set timeout
                scanTimeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    await self.stopScanInternal()
                    continuation.finish()
                }

                // Store continuation for delegate callbacks
                self.scanContinuation = continuation
            }
        }
    }

    private var scanContinuation: AsyncStream<ScannedDevice>.Continuation?

    func connect(_ deviceAddress: String) -> AsyncStream<ConnectState> {
        return AsyncStream { continuation in
            Task { @MainActor in
                // Clean up previous connection
                if let peripheral = connectedPeripheral {
                    centralManager?.cancelPeripheralConnection(peripheral)
                }
                connectedPeripheral = nil
                resetCharacteristics()

                // Find peripheral
                guard let peripheral = discoveredPeripherals[deviceAddress] else {
                    continuation.yield(.error(errorCode: -1, message: "Device not found"))
                    continuation.finish()
                    return
                }

                connectionState = .connecting(deviceAddress: deviceAddress)
                continuation.yield(.connecting(deviceAddress: deviceAddress))

                // Store continuation for delegate callbacks
                self.connectContinuation = continuation
                self.connectingAddress = deviceAddress

                // Connect
                peripheral.delegate = self
                centralManager?.connect(peripheral, options: nil)
            }
        }
    }

    private var connectContinuation: AsyncStream<ConnectState>.Continuation?
    private var connectingAddress: String?

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        resetState()
    }

    // MARK: - GATT Clients

    func getSystemClient() -> SystemServiceClientProtocol {
        return systemServiceClient
    }

    func getAtCommandClient() -> AtServiceClientProtocol {
        return atServiceClient
    }

    func getVoiceClient() -> VoiceServiceClientProtocol {
        return voiceServiceClient
    }

    func getCallRecorder() -> CallRecorderProtocol {
        return callRecorder
    }

    func getOtaClient() -> OtaServiceClientProtocol {
        return otaServiceClient
    }

    func isOtaInProgress() -> Bool {
        if case .writing = otaServiceClient.otaState.value { return true }
        if case .verifying = otaServiceClient.otaState.value { return true }
        return false
    }

    func getOtaServiceClient() -> OtaServiceClientProtocol {
        return otaServiceClient
    }

    // MARK: - MTU

    func requestMtu(_ mtu: Int) async -> Result<Int, Error> {
        guard let peripheral = connectedPeripheral else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
        }
        // CoreBluetooth doesn't support explicit MTU request on iOS
        // The system negotiates MTU automatically
        return .success(negotiatedMtu)
    }

    // MARK: - System Info Characteristic

    func readSystemInfoCharacteristic() async -> Result<Data, Error> {
        guard let peripheral = connectedPeripheral else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUuid.SYSTEM_SERVICE }) else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "System Service not found"]))
        }
        guard let char = service.characteristics?.first(where: { $0.uuid == BleUuid.SYSTEM_INFO }) else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "System Info characteristic not found"]))
        }

        return await withCheckedContinuation { continuation in
            pendingReadContinuation = continuation
            peripheral.readValue(for: char)

            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                if let _ = pendingReadContinuation {
                    pendingReadContinuation = nil
                    continuation.resume(returning: .failure(NSError(domain: "BLE", code: -2, userInfo: [NSLocalizedDescriptionKey: "Read timeout"])))
                }
            }
        }
    }

    // MARK: - Write Operations

    func writeCharacteristicAndWait(
        serviceUuid: CBUUID,
        charUuid: CBUUID,
        data: Data,
        writeType: CBCharacteristicWriteType,
        timeoutMs: Int64
    ) async -> Result<Void, Error> {
        guard let peripheral = connectedPeripheral else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service not found: \(serviceUuid)"]))
        }
        guard let char = service.characteristics?.first(where: { $0.uuid == charUuid }) else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Characteristic not found: \(charUuid)"]))
        }

        return await withCheckedContinuation { continuation in
            writeQueue.append((data: data, characteristic: char, completion: { result in
                continuation.resume(returning: result)
            }))
            processWriteQueue()
        }
    }

    func writeCharacteristicNoWait(
        serviceUuid: CBUUID,
        charUuid: CBUUID,
        data: Data,
        writeType: CBCharacteristicWriteType
    ) {
        guard let peripheral = connectedPeripheral else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else { return }
        guard let char = service.characteristics?.first(where: { $0.uuid == charUuid }) else { return }

        writeQueue.append((data: data, characteristic: char, completion: nil))
        processWriteQueue()
    }

    // MARK: - Connection Priority

    private var highPriorityMode: Bool = false

    func requestConnectionPriority(_ priority: Int) -> Bool {
        // Priority: 0 = normal, 1+ = high (low latency)
        // 注意：iOS 中心角色没有直接设置连接间隔的 API
        // Android 有 requestConnectionPriority()，iOS 只能由系统自动协商
        guard let peripheral = connectedPeripheral else {
            print("[BLE] ⚠️ Cannot set priority: not connected")
            return false
        }

        let previousMode = highPriorityMode
        highPriorityMode = priority > 0

        if highPriorityMode && !previousMode {
            print("[BLE] ⚡ HIGH PRIORITY MODE requested (iOS will auto-negotiate)")
            print("[BLE]    Note: iOS Central has NO API to set connection interval")
            print("[BLE]    Using .withoutResponse writes + high-precision timer")
        } else if !highPriorityMode && previousMode {
            print("[BLE] ▼ NORMAL PRIORITY MODE")
        }

        return true
    }

    func isInHighPriorityMode() -> Bool {
        return highPriorityMode
    }

    func discoverServices() async -> Result<Void, Error> {
        guard let peripheral = connectedPeripheral else {
            return .failure(NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
        }

        return await withCheckedContinuation { continuation in
            pendingDiscoverContinuation = continuation
            peripheral.discoverServices([
                BleUuid.SYSTEM_SERVICE,
                BleUuid.AT_SERVICE,
                BleUuid.VOICE_SERVICE,
                BleUuid.OTA_SERVICE
            ])

            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if let _ = pendingDiscoverContinuation {
                    pendingDiscoverContinuation = nil
                    continuation.resume(returning: .failure(NSError(domain: "BLE", code: -2, userInfo: [NSLocalizedDescriptionKey: "Discover timeout"])))
                }
            }
        }
    }

    func isVoiceServiceAvailable() -> Bool {
        guard let peripheral = connectedPeripheral else { return false }
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUuid.VOICE_SERVICE }) else { return false }
        let hasWrite = service.characteristics?.contains { $0.uuid == BleUuid.VOICE_IN || $0.uuid == BleUuid.VOICE_DATA } ?? false
        return hasWrite
    }

    // MARK: - Private Methods

    private func stopScanInternal() async {
        centralManager?.stopScan()
        isScanning = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        scanContinuation?.finish()
        scanContinuation = nil
    }

    /// 停止蓝牙扫描
    func stopScan() {
        centralManager?.stopScan()
        isScanning = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        scanContinuation?.finish()
        scanContinuation = nil
    }

    private func resetState() {
        connectedPeripheral = nil
        connectionState = .disconnected
        resetCharacteristics()
        discoveredPeripherals.removeAll()

        // Notify clients
        systemServiceClient.onGattClosed()
        atServiceClient.onGattClosed()
        voiceServiceClient.clearGattReferences()
        otaServiceClient.clearGattReferences()
    }

    private func resetCharacteristics() {
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
        writeQueue.removeAll()
        isWriting = false
    }

    private func processWriteQueue() {
        guard !isWriting, !writeQueue.isEmpty else { return }
        isWriting = true

        let item = writeQueue.removeFirst()
        connectedPeripheral?.writeValue(item.data, for: item.characteristic, type: .withResponse)
    }

    private func enableNotification(for characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        peripheral.setNotifyValue(true, for: characteristic)
    }

    private func dispatchNotification(data: Data, from characteristic: CBCharacteristic) {
        // 首先根据服务 UUID 分发（更可靠）
        if let service = characteristic.service {
            let serviceUuid = service.uuid

            switch serviceUuid {
            case BleUuid.VOICE_SERVICE:
                voiceServiceClient.handleNotification(data: data, from: characteristic)
                return

            case BleUuid.AT_SERVICE:
                atServiceClient.handleNotification(data: data, from: characteristic)
                return

            case BleUuid.SYSTEM_SERVICE:
                systemServiceClient.handleNotification(data: data, from: characteristic)
                return

            case BleUuid.OTA_SERVICE:
                otaServiceClient.handleNotification(data: data, from: characteristic)
                return

            default:
                break
            }
        }

        // 回退：如果服务不可用，使用特征值 UUID 分发
        switch characteristic.uuid {
        case BleUuid.VOICE_OUT, BleUuid.VOICE_DATA:
            voiceServiceClient.handleNotification(data: data, from: characteristic)

        case BleUuid.SYSTEM_CONTROL, BleUuid.SYSTEM_STATUS:
            systemServiceClient.handleNotification(data: data, from: characteristic)

        case BleUuid.AT_COMMAND, BleUuid.AT_RESPONSE:
            atServiceClient.handleNotification(data: data, from: characteristic)

        case BleUuid.OTA_CONTROL, BleUuid.OTA_STATUS:
            otaServiceClient.handleNotification(data: data, from: characteristic)

        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BleManagerImpl: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                print("[BLE] Powered on")
            case .poweredOff:
                connectionState = .error(errorCode: -1, message: "蓝牙未开启")
            case .unauthorized:
                connectionState = .error(errorCode: -1, message: "未授权蓝牙权限")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? "Unknown Device"
            let address = peripheral.identifier.uuidString

            discoveredPeripherals[address] = peripheral

            // Filter for TTCat devices only
            if name.contains("TTCat") || name.contains("天通猫") || name.contains("StarMate") {
                let device = ScannedDevice(name: name, address: address, rssi: RSSI.intValue)
                if !scannedDevices.contains(where: { $0.address == address }) {
                    scannedDevices.append(device)
                    scanContinuation?.yield(device)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedPeripheral = peripheral

            // Discover services
            peripheral.discoverServices([
                BleUuid.SYSTEM_SERVICE,
                BleUuid.AT_SERVICE,
                BleUuid.VOICE_SERVICE,
                BleUuid.OTA_SERVICE
            ])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            resetState()

            connectContinuation?.yield(.disconnected)
            connectContinuation?.finish()
            connectContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .error(errorCode: -1, message: "连接失败: \(error?.localizedDescription ?? "未知错误")")

            connectContinuation?.yield(.error(errorCode: -1, message: error?.localizedDescription ?? "连接失败"))
            connectContinuation?.finish()
            connectContinuation = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BleManagerImpl: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Error discovering services: \(error.localizedDescription)")
                pendingDiscoverContinuation?.resume(returning: .failure(error))
                pendingDiscoverContinuation = nil
                return
            }

            // Debug: Print all discovered services
            print("[BLE] 🔍 Discovered services:")
            peripheral.services?.forEach { service in
                print("[BLE]   Service: \(service.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: service)
            }

            // Complete pending discover
            pendingDiscoverContinuation?.resume(returning: .success(()))
            pendingDiscoverContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] Error discovering characteristics: \(error.localizedDescription)")
                return
            }

            guard let characteristics = service.characteristics else { return }

            // Debug: Print discovered characteristics
            print("[BLE] 📡 Service: \(service.uuid.uuidString)")
            for characteristic in characteristics {
                print("[BLE]   📝 Characteristic: \(characteristic.uuid.uuidString)")
            }

            for characteristic in characteristics {
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
                case BleUuid.VOICE_DATA:
                    voiceDataChar = characteristic
                    // VOICE_DATA 也需要订阅通知 (用于接收下行数据)
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

            // Set up service clients
            if service.uuid == BleUuid.SYSTEM_SERVICE {
                systemServiceClient.setPeripheral(peripheral, characteristics: characteristics)
            } else if service.uuid == BleUuid.AT_SERVICE {
                atServiceClient.setPeripheral(peripheral, characteristics: characteristics)
            } else if service.uuid == BleUuid.VOICE_SERVICE {
                print("[BLE] 🎙️ Setting up VoiceServiceClient with \(characteristics.count) characteristics")
                voiceServiceClient.setPeripheral(peripheral, characteristics: characteristics)
            } else if service.uuid == BleUuid.OTA_SERVICE {
                otaServiceClient.setPeripheral(peripheral, characteristics: characteristics)
            }

            // Notify connected when all required characteristics are found
            if systemControlChar != nil && atCommandChar != nil {
                if let address = connectingAddress {
                    connectionState = .connected(deviceAddress: address, mtu: negotiatedMtu)
                    connectContinuation?.yield(.connected(deviceAddress: address, mtu: negotiatedMtu))

                    // iPhone 连接后设置为 3 帧模式
                    Task {
                        let result = await systemServiceClient.setVoiceFrameMode(0x03)
                        switch result {
                        case .success(let mode):
                            print("[BLE] ✅ Voice frame mode configured: \(mode) frames/packet")
                        case .failure(let error):
                            print("[BLE] ⚠️ Failed to set voice frame mode: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[BLE] ❌ Error updating value: \(error.localizedDescription)")
                return
            }

            guard let data = characteristic.value else { return }

            // Handle System Info read
            if characteristic.uuid == BleUuid.SYSTEM_INFO {
                pendingReadContinuation?.resume(returning: .success(data))
                pendingReadContinuation = nil
                return
            }

            // Dispatch to appropriate client
            dispatchNotification(data: data, from: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            isWriting = false

            if let error = error {
                print("[BLE] Write error: \(error.localizedDescription)")
                pendingWriteContinuation?.resume(returning: .failure(error))
                pendingWriteContinuation = nil
            } else {
                pendingWriteContinuation?.resume(returning: .success(()))
                pendingWriteContinuation = nil
            }

            // Process next item in queue
            processWriteQueue()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateMTU mtu: Int, error: Error?) {
        Task { @MainActor in
            if error == nil {
                negotiatedMtu = mtu
                print("[BLE] MTU updated to \(mtu)")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let voiceDataReceived = Notification.Name("voiceDataReceived")
}

// MARK: - Type Alias for Backward Compatibility
/// Type alias for backward compatibility with code using BLEManager
typealias BLEManager = BleManagerImpl
