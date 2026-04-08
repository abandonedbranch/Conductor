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
    var toolsUsed: [ToolBadge]
    var sources: [ToolSource]
    var workflowPreview: WorkflowPreview?

    enum CodingKeys: String, CodingKey {
        case id, content, isUser, timestamp, toolsUsed, sources, workflowPreview
    }

    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date, toolsUsed: [ToolBadge] = [], sources: [ToolSource] = [], workflowPreview: WorkflowPreview? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.toolsUsed = toolsUsed
        self.sources = sources
        self.workflowPreview = workflowPreview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        isUser = try container.decode(Bool.self, forKey: .isUser)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        toolsUsed = try container.decodeIfPresent([ToolBadge].self, forKey: .toolsUsed) ?? []
        sources = try container.decodeIfPresent([ToolSource].self, forKey: .sources) ?? []
        workflowPreview = try container.decodeIfPresent(WorkflowPreview.self, forKey: .workflowPreview)
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
    @State private var session: LanguageModelSession

    private let model = SystemLanguageModel.default
    private let tools: [any Tool]
    private let toolTracker: ToolUsageTracker

    private static let instructions = """
You are The Conductor — an intelligent intermediary that interprets human intent \
and coordinates device capabilities to fulfill that intent.

Your role is orchestration, not assistance. When given a request:
- Infer the underlying goal, not just the surface request
- Identify what system capabilities are needed to achieve it
- Coordinate actions across multiple functions when necessary
- Explain your reasoning and what you're doing — transparency is non-negotiable

IMPORTANT RULES:
- When you do not know something, ALWAYS use one of your available search tools to \
  look it up. Do not guess. Do not apologize. Search first.
- If the user asks a factual question, use a tool before responding.
- Use the most relevant tool for the domain. Combine multiple tools when appropriate.
- Always synthesize results into a coherent answer rather than dumping raw data.
- If a search fails, tell the user exactly what you searched for and that no results \
  were found. Suggest a different search term.
- Never say "I am unable to provide information." Instead, explain specifically what \
  you tried and why it did not work.
- When the user asks for research, medical literature, academic papers, or scientific \
  information, you MUST call the appropriate research tool. Do not fabricate results.

Core principles:
- Clarity over cleverness: Use direct language. No marketing speak.
- Systems thinking: Consider workflow and coordination, not just single actions.
- Minimal friction: Extend the user's thinking; don't make them operate a tool.
- Technical honesty: Acknowledge your limits specifically — never give vague refusals.
- Privacy: You process locally. The search tools access the internet to \
  retrieve information — be transparent when using them.

When you act, be explicit about what you're doing and why. The user should always \
understand your decision-making process.

You sit between what users want to accomplish and what their device can do. \
The user specifies the outcome; you determine the path.
"""

    init(chat: Chat, chatManager: ChatManager) {
        self.chat = chat
        self.chatManager = chatManager

        let tracker = ToolUsageTracker()
        let tools: [any Tool] = [
            WikipediaSearchTool(tracker: tracker),
            PubMedSearchTool(tracker: tracker),
            SemanticScholarSearchTool(tracker: tracker),
            ArXivSearchTool(tracker: tracker),
            OpenAlexSearchTool(tracker: tracker),
            CrossRefSearchTool(tracker: tracker),
        ]
        self.toolTracker = tracker
        self.tools = tools
        self._session = State(initialValue: LanguageModelSession(
            tools: tools,
            instructions: Self.instructions
        ))
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
                            MessageBubbleView(message: message) {
                                Task { await regenerate(message) }
                            }
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
        await toolTracker.reset()

        do {
            try await streamResponse(to: userMessageContent)

            // Detect refusal loops — if the model repeated itself, compact and retry
            if isRepeatedResponse() {
                // Remove the repeated response we just appended
                if let last = messages.last, !last.isUser {
                    messages.removeLast()
                }
                compactSession()
                streamingContent = ""
                await toolTracker.reset()
                try await streamResponse(
                    to: "\(userMessageContent)\n\n(If you cannot answer from memory, use one of your search tools to look it up. Do not apologize — search or explain what you would need to answer.)"
                )
            }
        } catch {
            let isGenerationError = String(describing: error).contains("GenerationError")

            if isGenerationError {
                // Context exhausted — compact the transcript and retry
                compactSession()
                streamingContent = ""
                await toolTracker.reset()

                do {
                    try await streamResponse(to: userMessageContent)
                } catch {
                    let errorMessage = Message(
                        content: "The conversation is too long even after compacting. Try starting a new chat.",
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    chatManager.addMessage(errorMessage, to: chat.id)
                }
            } else {
                let errorMessage = Message(
                    content: "Something went wrong: \(error.localizedDescription)",
                    isUser: false,
                    timestamp: Date()
                )
                messages.append(errorMessage)
                chatManager.addMessage(errorMessage, to: chat.id)
            }
        }

        isResponding = false
        streamingContent = ""
    }

    private func streamResponse(to prompt: String) async throws {
        let stream = session.streamResponse(to: prompt)

        for try await partial in stream {
            streamingContent = partial.content
        }

        if !streamingContent.isEmpty {
            let usedTools = await toolTracker.badgeSnapshot()
            let usedSources = await toolTracker.sourceSnapshot()
            let workflow = await toolTracker.workflowPreviewSnapshot()
            let assistantMessage = Message(
                content: streamingContent,
                isUser: false,
                timestamp: Date(),
                toolsUsed: usedTools,
                sources: usedSources,
                workflowPreview: workflow
            )
            messages.append(assistantMessage)
            chatManager.addMessage(assistantMessage, to: chat.id)
        }
    }

    private func regenerate(_ assistantMessage: Message) async {
        // Find the user message that preceded this response
        guard let index = messages.firstIndex(where: { $0.id == assistantMessage.id }),
              index > 0,
              messages[index - 1].isUser else { return }
        guard !isResponding else { return }

        let userPrompt = messages[index - 1].content

        // Remove the old assistant message
        messages.remove(at: index)

        isResponding = true
        streamingContent = ""
        await toolTracker.reset()

        // Compact to drop the old response from the transcript
        compactSession()

        do {
            try await streamResponse(to: userPrompt)
        } catch {
            let errorMessage = Message(
                content: "Regeneration failed: \(error.localizedDescription)",
                isUser: false,
                timestamp: Date()
            )
            messages.append(errorMessage)
            chatManager.addMessage(errorMessage, to: chat.id)
        }

        isResponding = false
        streamingContent = ""
    }

    private func isRepeatedResponse() -> Bool {
        let assistantMessages = messages.filter { !$0.isUser }
        guard assistantMessages.count >= 2 else { return false }
        let last = assistantMessages[assistantMessages.count - 1].content
        let prev = assistantMessages[assistantMessages.count - 2].content
        return last == prev
    }

    private func compactSession() {
        let transcript = session.transcript
        // Keep the first entry (establishes context) and the last few exchanges
        let allEntries = Array(transcript)
        let keepCount = min(4, allEntries.count)
        let entriesToKeep: [Transcript.Entry]
        if allEntries.count <= keepCount {
            entriesToKeep = allEntries
        } else {
            entriesToKeep = [allEntries[0]] + allEntries.suffix(keepCount - 1)
        }

        let compactedTranscript = Transcript(entries: entriesToKeep)
        let newSession = LanguageModelSession(tools: tools, transcript: compactedTranscript)
        newSession.prewarm()
        session = newSession
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    var onRegenerate: (() -> Void)?
    @State private var showCopied = false
    @State private var savedPath: String?

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

                #if os(macOS)
                if let preview = message.workflowPreview {
                    WorkflowCardView(preview: preview, savedPath: $savedPath, onRegenerate: onRegenerate)
                }
                #endif

                HStack(spacing: 6) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(message.toolsUsed, id: \.self) { badge in
                        Image(systemName: badge.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(badge.tint.color)
                            .clipShape(Circle())
                            .help(badge.label)
                    }

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

                        if let onRegenerate {
                            Button(action: onRegenerate) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Regenerate")
                        }
                    }
                }
            }

            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

#if os(macOS)
struct WorkflowCardView: View {
    let preview: WorkflowPreview
    @Binding var savedPath: String?
    var onRegenerate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(preview.title, systemImage: "gearshape.2")
                .font(.headline)

            ForEach(Array(preview.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.actionName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if !step.parameterSummary.isEmpty {
                            Text(step.parameterSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if index < preview.steps.count - 1 {
                    HStack(spacing: 4) {
                        Spacer().frame(width: 20)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(step.outputType)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            HStack {
                if let savedPath {
                    Label("Saved to \(savedPath)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    let fileExists = FileManager.default.fileExists(atPath: preview.tempFileURL.path)
                    Button {
                        saveWorkflow(from: preview.tempFileURL, suggestedName: preview.title)
                    } label: {
                        Label("Save .workflow", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .disabled(!fileExists)

                    if let onRegenerate {
                        Button(action: onRegenerate) {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func saveWorkflow(from tempURL: URL, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "workflow")!]
        panel.nameFieldStringValue = "\(suggestedName).workflow"
        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: tempURL, to: destURL)
                savedPath = destURL.path
            } catch {
                // File copy failed — the panel already shows errors for permission issues
            }
        }
    }
}
#endif

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
