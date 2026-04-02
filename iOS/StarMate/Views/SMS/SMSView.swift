import SwiftUI

struct SMSView: View {
    @EnvironmentObject var smsManager: SMSManager

    var body: some View {
        NavigationStack {
            Group {
                if smsManager.selectedConversationId != nil {
                    if let conv = smsManager.conversations.first(where: { $0.conversation.id == smsManager.selectedConversationId }) {
                        ChatDetailView(
                            phoneNumber: conv.conversation.phoneNumber,
                            contactName: conv.conversation.contactName,
                            messages: smsManager.messages,
                            isSending: smsManager.isSending,
                            onBack: { smsManager.clearSelectedConversation() },
                            onSend: { content in
                                smsManager.sendMessage(to: conv.conversation.phoneNumber, content: content)
                            }
                        )
                    }
                } else {
                    ConversationListView(
                        conversations: smsManager.conversations,
                        onConversationClick: { smsManager.selectConversation($0.conversation.id) },
                        onDelete: { smsManager.deleteConversation($0.conversation.phoneNumber) }
                    )
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Conversation List View
struct ConversationListView: View {
    let conversations: [ConversationWithMessages]
    let onConversationClick: (ConversationWithMessages) -> Void
    let onDelete: (ConversationWithMessages) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "message.fill")
                    .font(.system(size: 20))
                Text("Messages")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .padding()
            .background(Color.cardBackgroundLight)

            if conversations.isEmpty {
                // Empty State
                VStack(spacing: AppTheme.Spacing.lg) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No messages yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.systemGray6)
            } else {
                List {
                    ForEach(conversations) { conv in
                        ConversationItem(
                            conversation: conv,
                            onClick: { onConversationClick(conv) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDelete(conv)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Conversation Item
struct ConversationItem: View {
    let conversation: ConversationWithMessages
    let onClick: () -> Void

    var conv: Conversation { conversation.conversation }

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Avatar
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.systemGray3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conv.contactName ?? conv.phoneNumber)
                            .font(.headline)
                            .fontWeight(conv.unreadCount > 0 ? .bold : .regular)

                        Spacer()

                        if conv.lastMessageTime > Date(timeIntervalSince1970: 0) {
                            Text(conv.formattedLastTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(conv.lastMessageContent ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if conv.unreadCount > 0 {
                    Text("\(conv.unreadCount)")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.systemBlue)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Detail View
struct ChatDetailView: View {
    let phoneNumber: String
    let contactName: String?
    let messages: [Message]
    let isSending: Bool
    let onBack: () -> Void
    let onSend: (String) -> Void

    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: AppTheme.Spacing.md) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(spacing: 2) {
                    Text(contactName ?? phoneNumber)
                        .font(.headline)
                    Text(phoneNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Spacer().frame(width: 28)
            }
            .padding()
            .background(Color.cardBackgroundLight)

            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .background(Color.systemGray6)
                .onChange(of: messages.count) { oldValue, newValue in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input Bar
            HStack(spacing: AppTheme.Spacing.sm) {
                TextField("Type a message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isInputFocused)

                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(inputText.isEmpty ? .secondary : .systemBlue)
                    }
                }
                .disabled(inputText.isEmpty || isSending)
            }
            .padding()
            .background(Color.cardBackgroundLight)
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        onSend(inputText)
        inputText = ""
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.messageType.isOutgoing {
                Spacer()
            }

            VStack(alignment: message.messageType.isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(message.messageType.isOutgoing ? Color.systemBlue : Color.systemGray5)
                    .foregroundColor(message.messageType.isOutgoing ? .white : .primary)
                    .cornerRadius(AppTheme.CornerRadius.medium)

                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.messageType.isOutgoing ? .trailing : .leading)

            if !message.messageType.isOutgoing {
                Spacer()
            }
        }
    }
}

#Preview {
    SMSView()
        .environmentObject(SMSManager())
}
