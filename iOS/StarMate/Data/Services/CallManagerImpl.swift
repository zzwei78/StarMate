import Foundation
import Combine

// MARK: - Call Manager Implementation

/// 通话管理器实现
///
/// 协调 AT 命令、音频流水线、录音器等模块，/// 管理完整的通话生命周期。
///
/// ## 通话流程
/// ```
/// 拨打电话:
/// makeCall() → ensureVoiceService() → ATD → startAudioPipeline() → callState = .connected
///
/// 接听来电:
/// answerCall() → ensureVoiceService() → ATA → startAudioPipeline() → callState = .connected
///
/// 挂断电话:
/// endCall() → stopAudioPipeline() → AT+CHUP → stopVoiceService() → callState = .idle
/// ```
@MainActor
final class CallManagerImpl: CallManagerProtocol, ObservableObject {

    // MARK: - Published State

    @Published private(set) var callState: CallState = .idle
    @Published private(set) var currentCall: ActiveCall?
    @Published private(set) var isSpeakerOn: Bool = false
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var callRecords: [CallRecord] = []

    // MARK: - Dependencies

    private let atClient: AtServiceClientImpl
    private let systemClient: SystemServiceClientImpl
    private let bleManager: BleManagerImpl
    private let voiceClient: VoiceServiceClientImpl
    private let audioPipeline: AudioPipelineManager
    private let callRecorder: CallRecorderImpl
    private let recordingPreferences: RecordingPreferences

    // MARK: - Private Properties

    private var callStartTime: Date?
    private var callTimer: Timer?
    private var urcTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        atClient: AtServiceClientImpl,
        systemClient: SystemServiceClientImpl,
        bleManager: BleManagerImpl,
        voiceClient: VoiceServiceClientImpl,
        callRecorder: CallRecorderImpl,
        recordingPreferences: RecordingPreferences
    ) {
        self.atClient = atClient
        self.systemClient = systemClient
        self.bleManager = bleManager
        self.voiceClient = voiceClient
        self.callRecorder = callRecorder
        self.recordingPreferences = recordingPreferences

        // 创建音频流水线
        self.audioPipeline = AudioPipelineManager()
        self.audioPipeline.delegate = self

        // 设置语音客户端回调
        voiceClient.onAmrFrameReceived = { [weak self] amrData in
            Task { @MainActor [weak self] in
                self?.audioPipeline.feedDownlinkAmr(amrData)
            }
        }

        // 订阅 URC 通知
        setupUrcHandler()

        print("[CallManager] Initialized")
    }

    deinit {
        urcTask?.cancel()
        callTimer?.invalidate()
    }

    // MARK: - Call Control

    /// 拨打电话
    func makeCall(phoneNumber: String) async -> Result<Void, Error> {
        guard callState == .idle else {
            let error = CallManagerError.busy
            print("[CallManager] ❌ Cannot make call: already in call")
            return .failure(error)
        }

        guard !phoneNumber.isEmpty else {
            let error = CallManagerError.invalidPhoneNumber
            return .failure(error)
        }

        do {
            // 1. 更新状态为拨号中
            callState = .dialing(phoneNumber: phoneNumber)

            // 2. 确保 Voice Service 启用
            try await ensureVoiceServiceEnabled()

            // 3. 等待服务稳定
            try await Task.sleep(nanoseconds: 400_000_000)

            // 4. 发送 ATD 命令
            print("[CallManager] 📞 Dialing \(phoneNumber)...")
            let dialResult = await atClient.sendCommand("ATD\(phoneNumber);", timeoutMs: 30000)

            switch dialResult {
            case .success(let response):
                print("[CallManager] ✅ Dial response: \(response)")
            case .failure(let error):
                throw error
            }

            // 5. 启动音频流水线
            try await startAudioPipeline()

            // 6. 更新状态为已连接
            callStartTime = Date()
            currentCall = ActiveCall(
                phoneNumber: phoneNumber,
                startTime: callStartTime!,
                isSpeakerOn: false,
                callState: .connected(phoneNumber: phoneNumber, startTime: callStartTime!)
            )
            callState = .connected(phoneNumber: phoneNumber, startTime: callStartTime!)

            // 7. 开始计时
            startCallTimer()

            // 8. 开始录音 (如果允许)
            if recordingPreferences.allowCallRecording {
                await callRecorder.startRecording()
            }

            print("[CallManager] ✅ Call connected")
            return .success(())

        } catch {
            // 发生错误，重置状态
            callState = .idle
            currentCall = nil
            await cleanupAfterCall()
            return .failure($0)
        }
    }

    /// 接听来电
    func answerCall() async -> Result<Void, Error> {
        guard case .incoming(let phoneNumber) = callState else {
            let error = CallManagerError.noIncomingCall
            return .failure(error)
        }

        do {
            // 1. 确保 Voice Service 启用
            try await ensureVoiceServiceEnabled()

            // 2. 等待服务稳定
            try await Task.sleep(nanoseconds: 400_000_000)

            // 3. 发送 ATA 掑令
            print("[CallManager] 📞 Answering call...")
            let answerResult = await atClient.sendCommand("ATA", timeoutMs: 30000)

            switch answerResult {
            case .success(let response):
                print("[CallManager] ✅ Answer response: \(response)")
            case .failure(let error):
                throw error
            }

            // 4. 启动音频流水线
            try await startAudioPipeline()

            // 5. 更新状态为已连接
            callStartTime = Date()
            currentCall = ActiveCall(
                phoneNumber: phoneNumber,
                startTime: callStartTime!,
                isSpeakerOn: false,
                callState: .connected(phoneNumber: phoneNumber, startTime: callStartTime!)
            )
            callState = .connected(phoneNumber: phoneNumber, startTime: callStartTime!)

            // 6. 开始计时
            startCallTimer()

            // 7. 开始录音 (如果允许)
            if recordingPreferences.allowCallRecording {
                await callRecorder.startRecording()
            }

            print("[CallManager] ✅ Call answered and connected")
            return .success(())

        } catch {
            callState = .idle
            currentCall = nil
            await cleanupAfterCall()
            return .failure($0)
        }
    }

    /// 挂断电话
    func endCall() async -> Result<Void, Error> {
        guard callState.isInCall else {
            return .success(()) // 没有通话，直接返回成功
        }

        print("[CallManager] 📵 Ending call...")

        // 1. 停止音频流水线
        await stopAudioPipeline()

        // 2. 停止录音
        await callRecorder.stopRecording()

        // 3. 发送挂断命令
        _ = await atClient.sendCommand("AT+CHUP")

        // 4. 停止 Voice Service
        _ = await systemClient.stopVoiceService()

        // 5. 保存通话记录
        if let call = currentCall {
            let record = CallRecord(
                phoneNumber: call.phoneNumber,
                contactName: nil,
                callType: callState.isIncoming ? .incoming : .outgoing,
                callStatus: .completed,
                startTime: call.startTime,
                duration: call.duration
            )
            callRecords.insert(record, at: 0)
        }

        // 6. 更新状态
        callState = .idle
        currentCall = nil
        callStartTime = nil

        // 7. 停止计时
        stopCallTimer()

        print("[CallManager] ✅ Call ended")
        return .success(())
    }

    /// 拒接来电
    func rejectCall() async -> Result<Void, Error> {
        guard case .incoming(let phoneNumber) = callState else {
            let error = CallManagerError.noIncomingCall
            return .failure(error)
        }

        print("[CallManager] 📵 Rejecting call from \(phoneNumber)")

        // 发送挂断命令
        _ = await atClient.sendCommand("AT+CHUP")

        // 保存为未接来电记录
        let record = CallRecord(
            phoneNumber: phoneNumber,
            contactName: nil,
            callType: .incoming,
            callStatus: .missed,
            startTime: Date(),
            duration: 0
        )
        callRecords.insert(record, at: 0)

        callState = .idle

        return .success(())
    }

    // MARK: - In-Call Actions

    /// 发送 DTMF 音
    func sendDtmf(_ key: DtmfKey) async -> Result<Void, Error> {
        guard callState.isInCall else {
            return .failure(CallManagerError.notInCall)
        }

        // AT+VTS - 在通话中发送 DTMF 音
        let command = "AT+VTS=\(key.value)"
        return await atClient.sendCommand(command).map { _ in () }
    }

    /// 切换扬声器/听筒
    func toggleSpeaker() async -> Result<Void, Error> {
        isSpeakerOn.toggle()

        let newMode: AudioMode = isSpeakerOn ? .speaker : .earpiece
        let result = await audioPipeline.setAudioMode(newMode)

        switch result {
        case .success:
            print("[CallManager] 🔊 Audio mode: \(newMode)")
            return .success(())
        case .failure(let error):
            // 回滚状态
            isSpeakerOn.toggle()
            return .failure(error)
        }
    }

    /// 切换静音
    func toggleMute() async -> Result<Void, Error> {
        isMuted.toggle()

        if isMuted {
            // 静音：停止录音
            _ = await audioPipeline.stopRecording()
            print("[CallManager] 🔇 Muted")
        } else {
            // 取消静音：恢复录音
            _ = await audioPipeline.startRecording()
            print("[CallManager] 🔊 Unmuted")
        }

        return .success(())
    }

    // MARK: - Call Records

    /// 删除通话记录
    func deleteCallRecord(_ id: String) async {
        callRecords.removeAll { $0.id == id }
    }

    /// 清空所有通话记录
    func clearAllCallRecords() async {
        callRecords.removeAll()
    }

    // MARK: - Private Methods

    /// 确保 Voice Service 已启用
    private func ensureVoiceServiceEnabled() async throws {
        // 检查服务状态
        let statusResult = await systemClient.getServiceStatus(ServiceId.SPP_VOICE)

        let isEnabled: Bool
        switch statusResult {
        case .success(let status):
            isEnabled = status
        case .failure(let error):
            throw error
        }

        if isEnabled {
            print("[CallManager] Voice service already enabled")
            return
        }

        // 启用服务
        print("[CallManager] Enabling voice service...")
        let startResult = await systemClient.startVoiceService()

        switch startResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }

        // 重新发现服务
        let discoverResult = await bleManager.discoverServices()

        switch discoverResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }

        // 检查 Voice Service 是否可用
        if !bleManager.isVoiceServiceAvailable() {
            // 重试一次
            try await Task.sleep(nanoseconds: 300_000_000)
            _ = await systemClient.startVoiceService()
            _ = await bleManager.discoverServices()
        }

        print("[CallManager] ✅ Voice service enabled")
    }

    /// 启动音频流水线
    private func startAudioPipeline() async throws {
        print("[CallManager] Starting audio pipeline...")

        // 启动录音
        let recordResult = await audioPipeline.startRecording()
        switch recordResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }

        // 启动播放
        let playResult = await audioPipeline.startPlaying()
        switch playResult {
        case .success:
            print("[CallManager] ✅ Audio pipeline started")
        case .failure(let error):
            // 停止录音
            _ = await audioPipeline.stopRecording()
            throw error
        }
    }

    /// 停止音频流水线
    private func stopAudioPipeline() async {
        print("[CallManager] Stopping audio pipeline...")

        _ = await audioPipeline.stopRecording()
        _ = await audioPipeline.stopPlaying()

        print("[CallManager] ✅ Audio pipeline stopped")
    }

    /// 通话后清理
    private func cleanupAfterCall() async {
        await stopAudioPipeline()
        await callRecorder.stopRecording()
        _ = await systemClient.stopVoiceService()
    }

    /// 设置 URC 处理器
    private func setupUrcHandler() {
        urcTask = Task { [weak self] in
            for await notification in await self?.atClient.urcStream ?? AsyncStream<AtNotification>() {
                await self?.handleUrc(notification)
            }
        }
    }

    /// 处理 URC 通知
    private func handleUrc(_ notification: AtNotification) async {
        let data = notification.data.uppercased()

        if data.contains("RING") || data.contains("+CLIP:") {
            // 来电
            await handleIncomingCall(notification.data)
        } else if data.contains("+CLCC:") {
            // 通话状态变化
            await handleCallStatusChange(notification.data)
        } else if data.contains("NO CARRIER") || data.contains("BUSY") {
            // 通话结束
            await handleCallEnded()
        }
    }

    /// 处理来电
    private func handleIncomingCall(_ data: String) async {
        guard callState == .idle else { return }

        // 解析来电号码 (简化处理)
        var phoneNumber = "Unknown"

        if let clipRange = data.range(of: "+CLIP:") {
            let afterClip = data[clipRange.upperBound...]
            if let quoteStart = afterClip.firstIndex(of: "\""),
               let quoteEnd = afterClip[afterClip.index(afterClip.startIndex, offsetBy: quoteStart + 1)...].firstIndex(of: "\"") {
                let numberRange = afterClip.index(afterClip.startIndex, offsetBy: quoteStart + 1)..<quoteEnd
                phoneNumber = String(afterClip[numberRange])
            }
        }

        print("[CallManager] 📞 Incoming call from \(phoneNumber)")

        callState = .incoming(phoneNumber: phoneNumber)
    }

    /// 处理通话状态变化
    private func handleCallStatusChange(_ data: String) async {
        // +CLCC: 返回通话列表状态
        // 这里可以解析通话状态变化
        print("[CallManager] 📞 Call status changed")
    }

    /// 处理通话结束
    private func handleCallEnded() async {
        guard callState.isInCall else { return }

        print("[CallManager] 📞 Remote end detected")

        // 保存通话记录
        if let call = currentCall {
            let record = CallRecord(
                phoneNumber: call.phoneNumber,
                contactName: nil,
                callType: callState.isIncoming ? .incoming : .outgoing,
                callStatus: .completed,
                startTime: call.startTime,
                duration: call.duration
            )
            callRecords.insert(record, at: 0)
        }

        // 清理
        await stopAudioPipeline()
        await callRecorder.stopRecording()

        callState = .idle
        currentCall = nil
        stopCallTimer()
    }

    /// 开始通话计时
    private func startCallTimer() {
        callTimer?.invalidate()

        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 触发 UI 更新
                _ = self?.currentCall
            }
        }
    }

    /// 停止通话计时
    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
}

// MARK: - AudioPipelineDelegate

extension CallManagerImpl: AudioPipelineDelegate {

    /// 上行 AMR 帧已编码 (发送给设备)
    func audioPipeline(_ pipeline: AudioPipelineManager, didEncodeAmrFrame frame: Data) {
        // 发送 AMR 帧到设备
        Task {
            _ = await voiceClient.sendAmrFrame(frame)
        }
    }

    /// 上行 PCM 已采集 (送给录音器)
    func audioPipeline(_ pipeline: AudioPipelineManager, didCaptureUplinkPcm pcm: Data) {
        callRecorder.feedUplinkPcm(pcm)
    }

    /// 下行 PCM 已解码 (送给录音器)
    func audioPipeline(_ pipeline: AudioPipelineManager, didDecodeDownlinkPcm pcm: Data) {
        callRecorder.feedDownlinkPcm(pcm)
    }
}

// MARK: - Service ID

/// 服务 ID 常量
struct ServiceId {
    static let SPP_VOICE: UInt8 = 0x01
}

// MARK: - Call Manager Error

/// 通话管理器错误
enum CallManagerError: LocalizedError {
    case busy
    case notInCall
    case noIncomingCall
    case invalidPhoneNumber
    case voiceServiceFailed
    case audioFailed

    var errorDescription: String? {
        switch self {
        case .busy:
            return "通话正忙"
        case .notInCall:
            return "当前不在通话中"
        case .noIncomingCall:
            return "没有来电"
        case .invalidPhoneNumber:
            return "无效的电话号码"
        case .voiceServiceFailed:
            return "语音服务启动失败"
        case .audioFailed:
            return "音频初始化失败"
        }
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension CallManagerImpl {
    /// 打印当前状态
    func printStatus() {
        print("[CallManager] Status:")
        print("  - callState: \(callState)")
        print("  - currentCall: \(currentCall?.phoneNumber ?? "none")")
        print("  - isSpeakerOn: \(isSpeakerOn)")
        print("  - isMuted: \(isMuted)")
        print("  - callRecords: \(callRecords.count)")
        audioPipeline.printStatus()
    }
}
#endif
