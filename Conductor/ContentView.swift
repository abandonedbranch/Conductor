import SwiftUI
import SwiftUI
import FoundationModels

// MARK: - Models

struct Chat: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String  // Changed to var so it can be updated
    var lastMessage: String
    var timestamp: Date
    
    init(id: UUID = UUID(), title: String, lastMessage: String, timestamp: Date) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.timestamp = timestamp
    }
}

struct Message: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - Chat Manager

@Observable
class ChatManager {
    var chats: [Chat] = []
    var chatMessages: [UUID: [Message]] = [:]
    
    private let chatsKey = "conductor.savedChats"
    private let messagesKey = "conductor.savedMessages"
    
    init() {
        loadChats()
    }
    
    func createNewChat() -> Chat {
        let newChat = Chat(
            title: "New Conversation",
            lastMessage: "Start a new chat...",
            timestamp: Date()
        )
        chats.insert(newChat, at: 0)
        chatMessages[newChat.id] = []
        saveChats()
        return newChat
    }
    
    func addMessage(_ message: Message, to chatId: UUID) {
        if chatMessages[chatId] == nil {
            chatMessages[chatId] = []
        }
        chatMessages[chatId]?.append(message)
        
        // Update the chat's last message and timestamp
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            chats[index].lastMessage = message.content
            chats[index].timestamp = message.timestamp
            
            // Generate a title from the first user message if still default
            if chats[index].title == "New Conversation" && message.isUser {
                chats[index].title = generateTitle(from: message.content)
            }
        }
        
        saveChats()
    }
    
    func getMessages(for chatId: UUID) -> [Message] {
        return chatMessages[chatId] ?? []
    }
    
    private func generateTitle(from message: String) -> String {
        let maxLength = 50
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        let truncated = String(trimmed.prefix(maxLength))
        return truncated + "..."
    }
    
    private func saveChats() {
        if let encoded = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(encoded, forKey: chatsKey)
        }
        if let encoded = try? JSONEncoder().encode(chatMessages) {
            UserDefaults.standard.set(encoded, forKey: messagesKey)
        }
    }
    
    private func loadChats() {
        if let data = UserDefaults.standard.data(forKey: chatsKey),
           let decoded = try? JSONDecoder().decode([Chat].self, from: data) {
            chats = decoded
        }
        if let data = UserDefaults.standard.data(forKey: messagesKey),
           let decoded = try? JSONDecoder().decode([UUID: [Message]].self, from: data) {
            chatMessages = decoded
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedChat: Chat?
    @State private var chatManager = ChatManager()
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            ChatSidebarView(chatManager: chatManager, selectedChat: $selectedChat)
        } detail: {
            // Main chat area
            if let chat = selectedChat {
                if #available(iOS 19.0, macOS 26.0, *) {
                    ChatDetailView(chat: chat, chatManager: chatManager)
                } else {
                    UnsupportedOSView()
                }
            } else {
                ChatEmptyStateView()
            }
        }
    }
}

// MARK: - Sidebar View

struct ChatSidebarView: View {
    let chatManager: ChatManager
    @Binding var selectedChat: Chat?
    
    var body: some View {
        List(chatManager.chats, selection: $selectedChat) { chat in
            ChatRowView(chat: chat)
                .tag(chat)
        }
        .navigationTitle("Conductor")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let newChat = chatManager.createNewChat()
                    selectedChat = newChat
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

// MARK: - Chat Row View

struct ChatRowView: View {
    let chat: Chat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.title)
                .font(.headline)
                .lineLimit(1)
            
            Text(chat.lastMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            Text(chat.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Detail View

@available(iOS 19.0, macOS 26.0, *)
struct ChatDetailView: View {
    let chat: Chat
    let chatManager: ChatManager
    
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isResponding = false
    @State private var streamingContent = ""
    @State private var modelAvailability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)
    
    private let model = SystemLanguageModel.default
    private let session: LanguageModelSession
    
    init(chat: Chat, chatManager: ChatManager) {
        self.chat = chat
        self.chatManager = chatManager
        
        // Create a session
        let instructions = """
        You are The Conductor, a helpful virtual assistant and user agent.
        You provide expert guidance on a variety of topics, and are able to call various built-in tools to automate everyday tasks.
        Keep your responses clear, practical, and encouraging.
        Focus on helping and educating the user.
        """
        self.session = LanguageModelSession(instructions: instructions)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Model availability status
            if modelAvailability != .available {
                modelStatusBanner
            }
            
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                        
                        // Show streaming response
                        if isResponding && !streamingContent.isEmpty {
                            MessageBubbleView(message: Message(
                                content: streamingContent,
                                isUser: false,
                                timestamp: Date()
                            ))
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: streamingContent) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack(spacing: 12) {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #else
                    .background(Color(uiColor: .systemGray6))
                    #endif
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .disabled(isResponding || modelAvailability != .available)
                
                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    if isResponding {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(messageText.isEmpty || modelAvailability != .available ? .gray : .blue)
                    }
                }
                .disabled(messageText.isEmpty || isResponding || modelAvailability != .available)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle(chat.title)
        #if os(macOS)
        .navigationSubtitle("\(messages.count) messages")
        #endif
        .onAppear {
            messages = chatManager.getMessages(for: chat.id)
            modelAvailability = model.availability
        }
    }
    
    @ViewBuilder
    private var modelStatusBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text(modelStatusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #else
        .background(Color(uiColor: .systemGray6))
        #endif
    }
    
    private var modelStatusMessage: String {
        switch modelAvailability {
        case .available:
            return "Apple Intelligence is ready"
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Please enable Apple Intelligence in Settings"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading or not ready"
        case .unavailable:
            return "Apple Intelligence is unavailable"
        }
    }
    
    private func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard modelAvailability == .available else { return }
        guard !isResponding else { return }
        
        let userMessageContent = messageText
        messageText = ""
        
        // Add user message
        let userMessage = Message(
            content: userMessageContent,
            isUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)
        chatManager.addMessage(userMessage, to: chat.id)
        
        // Start streaming response
        isResponding = true
        streamingContent = ""
        
        do {
            // Stream the response from Foundation Models
            let stream = session.streamResponse(to: userMessageContent)
            
            for try await partial in stream {
                streamingContent = partial.content ?? ""
            }
            
            // Once streaming is complete, save the final message
            if !streamingContent.isEmpty {
                let assistantMessage = Message(
                    content: streamingContent,
                    isUser: false,
                    timestamp: Date()
                )
                messages.append(assistantMessage)
                chatManager.addMessage(assistantMessage, to: chat.id)
            }
        } catch {
            // Handle errors
            let errorMessage = Message(
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                isUser: false,
                timestamp: Date()
            )
            messages.append(errorMessage)
            chatManager.addMessage(errorMessage, to: chat.id)
        }
        
        isResponding = false
        streamingContent = ""
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    #if os(macOS)
                    .background(message.isUser ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    #else
                    .background(message.isUser ? Color.blue : Color(uiColor: .systemGray5))
                    #endif
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Empty State View

struct ChatEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text("Conductor")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Select a chat or start a new conversation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unsupported OS View

struct UnsupportedOSView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("OS Version Not Supported")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Conductor requires iOS 19.0 or macOS 26.0 or later to use Apple Intelligence features.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
