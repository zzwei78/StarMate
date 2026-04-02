import Foundation

// MARK: - SMS Manager
class SMSManager: ObservableObject {
    // Conversations
    @Published var conversations: [ConversationWithMessages] = []

    // Selected Conversation
    @Published var selectedConversationId: String?

    // Messages for selected conversation
    @Published var messages: [Message] = []

    // Sending State
    @Published var isSending = false

    // Error
    @Published var errorMessage: String?

    // MARK: - Public Methods

    func selectConversation(_ id: String) {
        selectedConversationId = id
        if let conv = conversations.first(where: { $0.conversation.id == id }) {
            messages = conv.messages
            // Mark as read
            markAsRead(id)
        }
    }

    func clearSelectedConversation() {
        selectedConversationId = nil
        messages = []
    }

    func sendMessage(to phoneNumber: String, content: String) {
        guard !content.isEmpty else { return }

        isSending = true

        // Find or create conversation
        var conversationId: String?
        if let existing = conversations.first(where: { $0.conversation.phoneNumber == phoneNumber }) {
            conversationId = existing.conversation.id
        } else {
            let newConv = Conversation(phoneNumber: phoneNumber)
            conversationId = newConv.id
            conversations.append(ConversationWithMessages(conversation: newConv, messages: []))
        }

        guard let convId = conversationId else { return }

        // Create message
        let message = Message(
            conversationId: convId,
            content: content,
            messageType: .outgoing
        )

        // Simulate sending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            // Add to messages
            self.messages.append(message)

            // Update conversation
            if let index = self.conversations.firstIndex(where: { $0.conversation.id == convId }) {
                let old = self.conversations[index]
                var updatedMessages = old.messages
                updatedMessages.append(message)

                let updatedConv = Conversation(
                    id: old.conversation.id,
                    phoneNumber: old.conversation.phoneNumber,
                    contactName: old.conversation.contactName,
                    lastMessageContent: content,
                    lastMessageTime: Date(),
                    unreadCount: 0
                )

                self.conversations[index] = ConversationWithMessages(
                    conversation: updatedConv,
                    messages: updatedMessages
                )
            }

            self.isSending = false
        }
    }

    func deleteConversation(_ phoneNumber: String) {
        conversations.removeAll { $0.conversation.phoneNumber == phoneNumber }
        if selectedConversationId != nil {
            clearSelectedConversation()
        }
    }

    // MARK: - Private Methods

    private func markAsRead(_ conversationId: String) {
        if let index = conversations.firstIndex(where: { $0.conversation.id == conversationId }) {
            let old = conversations[index]
            var updatedConv = old.conversation
            updatedConv.unreadCount = 0

            conversations[index] = ConversationWithMessages(
                conversation: updatedConv,
                messages: old.messages
            )
        }
    }

    // Simulate receiving message
    func simulateIncomingMessage(from phoneNumber: String, content: String) {
        var conversationId: String?

        if let existing = conversations.first(where: { $0.conversation.phoneNumber == phoneNumber }) {
            conversationId = existing.conversation.id
        } else {
            let newConv = Conversation(phoneNumber: phoneNumber)
            conversationId = newConv.id
            conversations.append(ConversationWithMessages(conversation: newConv, messages: []))
        }

        guard let convId = conversationId else { return }

        let message = Message(
            conversationId: convId,
            content: content,
            messageType: .incoming
        )

        if let index = conversations.firstIndex(where: { $0.conversation.id == convId }) {
            let old = conversations[index]
            var updatedMessages = old.messages
            updatedMessages.append(message)

            let updatedConv = Conversation(
                id: old.conversation.id,
                phoneNumber: old.conversation.phoneNumber,
                contactName: old.conversation.contactName,
                lastMessageContent: content,
                lastMessageTime: Date(),
                unreadCount: old.conversation.unreadCount + 1
            )

            conversations[index] = ConversationWithMessages(
                conversation: updatedConv,
                messages: updatedMessages
            )
        }

        // If currently viewing this conversation, add to messages
        if selectedConversationId == convId {
            messages.append(message)
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
