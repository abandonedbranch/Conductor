import SwiftUI
import FoundationModels

// MARK: - Wikipedia Tool

@available(iOS 19.0, macOS 26.0, *)
struct WikipediaSearchTool: Tool {
    let name = "searchWikipedia"
    let description = "Search Wikipedia for a summary of a topic"

    @Generable
    struct Arguments {
        @Guide(description: "The search query to look up on Wikipedia")
        var searchQuery: String

        @Guide(description: "Maximum length of the summary to return (default 500)")
        var maxSummaryLength: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let summary = try await searchWikipedia(query: arguments.searchQuery)
        let maxLength = arguments.maxSummaryLength ?? 500

        let truncatedSummary = String(summary.prefix(maxLength))

        return """
            Wikipedia Summary for "\(arguments.searchQuery)":

            \(truncatedSummary)
            """
    }
    
    private func searchWikipedia(query: String) async throws -> String {
        // Step 1: Use Wikipedia's search API to find the best matching article
        let articleTitle = try await findArticleTitle(for: query)

        // Step 2: Fetch the summary for that article
        let summaryURL = "https://en.wikipedia.org/api/rest_v1/page/summary/"
        guard let encodedTitle = articleTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: summaryURL + encodedTitle) else {
            throw WikipediaError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (Apple Intelligence App)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WikipediaError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw WikipediaError.notFound(query: query)
        }

        guard httpResponse.statusCode == 200 else {
            throw WikipediaError.httpError(statusCode: httpResponse.statusCode)
        }

        let wikipediaResponse = try JSONDecoder().decode(WikipediaResponse.self, from: data)

        return wikipediaResponse.extract
    }

    private func findArticleTitle(for query: String) async throws -> String {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else {
            throw WikipediaError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Conductor/1.0 (Apple Intelligence App)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let searchResponse = try JSONDecoder().decode(WikipediaSearchResponse.self, from: data)

        guard let firstResult = searchResponse.query.search.first else {
            throw WikipediaError.notFound(query: query)
        }

        return firstResult.title
    }
}

// MARK: - Wikipedia Supporting Types

struct WikipediaResponse: Codable {
    let extract: String
    let title: String
    let description: String?
}

struct WikipediaSearchResponse: Codable {
    let query: SearchQuery

    struct SearchQuery: Codable {
        let search: [SearchResult]
    }

    struct SearchResult: Codable {
        let title: String
    }
}

enum WikipediaError: LocalizedError {
    case invalidQuery
    case notFound(query: String)
    case invalidResponse
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is invalid."
        case .notFound(let query):
            return "No Wikipedia article found for \"\(query)\"."
        case .invalidResponse:
            return "Received an invalid response from Wikipedia."
        case .httpError(let statusCode):
            return "Wikipedia returned an error (HTTP \(statusCode))."
        }
    }
}

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
    private let lastSelectedChatKey = "conductor.lastSelectedChat"
    
    init() {
        loadChats()
    }
    
    func saveLastSelectedChat(_ chatId: UUID?) {
        if let chatId = chatId {
            UserDefaults.standard.set(chatId.uuidString, forKey: lastSelectedChatKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSelectedChatKey)
        }
    }
    
    func loadLastSelectedChat() -> Chat? {
        guard let uuidString = UserDefaults.standard.string(forKey: lastSelectedChatKey),
              let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        return chats.first(where: { $0.id == uuid })
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
    
    func deleteChat(_ chat: Chat) {
        // Remove the chat
        chats.removeAll(where: { $0.id == chat.id })
        
        // Remove associated messages
        chatMessages.removeValue(forKey: chat.id)
        
        // Clear last selected chat if this was it
        if let lastSelectedUUID = UserDefaults.standard.string(forKey: lastSelectedChatKey),
           let uuid = UUID(uuidString: lastSelectedUUID),
           uuid == chat.id {
            UserDefaults.standard.removeObject(forKey: lastSelectedChatKey)
        }
        
        saveChats()
    }
    
    func deleteChats(at offsets: IndexSet) {
        let chatsToDelete = offsets.map { chats[$0] }
        for chat in chatsToDelete {
            deleteChat(chat)
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
                        .id(chat.id) // Force view to recreate when chat changes
                } else {
                    UnsupportedOSView()
                }
            } else {
                ChatEmptyStateView()
            }
        }
        .onAppear {
            // Load the last selected chat on startup
            if selectedChat == nil {
                selectedChat = chatManager.loadLastSelectedChat()
            }
        }
        .onChange(of: selectedChat) { _, newChat in
            // Save the selected chat whenever it changes
            chatManager.saveLastSelectedChat(newChat?.id)
        }
    }
}

// MARK: - Sidebar View

struct ChatSidebarView: View {
    let chatManager: ChatManager
    @Binding var selectedChat: Chat?
    
    var body: some View {
        List(selection: $selectedChat) {
            ForEach(chatManager.chats) { chat in
                ChatRowView(chat: chat)
                    .tag(chat)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteChat(chat)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteChat(chat)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .onDelete { indexSet in
                // This handles keyboard delete on macOS
                if let selectedChat = selectedChat,
                   let index = chatManager.chats.firstIndex(where: { $0.id == selectedChat.id }),
                   indexSet.contains(index) {
                    self.selectedChat = nil
                }
                
                chatManager.deleteChats(at: indexSet)
            }
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
    
    private func deleteChat(_ chat: Chat) {
        // Clear selection if we're deleting the selected chat
        if selectedChat?.id == chat.id {
            selectedChat = nil
        }
        
        chatManager.deleteChat(chat)
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
            
            Text(relativeTimeString(from: chat.timestamp))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        
        if interval < 60 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else if days < 7 {
            return "\(days)d ago"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
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
        
        // Create a session with tools
        let instructions = """
You are The Conductor — an intelligent intermediary that interprets human intent \
and coordinates device capabilities to fulfill that intent.

Your role is orchestration, not assistance. When given a request:
- Infer the underlying goal, not just the surface request
- Identify what system capabilities are needed to achieve it
- Coordinate actions across multiple functions when necessary
- Explain your reasoning and what you're doing — transparency is non-negotiable

Available capabilities:
- Wikipedia lookup: When you need factual information, historical context, or \
  encyclopedic knowledge, use the WikipediaSearchTool. Always tell the user \
  what you're looking up and why.

Core principles:
- Clarity over cleverness: Use direct language. No marketing speak.
- Systems thinking: Consider workflow and coordination, not just single actions.
- Minimal friction: Extend the user's thinking; don't make them operate a tool.
- Technical honesty: Acknowledge your limits. Don't oversell capabilities.
- Privacy: You process locally. The Wikipedia tool accesses the internet to \
  retrieve information — be transparent when using it.

When you act, be explicit about what you're doing and why. The user should always \
understand your decision-making process. If you can't do something, say so clearly \
and explain the limitation.

You sit between what users want to accomplish and what their device can do. \
The user specifies the outcome; you determine the path.
"""
        
        // Create and register tools
        let wikipediaTool = WikipediaSearchTool()
        
        self.session = LanguageModelSession(
            tools: [wikipediaTool],
            instructions: instructions
        )
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
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }
                
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
                            .font(.system(size: 25))
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
                streamingContent = partial.content
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
            // Handle general errors
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
