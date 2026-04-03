import Foundation

// MARK: - Conversation
struct Conversation: Identifiable, Codable, Equatable {
    let id: String
    let phoneNumber: String
    let contactName: String?
    var lastMessageContent: String?
    var lastMessageTime: Date
    var unreadCount: Int

    init(id: String = UUID().uuidString,
         phoneNumber: String,
         contactName: String? = nil,
         lastMessageContent: String? = nil,
         lastMessageTime: Date = Date(),
         unreadCount: Int = 0) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.contactName = contactName
        self.lastMessageContent = lastMessageContent
        self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount
    }
}

// MARK: - Message
struct Message: Identifiable, Codable, Equatable {
    let id: String
    let conversationId: String
    let content: String
    let messageType: MessageType
    let timestamp: Date
    var isDelivered: Bool
    var isRead: Bool

    init(id: String = UUID().uuidString,
         conversationId: String,
         content: String,
         messageType: MessageType,
         timestamp: Date = Date(),
         isDelivered: Bool = false,
         isRead: Bool = false) {
        self.id = id
        self.conversationId = conversationId
        self.content = content
        self.messageType = messageType
        self.timestamp = timestamp
        self.isDelivered = isDelivered
        self.isRead = isRead
    }
}

// MARK: - Message Type
enum MessageType: String, Codable {
    case incoming
    case outgoing

    var isOutgoing: Bool {
        return self == .outgoing
    }
}

// MARK: - Conversation with Messages
struct ConversationWithMessages: Identifiable {
    let conversation: Conversation
    let messages: [Message]

    var id: String { conversation.id }
}

// MARK: - Date Formatting Extensions
extension Message {
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

extension Conversation {
    var formattedLastTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: lastMessageTime)
    }
}

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
