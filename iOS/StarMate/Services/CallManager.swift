import Foundation

// MARK: - Call Manager
class CallManager: ObservableObject {
    // Call State
    @Published var callState: CallState = .idle
    @Published var phoneNumber: String = ""
    @Published var isSpeakerOn = false
    @Published var isMuted = false

    // Call Records
    @Published var callRecords: [CallRecord] = []

    // Incoming Call
    @Published var incomingCall: CallRecord?

    // Recording
    @Published var allowCallRecording = true
    @Published var isRecording = false

    // Error
    @Published var errorMessage: String?

    private var callStartTime: Date?
    private var callTimer: Timer?

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
        guard !phoneNumber.isEmpty else { return }

        callState = .dialing(phoneNumber: phoneNumber)

        // Simulate dialing and connecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }

            self.callState = .connected(phoneNumber: self.phoneNumber, startTime: Date())
            self.callStartTime = Date()
            self.startCallTimer()

            // Add to call records
            let record = CallRecord(
                phoneNumber: self.phoneNumber,
                callType: .outgoing,
                callStatus: .completed
            )
            self.callRecords.insert(record, at: 0)
        }
    }

    func answerCall() {
        guard let incoming = incomingCall else { return }

        callState = .connected(phoneNumber: incoming.phoneNumber, startTime: Date())
        callStartTime = Date()
        startCallTimer()
        incomingCall = nil
    }

    func endCall() {
        if case .connected(let number, let startTime) = callState {
            // Update call record duration
            let duration = Date().timeIntervalSince(startTime)
            if let index = callRecords.firstIndex(where: { $0.phoneNumber == number }) {
                let old = callRecords[index]
                callRecords[index] = CallRecord(
                    id: old.id,
                    phoneNumber: old.phoneNumber,
                    contactName: old.contactName,
                    callType: old.callType,
                    callStatus: .completed,
                    startTime: old.startTime,
                    duration: duration
                )
            }
        }

        callState = .ending
        stopCallTimer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.callState = .idle
            self?.phoneNumber = ""
        }
    }

    func rejectCall() {
        incomingCall = nil
        callState = .idle
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func sendDtmf(_ digit: String) {
        // Send DTMF tone
    }

    func fillNumberFromRecord(_ record: CallRecord) {
        phoneNumber = record.phoneNumber
    }

    func deleteCallRecord(_ id: String) {
        callRecords.removeAll { $0.id == id }
    }

    func clearAllCallRecords() {
        callRecords = []
    }

    func setAllowCallRecording(_ allowed: Bool) {
        allowCallRecording = allowed
    }

    // Simulate incoming call
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
