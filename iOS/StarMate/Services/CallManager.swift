import Foundation

// MARK: - Call Manager (ViewModel Wrapper)

/// 通话管理器 ViewModel
///
/// 作为 SwiftUI View 和底层 CallManagerImpl 之间的桥梁
@MainActor
class CallManager: ObservableObject {

    // MARK: - Published State

    @Published var callState: CallState = .idle
    @Published var phoneNumber: String = ""
    @Published var isSpeakerOn = false
    @Published var isMuted = false

    @Published var callRecords: [CallRecord] = []

    @Published var incomingCall: CallRecord?

    @Published var allowCallRecording = true
    @Published var isRecording = false

    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var impl: CallManagerImpl?
    private var callStartTime: Date?
    private var callTimer: Timer?

    // BLE Manager (需要从环境获取或创建)
    private weak var bleManager: BleManagerImpl?

    // 创建独立的客户端实例（共享 BLE 连接）
    private lazy var atClient = AtServiceClientImpl()
    private lazy var systemClient = SystemServiceClientImpl()
    private lazy var voiceClient = VoiceServiceClientImpl()

    // MARK: - Initialization

    init(bleManager: BleManagerImpl? = nil) {
        self.bleManager = bleManager
        print("[CallManager-VM] Initialized with \(bleManager != nil ? "external" : "no") BLE manager")

        // 如果有 BLE manager，设置客户端的 BLE 引用
        if let bleManager = bleManager {
            setupClients(with: bleManager)
        }
    }

    /// 设置客户端的 BLE 引用
    private func setupClients(with bleManager: BleManagerImpl) {
        // 注意：这里需要根据实际的客户端实现来设置
        // 可能需要在客户端中添加对 BLE manager 的引用
        print("[CallManager-VM] Setting up clients with BLE manager")
    }

    /// 确保底层实现已初始化
    private func ensureImpl() -> CallManagerImpl? {
        if let impl = impl {
            return impl
        }

        guard let bleManager = bleManager else {
            print("[CallManager-VM] ⚠️ BLE Manager not available")
            return nil
        }

        // 从 BLE manager 获取共享的客户端
        // 注意：需要强制转换类型，因为协议返回的是协议类型
        let sharedAtClient = bleManager.getAtCommandClient() as! AtServiceClientImpl
        let sharedSystemClient = bleManager.getSystemClient() as! SystemServiceClientImpl
        let sharedVoiceClient = bleManager.getVoiceClient() as! VoiceServiceClientImpl

        // 创建底层实现
        let impl = CallManagerImpl(
            atClient: sharedAtClient,
            systemClient: sharedSystemClient,
            bleManager: bleManager,
            voiceClient: sharedVoiceClient,
            callRecorder: CallRecorderImpl(),
            recordingPreferences: RecordingPreferences.shared
        )

        // 监听状态变化
        observeImplState(impl)

        self.impl = impl
        print("[CallManager-VM] ✅ CallManagerImpl created")
        return impl
    }

    /// 监听底层实现的状态变化
    private func observeImplState(_ impl: CallManagerImpl) {
        // 使用 Timer 轮询状态变化 (简化实现)
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            // 同步状态
            if self.callState != impl.callState {
                self.callState = impl.callState
            }
            if self.isSpeakerOn != impl.isSpeakerOn {
                self.isSpeakerOn = impl.isSpeakerOn
            }
            if self.isMuted != impl.isMuted {
                self.isMuted = impl.isMuted
            }
            if self.callRecords != impl.callRecords {
                self.callRecords = impl.callRecords
            }
        }
    }

    // MARK: - Public Methods

    func onDigitPress(_ digit: String) {
        if phoneNumber.count < 20 {
            phoneNumber += digit
        }
    }

    func onBackspace() {
        if !phoneNumber.isEmpty {
            phoneNumber.removeLast()
        }
    }

    func makeCall() {
        guard !phoneNumber.isEmpty else {
            errorMessage = "请输入电话号码"
            return
        }

        Task {
            guard let impl = ensureImpl() else {
                errorMessage = "无法连接到设备，请确保蓝牙已连接"
                return
            }

            print("[CallManager-VM] 📞 Calling makeCall on impl...")
            let result = await impl.makeCall(phoneNumber: phoneNumber)

            switch result {
            case .success:
                print("[CallManager-VM] ✅ Call started successfully")
            case .failure(let error):
                print("[CallManager-VM] ❌ Call failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func answerCall() {
        Task {
            guard let impl = ensureImpl() else {
                errorMessage = "无法接听电话"
                return
            }

            let result = await impl.answerCall()

            switch result {
            case .success:
                print("[CallManager-VM] ✅ Call answered")
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func endCall() {
        Task {
            guard let impl = impl else {
                // 如果没有底层实现，直接更新状态
                callState = .ending(reason: .localHangup)
                stopCallTimer()

                try? await Task.sleep(nanoseconds: 500_000_000)
                callState = .idle
                phoneNumber = ""
                return
            }

            let result = await impl.endCall()

            switch result {
            case .success:
                print("[CallManager-VM] ✅ Call ended")
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func rejectCall() {
        Task {
            guard let impl = impl else {
                callState = .idle
                return
            }

            let result = await impl.rejectCall()
            switch result {
            case .success:
                callState = .idle
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleSpeaker() {
        Task {
            guard let impl = impl else {
                isSpeakerOn.toggle()
                return
            }

            let result = await impl.toggleSpeaker()

            switch result {
            case .success:
                break
            case .failure:
                isSpeakerOn.toggle()
            }
        }
    }

    func toggleMute() {
        Task {
            guard let impl = impl else {
                isMuted.toggle()
                return
            }

            let result = await impl.toggleMute()

            switch result {
            case .success:
                break
            case .failure:
                isMuted.toggle()
            }
        }
    }

    func sendDtmf(_ digit: String) {
        Task {
            guard let impl = impl else { return }
            // 尝试将数字转换为 DtmfKey
            if let dtmfKey = DtmfKey(rawValue: digit) {
                _ = await impl.sendDtmf(dtmfKey)
            }
        }
    }

    func fillNumberFromRecord(_ record: CallRecord) {
        phoneNumber = record.phoneNumber
    }

    func deleteCallRecord(_ record: CallRecord) {
        Task {
            await impl?.deleteCallRecord(record.id)
        }
    }

    func clearAllCallRecords() {
        Task {
            await impl?.clearAllCallRecords()
        }
    }

    func setAllowCallRecording(_ allowed: Bool) {
        allowCallRecording = allowed
    }

    func simulateIncomingCall(from number: String) {
        incomingCall = CallRecord(
            phoneNumber: number,
            callType: .incoming,
            callStatus: .missed
        )
        callState = .incoming(phoneNumber: number)
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private Methods

    private func startCallTimer() {
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Update call duration display
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
        callStartTime = nil
    }
}
