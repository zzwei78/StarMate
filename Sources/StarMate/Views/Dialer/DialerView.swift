import SwiftUI

struct DialerView: View {
    @EnvironmentObject var callManager: CallManager

    var body: some View {
        NavigationStack {
            Group {
                switch callManager.callState {
                case .idle:
                    if callManager.incomingCall != nil {
                        IncomingCallView(
                            phoneNumber: callManager.incomingCall?.phoneNumber ?? "",
                            onAnswer: { callManager.answerCall() },
                            onReject: { callManager.rejectCall() }
                        )
                    } else {
                        DialPadView()
                    }

                case .dialing(let number):
                    InCallView(
                        phoneNumber: number,
                        statusText: "Dialing...",
                        isSpeakerOn: callManager.isSpeakerOn,
                        onEndCall: { callManager.endCall() },
                        onToggleSpeaker: { callManager.toggleSpeaker() }
                    )

                case .connected(let number, _):
                    InCallView(
                        phoneNumber: number,
                        statusText: "Connected",
                        isSpeakerOn: callManager.isSpeakerOn,
                        onEndCall: { callManager.endCall() },
                        onToggleSpeaker: { callManager.toggleSpeaker() }
                    )

                case .incoming(let number):
                    IncomingCallView(
                        phoneNumber: number,
                        onAnswer: { callManager.answerCall() },
                        onReject: { callManager.rejectCall() }
                    )

                case .ending:
                    InCallView(
                        phoneNumber: "",
                        statusText: "Call ended",
                        isSpeakerOn: false,
                        onEndCall: {},
                        onToggleSpeaker: {}
                    )
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Dial Pad View
struct DialPadView: View {
    @EnvironmentObject var callManager: CallManager

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Call History
            if !callManager.callRecords.isEmpty {
                CallHistorySection(
                    records: callManager.callRecords,
                    onRecordClick: { callManager.fillNumberFromRecord($0) },
                    onRecordDelete: { callManager.deleteCallRecord($0) },
                    onClearAll: { callManager.clearAllCallRecords() }
                )
            }

            // Phone Number Display
            Text(callManager.phoneNumber.isEmpty ? "请输入号码" : formatPhoneNumber(callManager.phoneNumber))
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(callManager.phoneNumber.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xxl)

            // Error Message
            if let error = callManager.errorMessage {
                ErrorBanner(message: error, onDismiss: { callManager.clearError() })
            }

            Spacer()

            // Keypad
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(keypadRows, id: \.self) { row in
                    HStack(spacing: AppTheme.Spacing.lg) {
                        ForEach(row, id: \.self) { key in
                            DialButton(key: key) {
                                callManager.onDigitPress(key)
                            }
                        }
                    }
                }
            }

            Spacer()

            // Action Buttons
            HStack(spacing: AppTheme.Spacing.xxl) {
                // Contacts Button
                Button(action: {}) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.systemBlue)
                }

                // Call Button
                Button(action: { callManager.makeCall() }) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.systemGreen)
                        .clipShape(Circle())
                }

                // Backspace Button
                Button(action: { callManager.onBackspace() }) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.systemBlue)
                }
                .disabled(callManager.phoneNumber.isEmpty)
                .opacity(callManager.phoneNumber.isEmpty ? 0.3 : 1)
            }
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .background(Color.systemGray6)
    }

    var keypadRows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["*", "0", "#"]
        ]
    }

    func formatPhoneNumber(_ number: String) -> String {
        // Simple formatting - add spaces
        var result = ""
        for (index, char) in number.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}

// MARK: - Dial Button
struct DialButton: View {
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 72, height: 72)
                .background(Color.systemGray5)
                .clipShape(Circle())
        }
    }
}

// MARK: - Call History Section
struct CallHistorySection: View {
    let records: [CallRecord]
    let onRecordClick: (CallRecord) -> Void
    let onRecordDelete: (String) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("通话记录")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("清空", action: onClearAll)
                    .font(.caption)
            }

            ForEach(records.prefix(5)) { record in
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: record.callType.icon)
                        .foregroundColor(record.callType.color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.contactName ?? record.phoneNumber)
                            .font(.subheadline)
                        Text(record.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { onRecordDelete(record.id) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.systemRed)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onRecordClick(record) }
            }
        }
        .padding()
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.medium)
    }
}

// MARK: - In Call View
struct InCallView: View {
    let phoneNumber: String
    let statusText: String
    let isSpeakerOn: Bool
    let onEndCall: () -> Void
    let onToggleSpeaker: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xxl) {
            Spacer()

            // Call Info
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundColor(.systemBlue)

                Text(phoneNumber)
                    .font(.system(size: 28, weight: .semibold))

                Text(statusText)
                    .font(.headline)
                    .foregroundColor(.systemBlue)
            }

            Spacer()

            // In-call Controls
            HStack(spacing: AppTheme.Spacing.xxl) {
                // Speaker
                VStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onToggleSpeaker) {
                        Image(systemName: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill")
                            .font(.system(size: 24))
                            .foregroundColor(isSpeakerOn ? .systemBlue : .primary)
                            .frame(width: 56, height: 56)
                            .background(isSpeakerOn ? Color.systemBlue.opacity(0.2) : Color.systemGray5)
                            .clipShape(Circle())
                    }
                    Text("Speaker")
                        .font(.caption2)
                }

                // Keypad
                VStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: {}) {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                            .frame(width: 56, height: 56)
                            .background(Color.systemGray5)
                            .clipShape(Circle())
                    }
                    Text("Keypad")
                        .font(.caption2)
                }

                // Mute
                VStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: {}) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                            .frame(width: 56, height: 56)
                            .background(Color.systemGray5)
                            .clipShape(Circle())
                    }
                    Text("Mute")
                        .font(.caption2)
                }
            }

            Spacer()

            // End Call Button
            Button(action: onEndCall) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.systemRed)
                    .clipShape(Circle())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.systemGray6)
    }
}

// MARK: - Incoming Call View
struct IncomingCallView: View {
    let phoneNumber: String
    let onAnswer: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xxl) {
            Spacer()

            // Call Info
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundColor(.systemBlue)

                Text("Incoming Call")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text(phoneNumber)
                    .font(.system(size: 28, weight: .bold))
            }

            Spacer()

            // Answer/Reject Buttons
            HStack(spacing: 80) {
                // Reject
                VStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onReject) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Color.systemRed)
                            .clipShape(Circle())
                    }
                    Text("Decline")
                        .font(.caption)
                }

                // Answer
                VStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onAnswer) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Color.systemGreen)
                            .clipShape(Circle())
                    }
                    Text("Accept")
                        .font(.caption)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.systemGray6)
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.systemRed)

            Text(message)
                .font(.caption)
                .foregroundColor(.systemRed)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.medium)
    }
}

#Preview {
    DialerView()
        .environmentObject(CallManager())
}
