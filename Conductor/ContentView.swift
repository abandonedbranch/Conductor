import SwiftUI
import FoundationModels

// MARK: - Models

struct Chat: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
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
    var sources: [ToolSource]

    enum CodingKeys: String, CodingKey {
        case id, content, isUser, timestamp, sources
    }

    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date, sources: [ToolSource] = []) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        isUser = try container.decode(Bool.self, forKey: .isUser)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sources = try container.decodeIfPresent([ToolSource].self, forKey: .sources) ?? []
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
    private let snapshotsKey = "conductor.savedSnapshots"
    private var chatSnapshots: [UUID: Data] = [:]

    init() {
        loadChats()
        loadSnapshots()
    }

    @available(iOS 19.0, macOS 26.0, *)
    func saveSnapshot(_ snapshot: GraphSnapshot, for chatID: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        chatSnapshots[chatID] = data
        persistSnapshots()
    }

    func saveSnapshotRaw(_ data: Data, for chatID: UUID) {
        chatSnapshots[chatID] = data
        persistSnapshots()
    }

    @available(iOS 19.0, macOS 26.0, *)
    func loadSnapshot(for chatID: UUID) -> GraphSnapshot? {
        guard let data = chatSnapshots[chatID] else { return nil }
        guard let decoded = try? JSONDecoder().decode(GraphSnapshot.self, from: data) else {
            return nil
        }
        guard decoded.schemaVersion == GraphSnapshot.currentSchemaVersion else {
            return nil
        }
        return decoded
    }

    private func persistSnapshots() {
        if let data = try? JSONEncoder().encode(chatSnapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
    }

    private func loadSnapshots() {
        if let data = UserDefaults.standard.data(forKey: snapshotsKey),
           let decoded = try? JSONDecoder().decode([UUID: Data].self, from: data) {
            chatSnapshots = decoded
        }
    }

    func saveLastSelectedChat(_ chatId: UUID?) {
        if let chatId {
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
        return chats.first { $0.id == uuid }
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

        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            chats[index].lastMessage = message.content
            chats[index].timestamp = message.timestamp

            if chats[index].title == "New Conversation" && message.isUser {
                chats[index].title = generateTitle(from: message.content)
            }
        }

        saveChats()
    }

    func getMessages(for chatId: UUID) -> [Message] {
        chatMessages[chatId] ?? []
    }

    private func generateTitle(from message: String) -> String {
        let maxLength = 50
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.prefix(maxLength)) + "..."
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
        chats.removeAll { $0.id == chat.id }
        chatMessages.removeValue(forKey: chat.id)

        if let lastSelectedUUID = UserDefaults.standard.string(forKey: lastSelectedChatKey),
           let uuid = UUID(uuidString: lastSelectedUUID),
           uuid == chat.id {
            UserDefaults.standard.removeObject(forKey: lastSelectedChatKey)
        }

        chatSnapshots.removeValue(forKey: chat.id)
        persistSnapshots()

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
            ChatSidebarView(chatManager: chatManager, selectedChat: $selectedChat)
        } detail: {
            if let chat = selectedChat {
                if #available(iOS 19.0, macOS 26.0, *) {
                    ChatDetailView(chat: chat, chatManager: chatManager)
                        .id(chat.id)
                } else {
                    UnsupportedOSView()
                }
            } else {
                ChatEmptyStateView()
            }
        }
        .onAppear {
            if selectedChat == nil {
                selectedChat = chatManager.loadLastSelectedChat()
            }
        }
        .onChange(of: selectedChat) { _, newChat in
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
                if let selectedChat,
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
        let interval = Date().timeIntervalSince(date)
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
    @State private var modelAvailability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)
    @State private var conductor: Conductor

    private let model = SystemLanguageModel.default

    init(chat: Chat, chatManager: ChatManager) {
        self.chat = chat
        self.chatManager = chatManager

        var tools: [any AgentTool] = [
            WikipediaSearchTool(),
            PubMedSearchTool(),
            ArXivSearchTool(),
            SemanticScholarSearchTool(),
            OpenAlexSearchTool(),
            CrossRefSearchTool(),
            WebReaderTool(),
        ]
        #if os(macOS)
        tools.append(BuildAutomatorWorkflowTool(index: AutomatorActionIndex()))
        #endif

        let snapshot = chatManager.loadSnapshot(for: chat.id)
        self._conductor = State(initialValue: Conductor(tools: tools, snapshot: snapshot))
    }

    var body: some View {
        VStack(spacing: 0) {
            if modelAvailability != .available {
                modelStatusBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if isResponding {
                            ActionGroupView(actions: conductor.proxy.actions)
                                .id("active-actions")
                                .transition(.opacity)
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
                .onChange(of: conductor.proxy.actions.count) { _, _ in
                    if isResponding {
                        withAnimation {
                            proxy.scrollTo("active-actions", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

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
                        Task { await sendMessage() }
                    }

                Button {
                    Task { await sendMessage() }
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

        let userMessage = Message(content: userMessageContent, isUser: true, timestamp: Date())
        messages.append(userMessage)
        chatManager.addMessage(userMessage, to: chat.id)

        isResponding = true

        do {
            let result = try await conductor.handle(message: userMessageContent)
            let assistantMessage = Message(
                content: result.text,
                isUser: false,
                timestamp: Date(),
                sources: result.sources
            )
            messages.append(assistantMessage)
            chatManager.addMessage(assistantMessage, to: chat.id)
            let snap = await conductor.snapshot()
            chatManager.saveSnapshot(snap, for: chat.id)
        } catch {
            let errorMessage = Message(
                content: "Something went wrong: \(error.localizedDescription)",
                isUser: false,
                timestamp: Date()
            )
            messages.append(errorMessage)
            chatManager.addMessage(errorMessage, to: chat.id)
        }

        isResponding = false
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    @State private var showCopied = false

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.isUser {
                    Text(message.content)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(16)
                } else {
                    MarkdownTextView(content: message.content)
                        .padding(12)
                        #if os(macOS)
                        .background(Color(nsColor: .controlBackgroundColor))
                        #else
                        .background(Color(uiColor: .systemGray5))
                        #endif
                        .cornerRadius(16)
                }

                if !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(message.sources, id: \.self) { source in
                            Link(destination: URL(string: source.url)!) {
                                Label(source.title, systemImage: "link")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !message.isUser {
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            #else
                            UIPasteboard.general.string = message.content
                            #endif
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopied = false
                            }
                        } label: {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy")
                    }
                }
            }

            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    markdownText(text)
                        .font(headingFont(level))
                        .fontWeight(.semibold)
                case .paragraph(let text):
                    markdownText(text)
                }
            }
        }
    }

    private func markdownText(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var currentLines: [String] = []

        func flushParagraph() {
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result.append(.paragraph(text))
            }
            currentLines.removeAll()
        }

        for line in content.components(separatedBy: "\n") {
            if let heading = parseHeading(line) {
                flushParagraph()
                result.append(heading)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty && !currentLines.isEmpty {
                flushParagraph()
            } else {
                currentLines.append(line)
            }
        }
        flushParagraph()
        return result
    }

    private func parseHeading(_ line: String) -> Block? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6,
              trimmed.count > level,
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        let text = String(trimmed.dropFirst(level + 1))
        return .heading(level: level, text: text)
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
