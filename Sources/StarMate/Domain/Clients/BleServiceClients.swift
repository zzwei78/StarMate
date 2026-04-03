import Foundation
import CoreBluetooth
import Combine

// MARK: - System Service Client Protocol
/// GATT System Service client (UUID: 0xABFC).
/// Handles device info, battery, signal, service management, TT Module status.
protocol SystemServiceClientProtocol: AnyObject {
    // MARK: - Published State
    var connectionState: CurrentValueSubject<ConnectState, Never> { get }
    var deviceInfo: CurrentValueSubject<SystemInfo?, Never> { get }
    var ttModuleState: CurrentValueSubject<TtModuleState?, Never> { get }

    // MARK: - Commands
    /// Read system info (0x30)
    func readInfo() async -> Result<SystemInfo, Error>

    /// Read version info (0x31) - system_version_info_t (96 bytes)
    func readVersionInfo() async -> Result<TerminalVersion, Error>

    /// Read battery status
    func readBattery() async -> Result<BatteryInfo, Error>

    /// Start voice service
    func startVoiceService() async -> Result<Void, Error>

    /// Stop voice service
    func stopVoiceService() async -> Result<Void, Error>

    /// Get service status via CMD_SERVICE_STATUS (0x12)
    func getServiceStatus(_ serviceId: UInt8) async -> Result<Bool, Error>

    /// Start OTA service
    func startOtaService() async -> Result<Void, Error>

    /// Reboot MCU
    func rebootMcu() async -> Result<Void, Error>

    /// Reboot TT Module
    func rebootModule() async -> Result<Void, Error>

    /// Get TT Module status (v3.1)
    func getTtModuleStatus() async -> Result<TtModuleStatus, Error>

    /// Set TT Module power (v3.1)
    func setTtModulePower(_ enabled: Bool) async -> Result<Void, Error>

    /// Called by BleManager when GATT disconnects
    func onGattClosed()
}

// MARK: - AT Service Client Protocol
/// GATT AT Command Service client (UUID: 0xABF2).
/// Handles AT command send/receive and URC notification dispatch.
protocol AtServiceClientProtocol: AnyObject {
    // MARK: - Streams
    /// AT response stream
    var responseStream: AsyncStream<AtResponse> { get }

    /// URC (unsolicited result code) stream
    var urcStream: AsyncStream<AtNotification> { get }

    // MARK: - Commands
    /// Send AT command and wait for response
    func sendCommand(_ command: String) async -> Result<String, Error>

    /// Send AT command with custom timeout
    func sendCommand(_ command: String, timeoutMs: Int64) async -> Result<String, Error>

    /// Send AT command without waiting for response
    func sendCommandNoWait(_ command: String) async -> Result<Void, Error>

    /// Called by BleManager when GATT disconnects
    func onGattClosed()
}

// MARK: - Voice Service Client Protocol
/// GATT Voice Service client (UUID: 0xABF0).
/// Handles bidirectional voice data streaming during calls.
protocol VoiceServiceClientProtocol: AnyObject {
    // MARK: - Streams
    /// Voice data stream (receiving from device)
    var voiceDataStream: AsyncStream<VoicePacket> { get }

    // MARK: - Commands
    /// Send voice data to device
    func sendVoiceData(_ data: Data) async -> Result<Void, Error>

    /// Start recording
    func startRecording() async -> Result<Void, Error>

    /// Stop recording
    func stopRecording() async -> Result<Void, Error>

    /// Start playback
    func startPlaying() async -> Result<Void, Error>

    /// Stop playback
    func stopPlaying() async -> Result<Void, Error>

    /// Switch audio output mode
    func setAudioMode(_ mode: AudioMode) async -> Result<Void, Error>

    /// Called by BleManager when GATT disconnects
    func onGattClosed()
}

// MARK: - OTA Service Client Protocol
/// GATT OTA Service client (UUID: 0xABF8).
/// Handles MCU and TT Module firmware upgrades.
protocol OtaServiceClientProtocol: AnyObject {
    // MARK: - Published State
    var otaState: CurrentValueSubject<OtaState, Never> { get }

    // MARK: - Streams
    /// OTA progress stream (0-100)
    var progressStream: AsyncStream<Int> { get }

    // MARK: - Commands
    /// Start MCU OTA upgrade
    func startMcuOta(_ firmware: Data, crc32: Int) async -> Result<Void, Error>

    /// Start TT Module OTA upgrade
    func startTtOta(_ firmware: Data, crc32: Int) async -> Result<Void, Error>

    /// Abort current OTA
    func abortOta() async -> Result<Void, Error>

    /// Reset state to Idle
    func resetOtaState()

    /// Send firmware data packet
    func sendFirmwarePacket(seq: Int, data: Data) async -> Result<Void, Error>
}
