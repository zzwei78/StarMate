import Foundation

// MARK: - SMS Notification
/// SMS notification from +CMTI URC
struct SmsNotification: Equatable {
    let storage: String
    let index: Int
    let timestamp: Date
}

// MARK: - SMS Message
/// SMS message from AT+CMGR / AT+CMGL response
struct SmsMessage: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let phoneNumber: String
    let content: String
    let timestamp: Date
    let isRead: Bool

    init(id: UUID = UUID(), index: Int, phoneNumber: String, content: String, timestamp: Date, isRead: Bool) {
        self.id = id
        self.index = index
        self.phoneNumber = phoneNumber
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

// MARK: - SMSC Config
/// SMS center configuration from AT+CSCA
struct SmscConfig: Equatable {
    let number: String
    let type: Int
    let isDefault: Bool
}

// MARK: - Sending State
/// SMS sending state
enum SendingState: Equatable {
    case idle
    case sending(phoneNumber: String)
    case sent(messageRef: String)
    case failed(error: String)

    var isSending: Bool {
        if case .sending = self { return true }
        return false
    }
}
