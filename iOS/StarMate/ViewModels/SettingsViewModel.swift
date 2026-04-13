import Foundation
import Combine
import SwiftUI
import AVFoundation

@MainActor
class SettingsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isConnected: Bool = false
    @Published var connectionState: ConnectState = .disconnected
    @Published var connectedDeviceAddress: String?
    @Published var ttModuleState: TtModuleState?
    @Published var allowCallRecording: Bool = false
    @Published var terminalVersion: TerminalVersion?
    @Published var basebandVersion: BasebandVersion?
    @Published var otaState: OtaState = .idle
    @Published var otaProgress: Int = 0
    @Published var isRebooting: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var error: String?
    @Published var message: String?

    // MARK: - Audio Test Manager

    let audioTestManager: AudioTestManager

    // MARK: - Dependencies

    private var bleManager: BleManagerImpl  // 改为 var 以允许更新
    private var systemClient: SystemServiceClientImpl {
        return bleManager.getSystemClient() as! SystemServiceClientImpl
    }
    private var atClient: AtServiceClientImpl {
        return bleManager.getAtCommandClient() as! AtServiceClientImpl
    }
    private var otaClient: OtaServiceClientImpl {
        return bleManager.getOtaServiceClient() as! OtaServiceClientImpl
    }
    private let recordingPreferences: RecordingPreferences

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - File Picker State

    @Published var selectedFirmwareUrl: URL?
    @Published var selectedOtaTarget: OtaTarget?

    // MARK: - Initialization

    init(bleManager: BleManagerImpl, recordingPreferences: RecordingPreferences = .shared) {
        self.bleManager = bleManager
        self.recordingPreferences = recordingPreferences

        // 初始化音频测试管理器
        let voiceClient = bleManager.getVoiceClient() as? VoiceServiceClientImpl
        self.audioTestManager = AudioTestManager(voiceClient: voiceClient, bleManager: bleManager)

        setupBindings()
    }

    /// 更新 BLE Manager（从 Environment 注入）
    func updateBleManager(_ newBleManager: BleManagerImpl) {
        // 如果是同一个实例，不需要更新
        if bleManager === newBleManager { return }

        bleManager = newBleManager

        // 重新设置绑定
        cancellables.removeAll()
        setupBindings()

        // 更新音频测试管理器的 voice client 和 bleManager
        let voiceClient = bleManager.getVoiceClient() as? VoiceServiceClientImpl
        audioTestManager.updateVoiceClient(voiceClient)
        audioTestManager.updateBleManager(newBleManager)

        // 立即同步当前状态
        self.connectionState = bleManager.connectionState
        self.isConnected = bleManager.connectionState.isConnected
        if case .connected(let address, _) = bleManager.connectionState {
            self.connectedDeviceAddress = address
        }

        print("[SettingsViewModel] Updated with shared bleManager, isConnected: \(isConnected)")
    }

    private func setupBindings() {
        // Subscribe to connection state
        bleManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.connectionState = state

                let connected: Bool
                var address: String? = nil
                switch state {
                case .connected(let deviceAddress, _):
                    connected = true
                    address = deviceAddress
                default:
                    connected = false
                }
                self.isConnected = connected
                self.connectedDeviceAddress = address

                // Load versions when connected
                if connected {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
                        await self.refreshVersions()
                    }
                } else {
                    // Clear data on disconnect
                    self.terminalVersion = nil
                    self.basebandVersion = nil
                    self.ttModuleState = nil
                }
            }
            .store(in: &cancellables)

        // Subscribe to TT module state from systemClient
        systemClient.ttModuleState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.ttModuleState = state
            }
            .store(in: &cancellables)

        // Subscribe to OTA state
        otaClient.otaState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.otaState = state
                self?.otaProgress = state.progress
            }
            .store(in: &cancellables)

        // Subscribe to recording preference
        recordingPreferences.$allowCallRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$allowCallRecording)
    }

    // MARK: - Version Info

    func refreshVersions() async {
        guard isConnected else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // Load terminal version via GATT
        let versionResult = await systemClient.readVersionInfo()
        switch versionResult {
        case .success(let version):
            terminalVersion = version
        case .failure(let error):
            print("[SettingsVM] Failed to read terminal version: \(error.localizedDescription)")
        }

        // Load TT module status
        let statusResult = await systemClient.getTtModuleStatus()
        switch statusResult {
        case .success(let status):
            ttModuleState = status.state
        case .failure(let error):
            print("[SettingsVM] Failed to read TT module status: \(error.localizedDescription)")
        }

        // Load baseband info via AT commands (only if TT module is working)
        if ttModuleState?.isWorking == true {
            await loadBasebandInfo()
        }
    }

    private func loadBasebandInfo() async {
        // Get IMSI
        let imsiResult = await atClient.sendCommand("AT+CIMI")
        let imsi = extractValue(from: imsiResult)

        // Get CCID
        let ccidResult = await atClient.sendCommand("AT+CCID")
        let ccid = extractCcidValue(from: ccidResult)

        // Get software version
        let swResult = await atClient.sendCommand("AT+CGMR")
        let swVersion = extractValue(from: swResult)

        // Get hardware version / model
        let hwResult = await atClient.sendCommand("AT+CGMM")
        let hwVersion = extractValue(from: hwResult)

        basebandVersion = BasebandVersion(
            imei: "",
            imsi: imsi,
            ccid: ccid,
            softwareVersion: swVersion,
            hardwareVersion: hwVersion,
            model: "",
            manufacturer: ""
        )
    }

    private func extractValue(from result: Result<String, Error>) -> String {
        switch result {
        case .success(let response):
            // Extract the value from AT response (remove OK and whitespace)
            let lines = response.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed != "OK" && !trimmed.hasPrefix("+") {
                    return trimmed
                }
            }
            return response.replacingOccurrences(of: "\nOK", with: "").trimmingCharacters(in: .whitespaces)
        case .failure:
            return ""
        }
    }

    private func extractCcidValue(from result: Result<String, Error>) -> String {
        switch result {
        case .success(let response):
            // AT+CCID returns: +CCID: 89860000000000000000
            if let range = response.range(of: "+CCID:") {
                let value = response[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = value.components(separatedBy: .newlines)
                return lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
            }
            return extractValue(from: result)
        case .failure:
            return ""
        }
    }

    // MARK: - Device Management

    func rebootMcu() async {
        isRebooting = true
        let result = await systemClient.rebootMcu()
        switch result {
        case .success:
            message = "终端正在重启，蓝牙可能在30-45秒内暂时不可连接，系统将自动重连"
        case .failure(let error):
            self.error = error.localizedDescription
        }
        isRebooting = false
    }

    func rebootTtModule() async {
        isRebooting = true
        let result = await systemClient.rebootModule()
        switch result {
        case .success:
            message = "天通模块正在重启"
            // Refresh status after reboot
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            _ = await systemClient.getTtModuleStatus()
        case .failure(let error):
            self.error = error.localizedDescription
        }
        isRebooting = false
    }

    func setTtModulePower(_ enabled: Bool) async {
        let result = await systemClient.setTtModulePower(enabled)
        switch result {
        case .success:
            message = enabled ? "天通模块已开启" : "天通模块已关闭"
            // Refresh status after power change
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = await systemClient.getTtModuleStatus()
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }

    // MARK: - Call Recording

    func setAllowCallRecording(_ enabled: Bool) {
        recordingPreferences.setAllowCallRecording(enabled)
    }

    // MARK: - OTA

    func startMcuOta(firmwareUrl: URL) async {
        guard let firmwareData = try? Data(contentsOf: firmwareUrl) else {
            error = "无法读取固件文件"
            return
        }

        let crc32 = firmwareData.crc32()
        let result = await otaClient.startMcuOta(firmwareData, crc32: Int(crc32))
        if case .failure(let err) = result {
            error = err.localizedDescription
        }
    }

    func startTtOta(firmwareUrl: URL) async {
        guard let firmwareData = try? Data(contentsOf: firmwareUrl) else {
            error = "无法读取固件文件"
            return
        }

        let crc32 = firmwareData.crc32()
        let result = await otaClient.startTtOta(firmwareData, crc32: Int(crc32))
        if case .failure(let err) = result {
            error = err.localizedDescription
        }
    }

    func abortOta() async {
        _ = await otaClient.abortOta()
    }

    func resetOtaState() {
        otaClient.resetOtaState()
    }

    // MARK: - Audio Testing (临时测试功能 - 已屏蔽)

    /*
    // 测试相关属性
    @Published var isTestRecording: Bool = false
    @Published var testRecordingDuration: String = "0.0s"
    @Published var testAmrFramesEncoded: Int = 0
    @Published var testAmrFramesDecoded: Int = 0
    @Published var testAudioLevel: Float = 0.0
    @Published var testFilePath: String?

    private var testRecordingTimer: Timer?
    private var testRecordingStartTime: Date?
    private var testAudioEngine: AVAudioEngine?
    private var testAudioFormat: AVAudioFormat?
    private var testAudioPlayer: AVAudioPlayer?
    private var testAudioConverter: AVAudioConverter?
    private var testAmrEncoder: AmrNbEncoder?
    private var testPcm8kHzBuffer: Data = Data()
    private var testAmrData: Data = Data()
    private let testPcmFrameSize: Int = 320

    // 测试录音相关函数已屏蔽...
    */

    // MARK: - Utility

    // MARK: - Utility

    func clearError() {
        error = nil
    }

    func clearMessage() {
        message = nil
    }
}
