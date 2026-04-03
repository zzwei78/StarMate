import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Manager Protocol
/// BLE connection manager.
/// Responsible for scanning, GATT connection, and managing GATT clients.
protocol BleManagerProtocol: AnyObject {
    // MARK: - Scanning
    /// Scan for TTCat devices
    func scanDevices() -> AsyncStream<ScannedDevice>

    // MARK: - Connection
    /// Connect to a specific device
    func connect(_ deviceAddress: String) -> AsyncStream<ConnectState>

    /// Disconnect from current device
    func disconnect()

    // MARK: - State
    /// True when OTA is writing firmware or verifying
    func isOtaInProgress() -> Bool

    // MARK: - GATT Clients
    func getSystemClient() -> SystemServiceClientProtocol
    func getAtCommandClient() -> AtServiceClientProtocol
    func getVoiceClient() -> VoiceServiceClientProtocol
    func getOtaServiceClient() -> OtaServiceClientProtocol

    // MARK: - MTU
    /// Request MTU
    func requestMtu(_ mtu: Int) async -> Result<Int, Error>

    // MARK: - System Info Characteristic
    /// Read System Info characteristic (0xABFE) - 96 bytes version info
    func readSystemInfoCharacteristic() async -> Result<Data, Error>

    // MARK: - Write Operations
    /// Write characteristic and suspend until write completion
    func writeCharacteristicAndWait(
        serviceUuid: CBUUID,
        charUuid: CBUUID,
        data: Data,
        writeType: CBCharacteristicWriteType,
        timeoutMs: Int64
    ) async -> Result<Void, Error>

    /// Enqueue a write without waiting for callback
    func writeCharacteristicNoWait(
        serviceUuid: CBUUID,
        charUuid: CBUUID,
        data: Data,
        writeType: CBCharacteristicWriteType
    )

    // MARK: - Connection Priority
    /// Request BLE connection priority for lower latency
    func requestConnectionPriority(_ priority: Int) -> Bool

    // MARK: - Service Discovery
    /// Re-discover GATT services
    func discoverServices() async -> Result<Void, Error>

    // MARK: - Voice Service Check
    /// Query whether Voice Service is present and has a writable characteristic
    func isVoiceServiceAvailable() -> Bool
}
