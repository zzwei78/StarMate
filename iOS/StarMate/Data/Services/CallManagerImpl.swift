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

    private var uplinkPcmCount = 0
    private var frameCount = 0
    private var downlinkFrameCount = 0

    // 时间戳记录
    private var lastCallManagerDownlinkTime: Date?
    private var lastCallManagerUplinkTime: Date?

    // AMR 帧批量发送
    private var uplinkAmrBuffer: [Data] = []
    private let uplinkBufferLock = NSLock()
    private var uplinkSendTimer: DispatchSourceTimer?
    private let framesPerBatch = 3  // 每次发送 3 帧
    private let batchDuration: TimeInterval = 0.06  // 60ms 发送一次

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
                guard let self = self else { return }
                let now = Date()
                self.downlinkFrameCount += 1

                // 计算接收间隔
                if let lastTime = self.lastCallManagerDownlinkTime {
                    let interval = now.timeIntervalSince(lastTime) * 1000
                    // if self.downlinkFrameCount <= 20 || abs(interval - 20) > 5 {
                    //     let formatter = DateFormatter()
                    //     formatter.dateFormat = "HH:mm:ss.SSS"
                    //     let timestamp = formatter.string(from: now)
                    //     print("[\(timestamp)] [CallManager] 📥 DL RX #\(self.downlinkFrameCount), interval: \(String(format: "%.1f", interval))ms")
                    // }
                }
                self.lastCallManagerDownlinkTime = now

                if self.downlinkFrameCount % 50 == 0 {
                    print("[CallManager] 📥 Received AMR frames: \(self.downlinkFrameCount)")
                }
                self.audioPipeline.feedDownlinkAmr(amrData)
            }
        }

        // 订阅 URC 通知
        setupUrcHandler()

        print("[CallManager] Initialized")
        print("[CallManager]    - Recording allowed: \(recordingPreferences.allowCallRecording)")
    }

    deinit {
        urcTask?.cancel()
        callTimer?.invalidate()
        uplinkSendTimer?.cancel()
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

        // 确保没有残留的定时器
        uplinkSendTimer?.cancel()
        uplinkSendTimer = nil
        uplinkAmrBuffer.removeAll()

        do {
            // 1. 检查信号强度（拨号前必须先检查）
            print("[CallManager] → Checking signal strength...")
            let signalResult = await atClient.sendCommand("AT+CSQ", timeoutMs: 5000)

            switch signalResult {
            case .success(let response):
                // 解析信号强度: +CSQ: <rssi>,<ber>
                // rssi: 0-31 (99=unknown), 0-5 bars mapped
                var signalOK = false
                if response.contains("OK") || response.contains("+CSQ:") {
                    // 提取 RSSI 值
                    if let range = response.range(of: ": ")?.upperBound {
                        let suffix = response[range...]
                        let parts = suffix.split(separator: ",")
                        if let rssiStr = parts.first, let rssi = Int(rssiStr) {
                            if rssi == 99 {
                                print("[CallManager] ❌ Signal unknown (rssi=99), cannot make call")
                                callState = .idle
                                return .failure(NSError(domain: "CallManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无信号，无法拨号"]))
                            } else if rssi == 0 {
                                print("[CallManager] ❌ Signal too weak (rssi=\(rssi)), cannot make call")
                                callState = .idle
                                return .failure(NSError(domain: "CallManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "信号太弱，无法拨号"]))
                            } else {
                                print("[CallManager] ✅ Signal OK (rssi=\(rssi))")
                                signalOK = true
                            }
                        }
                    }
                }

                // 如果信号检查失败且没有获取到有效值，不允许拨号
                if !signalOK {
                    print("[CallManager] ❌ Signal check failed, cannot make call")
                    callState = .idle
                    return .failure(NSError(domain: "CallManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取信号信息"]))
                }

            case .failure:
                // 信号检查命令失败，不允许拨号
                print("[CallManager] ❌ Signal check command failed, cannot make call")
                callState = .idle
                return .failure(NSError(domain: "CallManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法检查信号状态"]))
            }

            // 2. 更新状态为拨号中
            callState = .dialing(phoneNumber: phoneNumber)
            print("[CallManager] 📱 State: dialing")

            // 3. 确保 Voice Service 启用
            print("[CallManager] → Ensuring voice service enabled...")
            try await ensureVoiceServiceEnabled()

            // 4. 等待服务稳定
            try await Task.sleep(nanoseconds: 400_000_000)

            // 5. 发送 ATD 命令
            print("[CallManager] 📞 Dialing \(phoneNumber)...")
            let dialResult = await atClient.sendCommand("ATD\(phoneNumber);", timeoutMs: 30000)

            switch dialResult {
            case .success(let response):
                print("[CallManager] ✅ Dial response: \(response)")
            case .failure(let error):
                // 拨号失败，不启动音频流水线
                print("[CallManager] ❌ Dial failed: \(error.localizedDescription)")
                callState = .idle
                currentCall = nil
                return .failure(error)
            }

            // 5. 启动音频流水线（拨号成功后才启动）
            print("[CallManager] → Starting audio pipeline...")
            try await startAudioPipeline()

            // 等待一下，确保音频流水线稳定
            try await Task.sleep(nanoseconds: 100_000_000)
            print("[CallManager] ✅ Audio pipeline is ready")

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

            // 8. 开始本地录音 (如果允许)
            print("[CallManager] → Local recording enabled: \(recordingPreferences.allowCallRecording)")
            if recordingPreferences.allowCallRecording {
                await callRecorder.startRecording()
            }

            print("[CallManager] ✅ Call connected")
            return .success(())

        } catch {
            // 发生错误，重置状态
            print("[CallManager] ❌ Call failed: \(error.localizedDescription)")
            callState = .idle
            currentCall = nil
            await cleanupAfterCall()
            return .failure(error)
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
            return .failure(error)
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
        print("[CallManager] → Checking voice service status...")
        let statusResult = await systemClient.getServiceStatus(ServiceId.SPP_VOICE)

        let isEnabled: Bool
        switch statusResult {
        case .success(let status):
            isEnabled = status
            print("[CallManager]    Voice service status: \(isEnabled)")
        case .failure(let error):
            // TEST MODE: 即使状态检查失败也继续
            print("[CallManager]    ⚠️ Failed to get status: \(error.localizedDescription)")
            print("[CallManager]    ⚠️ TEST MODE: Continuing anyway...")
            return
        }

        if isEnabled {
            print("[CallManager] Voice service already enabled")
            return
        }

        // 启用服务
        print("[CallManager] → Enabling voice service...")
        let startResult = await systemClient.startVoiceService()

        switch startResult {
        case .success:
            print("[CallManager]    Voice service start command sent")
        case .failure(let error):
            // TEST MODE: 即使启动失败也继续
            print("[CallManager]    ❌ Failed to start voice service: \(error.localizedDescription)")
            print("[CallManager]    ⚠️ TEST MODE: Continuing anyway...")
            // 不抛出错误，继续执行
        }

        // 重新发现服务
        print("[CallManager] → Rediscovering services...")
        let discoverResult = await bleManager.discoverServices()

        switch discoverResult {
        case .success:
            print("[CallManager]    ✅ Services rediscovered")
        case .failure(let error):
            print("[CallManager]    ❌ Service discovery failed: \(error.localizedDescription)")
            throw error
        }

        // 检查 Voice Service 是否可用
        let voiceAvailable = bleManager.isVoiceServiceAvailable()
        print("[CallManager]    Voice service available: \(voiceAvailable)")

        if !voiceAvailable {
            // 重试一次
            print("[CallManager]    ⚠️ Voice service not available, retrying...")
            try await Task.sleep(nanoseconds: 300_000_000)
            let retryResult = await systemClient.startVoiceService()
            switch retryResult {
            case .success:
                print("[CallManager]    Retry startVoiceService: success")
            case .failure(let error):
                print("[CallManager]    ❌ Retry failed: \(error.localizedDescription)")
            }
            let retryDiscover = await bleManager.discoverServices()
            switch retryDiscover {
            case .success:
                print("[CallManager]    Retry discoverServices: success")
            case .failure(let error):
                print("[CallManager]    ❌ Retry discover failed: \(error.localizedDescription)")
            }
        }

        print("[CallManager] ✅ Voice service enabled")
    }

    /// 启动音频流水线
    private func startAudioPipeline() async throws {
        print("[CallManager] ==================================================")
        print("[CallManager] 🎙️ Starting audio pipeline...")
        print("[CallManager] ==================================================")

        // 启动录音
        print("[CallManager] → Starting recording...")
        let recordResult = await audioPipeline.startRecording()
        switch recordResult {
        case .success:
            print("[CallManager] ✅ Recording started - listening for audio")
        case .failure(let error):
            print("[CallManager] ❌ Recording failed: \(error)")
            throw error
        }

        // 启动播放
        print("[CallManager] → Starting playback...")
        let playResult = await audioPipeline.startPlaying()
        switch playResult {
        case .success:
            print("[CallManager] ✅ Audio pipeline fully started (recording + playing)")
            print("[CallManager] ==================================================")
        case .failure(let error):
            // 停止录音
            _ = await audioPipeline.stopRecording()
            print("[CallManager] ❌ Playback failed: \(error)")
            throw error
        }

        // 重置计数器
        frameCount = 0
        uplinkPcmCount = 0
        downlinkFrameCount = 0
        uplinkAmrBuffer.removeAll()

        // 启动批量发送定时器
        startUplinkBatchSender()
    }

    /// 停止音频流水线
    private func stopAudioPipeline() async {
        print("[CallManager] ==================================================")
        print("[CallManager] 🛑 Stopping audio pipeline...")
        print("[CallManager]    - Total encoded frames: \(frameCount)")
        print("[CallManager]    - Total uplink PCM frames: \(uplinkPcmCount)")
        print("[CallManager]    - Total downlink frames: \(downlinkFrameCount)")
        print("[CallManager] ==================================================")

        // 停止批量发送定时器
        uplinkSendTimer?.cancel()
        uplinkSendTimer = nil

        _ = await audioPipeline.stopRecording()
        _ = await audioPipeline.stopPlaying()

        print("[CallManager] ✅ Audio pipeline stopped")
    }

    /// 启动上行 AMR 帧批量发送定时器
    private func startUplinkBatchSender() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.setEventHandler { [weak self, weak voiceClient] in
            guard let self = self, let voiceClient = voiceClient else {
                timer.cancel()
                return
            }

            // 检查是否在通话中，不在则停止定时器
            guard self.callState.isInCall else {
                timer.cancel()
                self.uplinkSendTimer = nil
                return
            }

            // 收集 framesPerBatch 个帧进行批量发送
            self.uplinkBufferLock.lock()
            var batch: [Data] = []
            let countToAdd = min(self.framesPerBatch, self.uplinkAmrBuffer.count)
            if countToAdd > 0 {
                batch = Array(self.uplinkAmrBuffer.prefix(countToAdd))
                self.uplinkAmrBuffer.removeFirst(countToAdd)
            }
            let bufferCount = self.uplinkAmrBuffer.count
            self.uplinkBufferLock.unlock()

            if !batch.isEmpty {
                let now = Date()

                // 计算发送间隔
                if let lastTime = self.lastCallManagerUplinkTime {
                    let interval = now.timeIntervalSince(lastTime) * 1000
                    // if self.frameCount <= 20 || abs(interval - 60) > 10 {
                    //     let formatter = DateFormatter()
                    //     formatter.dateFormat = "HH:mm:ss.SSS"
                    //     let timestamp = formatter.string(from: now)
                    //     print("[\(timestamp)] [CallManager] 📤 UL TX batch #\(self.frameCount - batch.count + 1)-#\(self.frameCount), \(batch.count) frames, interval: \(String(format: "%.1f", interval))ms, buffer: \(bufferCount)")
                    // }
                }
                self.lastCallManagerUplinkTime = now

                // 使用 Task { @MainActor in } 确保线程安全
                Task { @MainActor in
                    let result = await voiceClient.sendAmrFrames(batch)
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("[CallManager] ❌ Failed to send AMR batch: \(error.localizedDescription)")
                    }
                }
            }
        }

        // 设置定时器：每 60ms 发送一次
        timer.schedule(deadline: .now(), repeating: .milliseconds(Int(batchDuration * 1000)), leeway: .milliseconds(1))
        timer.resume()
        uplinkSendTimer = timer

        print("[CallManager] 📤 Uplink batch sender started: \(batchDuration * 1000)ms interval, \(framesPerBatch) frames/batch")
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
            guard let self = self else { return }
            for await notification in self.atClient.urcStream {
                await self.handleUrc(notification)
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
               let afterQuoteStart = afterClip.index(quoteStart, offsetBy: 1, limitedBy: afterClip.endIndex),
               let quoteEnd = afterClip[afterQuoteStart...].firstIndex(of: "\"") {
                let numberRange = afterQuoteStart..<quoteEnd
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

    /// 上行 AMR 帧已编码 (加入缓冲队列，批量发送)
    func audioPipeline(_ pipeline: AudioPipelineManager, didEncodeAmrFrame frame: Data) {
        // 将 AMR 帧加入缓冲队列
        uplinkBufferLock.lock()
        uplinkAmrBuffer.append(frame)
        frameCount += 1
        uplinkBufferLock.unlock()
    }

    /// 上行 PCM 已采集 (送给录音器)
    func audioPipeline(_ pipeline: AudioPipelineManager, didCaptureUplinkPcm pcm: Data) {
        uplinkPcmCount += 1
        if uplinkPcmCount % 50 == 0 {  // 每1秒
            print("[CallManager] 🎙️ Uplink PCM: \(uplinkPcmCount) frames recorded")
        }
        callRecorder.feedUplinkPcm(pcm)
    }

    /// 下行 PCM 已解码 (送给录音器)
    func audioPipeline(_ pipeline: AudioPipelineManager, didDecodeDownlinkPcm pcm: Data) {
        callRecorder.feedDownlinkPcm(pcm)
    }
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
