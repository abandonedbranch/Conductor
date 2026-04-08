# Three-Tool Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace direct tool access with a three-tool gateway (`action`, `library`, `manual`) that prevents hallucination and reduces context window pressure.

**Architecture:** A `CapabilityRegistry` service holds metadata and execute closures for all capabilities (search backends, Automator). Three gateway tools (`ActionTool`, `LibraryTool`, `ManualTool`) query the registry on behalf of the model. The model session only ever sees these three tools.

**Tech Stack:** Swift 6, FoundationModels framework, SwiftUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-04-08-three-tool-gateway-design.md`

---

### Task 1: CapabilityRegistry — Types and Scoring

**Files:**
- Create: `Conductor/Services/CapabilityRegistry.swift`
- Create: `ConductorTests/CapabilityRegistryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("CapabilityRegistry Tests", .serialized)
struct CapabilityRegistryTests {

    private func makeCapability(
        id: String,
        name: String,
        keywords: [String] = [],
        description: String = ""
    ) -> Capability {
        Capability(
            id: id,
            name: name,
            description: description,
            keywords: keywords,
            execute: { _ in "executed \(id)" }
        )
    }

    @Test("Returns empty results for query with no matches")
    func zeroMatches() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Build Workflow", keywords: ["automator"]))
        let results = await registry.search(query: "spreadsheet", maxResults: 5)
        #expect(results.isEmpty)
    }

    @Test("Returns single match when query hits one capability")
    func singleMatch() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Build Workflow", keywords: ["automator", "workflow"]))
        await registry.register(makeCapability(id: "b", name: "Search PubMed", keywords: ["biomedical", "clinical"]))
        let results = await registry.search(query: "workflow", maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].capability.id == "a")
    }

    @Test("Returns multiple matches sorted by score")
    func multipleMatchesSorted() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(
            id: "a",
            name: "Build Workflow",
            keywords: ["automator", "workflow", "automate"],
            description: "Build macOS Automator workflows"
        ))
        await registry.register(makeCapability(
            id: "b",
            name: "Run Shortcut",
            keywords: ["shortcut", "automate"],
            description: "Run a Shortcuts workflow"
        ))
        // "automate" matches both; "workflow" matches both (name for a, description for b)
        // "a" should score higher: name match (3) + keyword (2) vs keyword (2) + description (1)
        let results = await registry.search(query: "automate workflow", maxResults: 5)
        #expect(results.count == 2)
        #expect(results[0].capability.id == "a")
        #expect(results[0].score > results[1].score)
    }

    @Test("Name matches score higher than keyword matches")
    func nameScoresHigherThanKeyword() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Search Images", keywords: ["photo"]))
        await registry.register(makeCapability(id: "b", name: "Edit Photo", keywords: ["images"]))
        let results = await registry.search(query: "images", maxResults: 5)
        #expect(results[0].capability.id == "a") // name match = 3 pts
    }

    @Test("Search is case insensitive")
    func caseInsensitive() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Build Workflow", keywords: ["AUTOMATOR"]))
        let results = await registry.search(query: "automator", maxResults: 5)
        #expect(results.count == 1)
    }

    @Test("Respects maxResults limit")
    func respectsMaxResults() async {
        let registry = CapabilityRegistry()
        for i in 1...10 {
            await registry.register(makeCapability(id: "\(i)", name: "Tool \(i)", keywords: ["common"]))
        }
        let results = await registry.search(query: "common", maxResults: 3)
        #expect(results.count == 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/CapabilityRegistryTests 2>&1 | tail -20`
Expected: Compilation failure — `CapabilityRegistry`, `Capability`, `ScoredCapability` not defined.

- [ ] **Step 3: Implement CapabilityRegistry**

```swift
import Foundation

struct CapabilityRequest: Sendable {
    let userMessage: String
    let extractedGoal: String
    let parameters: [String: String]?
}

struct Capability: Sendable {
    let id: String
    let name: String
    let description: String
    let keywords: [String]
    let execute: @Sendable (CapabilityRequest) async -> String
}

struct ScoredCapability: Sendable {
    let capability: Capability
    let score: Int
}

actor CapabilityRegistry {
    private var capabilities: [Capability]

    init(capabilities: [Capability] = []) {
        self.capabilities = capabilities
    }

    func register(_ capability: Capability) {
        capabilities.append(capability)
    }

    func search(query: String, maxResults: Int) -> [ScoredCapability] {
        let queryLower = query.lowercased()
        guard !queryLower.isEmpty else {
            return []
        }

        let terms = queryLower.split(separator: " ").map(String.init)
        var scored: [ScoredCapability] = []

        for capability in capabilities {
            var score = 0
            let nameLower = capability.name.lowercased()
            let descLower = capability.description.lowercased()
            let kwLower = capability.keywords.map { $0.lowercased() }

            for term in terms {
                if nameLower.contains(term) { score += 3 }
                if kwLower.contains(where: { $0.contains(term) }) { score += 2 }
                if descLower.contains(term) { score += 1 }
            }

            if score > 0 {
                scored.append(ScoredCapability(capability: capability, score: score))
            }
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(maxResults))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/CapabilityRegistryTests 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/CapabilityRegistry.swift ConductorTests/CapabilityRegistryTests.swift
git commit -m "(registry): add CapabilityRegistry with fuzzy keyword scoring"
```

---

### Task 2: ManualTool — Static Documentation Lookup

**Files:**
- Create: `Conductor/Tools/ManualTool.swift`
- Create: `ConductorTests/ManualToolTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ManualTool Tests")
struct ManualToolTests {

    @Test("Returns index when no page specified")
    func returnsIndex() {
        let index = ManualPage.index
        for page in ManualPage.allCases {
            #expect(index.contains(page.rawValue))
            #expect(index.contains(page.summary))
        }
    }

    @Test("Returns page content for known page")
    func returnsPageContent() {
        let content = ManualPage.search.content
        #expect(!content.isEmpty)
        #expect(content.contains("search") || content.contains("Search"))
    }

    @Test("Each page has a non-empty summary")
    func allPagesHaveSummaries() {
        for page in ManualPage.allCases {
            #expect(!page.summary.isEmpty, "Page \(page.rawValue) has empty summary")
        }
    }

    @Test("Each page has non-empty content")
    func allPagesHaveContent() {
        for page in ManualPage.allCases {
            #expect(!page.content.isEmpty, "Page \(page.rawValue) has empty content")
        }
    }

    @Test("Index lists all available pages")
    func indexListsAllPages() {
        let index = ManualPage.index
        for page in ManualPage.allCases {
            #expect(index.contains(page.rawValue))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/ManualToolTests 2>&1 | tail -20`
Expected: Compilation failure — `ManualPage` not defined.

- [ ] **Step 3: Implement ManualPage and ManualTool**

```swift
import Foundation
import FoundationModels

// MARK: - Manual Pages

enum ManualPage: String, CaseIterable {
    case overview
    case search
    case automator

    var summary: String {
        switch self {
        case .overview:  return "What Conductor is and how it works"
        case .search:    return "Search across scientific and general knowledge sources"
        case .automator: return "Build macOS Automator workflows from natural language"
        }
    }

    var content: String {
        switch self {
        case .overview:
            return """
            Conductor is an on-device assistant that orchestrates system capabilities. \
            It interprets user intent and coordinates tools to fulfill requests. \
            All processing happens locally. Network access occurs only through \
            explicit search tools and is always transparent to the user.
            """
        case .search:
            return """
            Conductor can search multiple knowledge sources: \
            PubMed (biomedical/clinical), arXiv (physics, math, CS), \
            Semantic Scholar (cross-disciplinary academic), OpenAlex (bibliometrics), \
            CrossRef (DOI/citation metadata), and Wikipedia (general knowledge). \
            The appropriate source is selected automatically based on the query domain.
            """
        case .automator:
            return """
            On macOS, Conductor can build Automator workflow files from natural language descriptions. \
            It searches the system's installed Automator actions, plans a multi-step workflow, \
            and assembles a .workflow file. The user must explicitly request workflow creation.
            """
        }
    }

    static var index: String {
        allCases.map { "- \($0.rawValue): \($0.summary)" }.joined(separator: "\n")
    }
}

// MARK: - ManualTool

@available(iOS 19.0, macOS 26.0, *)
struct ManualTool: Tool {
    let name = "manual"
    let description = "Look up documentation about Conductor. Call with a page name for details, or without arguments for an index of available pages."

    @Generable
    struct Arguments {
        @Guide(description: "The manual page to look up. Omit for the index.")
        var page: String?
    }

    func call(arguments: Arguments) async -> String {
        guard let pageName = arguments.page else {
            return ManualPage.index
        }
        guard let page = ManualPage(rawValue: pageName.lowercased()) else {
            return "No manual page named \"\(pageName)\". Available pages:\n\(ManualPage.index)"
        }
        return page.content
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/ManualToolTests 2>&1 | tail -20`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/ManualTool.swift ConductorTests/ManualToolTests.swift
git commit -m "(tools): add ManualTool with static documentation pages"
```

---

### Task 3: ActionTool — Intent Resolution and Capability Dispatch

**Files:**
- Create: `Conductor/Tools/ActionTool.swift`
- Create: `ConductorTests/ActionToolTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ActionTool Tests", .serialized)
struct ActionToolTests {

    private func makeRegistry(_ capabilities: [Capability]) async -> CapabilityRegistry {
        let registry = CapabilityRegistry()
        for cap in capabilities {
            await registry.register(cap)
        }
        return registry
    }

    @Test("Returns no-match message when no capabilities match")
    func zeroMatches() async {
        let registry = await makeRegistry([
            Capability(id: "a", name: "Build Workflow", description: "", keywords: ["automator"]) { _ in "built" }
        ])
        let result = await ActionTool.resolve(userMessage: "play some music", registry: registry)
        switch result {
        case .noMatch(let message):
            #expect(message.contains("No program"))
        default:
            Issue.record("Expected noMatch, got \(result)")
        }
    }

    @Test("Executes single matching capability")
    func singleMatch() async {
        let registry = await makeRegistry([
            Capability(id: "a", name: "Build Workflow", description: "", keywords: ["automator", "workflow"]) { request in
                "built: \(request.extractedGoal)"
            }
        ])
        let result = await ActionTool.resolve(userMessage: "build an automator workflow to rename files", registry: registry)
        switch result {
        case .executed(let output):
            #expect(output.contains("built"))
        default:
            Issue.record("Expected executed, got \(result)")
        }
    }

    @Test("Returns vague intent when multiple capabilities match")
    func multipleMatches() async {
        let registry = await makeRegistry([
            Capability(id: "a", name: "Automate Files", description: "", keywords: ["automate", "files"]) { _ in "a" },
            Capability(id: "b", name: "Automate Photos", description: "", keywords: ["automate", "photos"]) { _ in "b" },
        ])
        let result = await ActionTool.resolve(userMessage: "automate something", registry: registry)
        switch result {
        case .vagueIntent(let count):
            #expect(count == 2)
        default:
            Issue.record("Expected vagueIntent, got \(result)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/ActionToolTests 2>&1 | tail -20`
Expected: Compilation failure — `ActionTool` not defined.

- [ ] **Step 3: Implement ActionTool**

```swift
import Foundation
import FoundationModels

// MARK: - Errors

struct VagueIntentError: Error {
    let matchCount: Int
}

// MARK: - Resolution Result (for testing)

enum ActionResult: Sendable {
    case executed(String)
    case noMatch(String)
    case vagueIntent(Int)
}

// MARK: - ActionTool

@available(iOS 19.0, macOS 26.0, *)
struct ActionTool: Tool {
    let name = "action"
    let description = "Execute a device capability. Call when the user wants to do something — build, create, convert, run."
    let registry: CapabilityRegistry
    let tracker: ToolUsageTracker

    @Generable
    struct Arguments {
        @Guide(description: "The user's message describing what they want to do")
        var userMessage: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = await Self.resolve(userMessage: arguments.userMessage, registry: registry)
        switch result {
        case .executed(let output):
            return output
        case .noMatch(let message):
            return message
        case .vagueIntent(let count):
            throw VagueIntentError(matchCount: count)
        }
    }

    static func resolve(userMessage: String, registry: CapabilityRegistry) async -> ActionResult {
        let matches = await registry.search(query: userMessage, maxResults: 5)

        guard !matches.isEmpty else {
            return .noMatch("No program exists to fulfill this request.")
        }

        if matches.count > 1 {
            // Check if the top match is clearly dominant (2x the second score)
            if matches[0].score >= matches[1].score * 2 {
                let request = CapabilityRequest(
                    userMessage: userMessage,
                    extractedGoal: userMessage,
                    parameters: nil
                )
                let output = await matches[0].capability.execute(request)
                return .executed(output)
            }
            return .vagueIntent(matches.count)
        }

        let request = CapabilityRequest(
            userMessage: userMessage,
            extractedGoal: userMessage,
            parameters: nil
        )
        let output = await matches[0].capability.execute(request)
        return .executed(output)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/ActionToolTests 2>&1 | tail -20`
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/ActionTool.swift ConductorTests/ActionToolTests.swift
git commit -m "(tools): add ActionTool with capability resolution and VagueIntentError"
```

---

### Task 4: LibraryTool — Unified Search Router

**Files:**
- Create: `Conductor/Tools/LibraryTool.swift`
- Create: `ConductorTests/LibraryToolTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("LibraryTool Tests", .serialized)
struct LibraryToolTests {

    private func makeRegistry() async -> CapabilityRegistry {
        let registry = CapabilityRegistry()
        await registry.register(Capability(
            id: "pubmed",
            name: "PubMed",
            description: "Biomedical and clinical research",
            keywords: ["biomedical", "clinical", "medical", "health", "life science"]
        ) { request in
            "PubMed results for: \(request.extractedGoal)"
        })
        await registry.register(Capability(
            id: "arxiv",
            name: "arXiv",
            description: "Physics, math, computer science preprints",
            keywords: ["physics", "math", "computer science", "preprint", "machine learning"]
        ) { request in
            "arXiv results for: \(request.extractedGoal)"
        })
        await registry.register(Capability(
            id: "wikipedia",
            name: "Wikipedia",
            description: "General knowledge and encyclopedic information",
            keywords: ["general", "history", "overview", "encyclopedia"]
        ) { request in
            "Wikipedia results for: \(request.extractedGoal)"
        })
        return registry
    }

    @Test("Routes to explicit domain when provided")
    func routesByDomain() async {
        let registry = await makeRegistry()
        let result = await LibraryTool.route(query: "CRISPR", domain: "biomedical", registry: registry)
        #expect(result.contains("PubMed"))
    }

    @Test("Auto-routes based on query keywords when no domain")
    func autoRoutesByQuery() async {
        let registry = await makeRegistry()
        let result = await LibraryTool.route(query: "clinical trial for immunotherapy", domain: nil, registry: registry)
        #expect(result.contains("PubMed"))
    }

    @Test("Falls back to first result when query is ambiguous")
    func fallbackOnAmbiguousQuery() async {
        let registry = await makeRegistry()
        let result = await LibraryTool.route(query: "interesting facts", domain: nil, registry: registry)
        // Should still return something, not fail
        #expect(!result.isEmpty)
    }

    @Test("Returns error message when domain matches nothing")
    func unknownDomain() async {
        let registry = await makeRegistry()
        let result = await LibraryTool.route(query: "test", domain: "astrology", registry: registry)
        #expect(result.contains("No search backend"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/LibraryToolTests 2>&1 | tail -20`
Expected: Compilation failure — `LibraryTool` not defined.

- [ ] **Step 3: Implement LibraryTool**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct LibraryTool: Tool {
    let name = "library"
    let description = "Search for information. Call when the user wants to know something — look up research, facts, or references."
    let registry: CapabilityRegistry
    let tracker: ToolUsageTracker

    @Generable
    struct Arguments {
        @Guide(description: "The search query")
        var query: String

        @Guide(description: "Optional knowledge domain to search, e.g. 'biomedical', 'physics', 'general'")
        var domain: String?
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(ToolBadge(icon: "books.vertical", tint: .blue, label: "Library"))
        return await Self.route(query: arguments.query, domain: arguments.domain, registry: registry)
    }

    static func route(query: String, domain: String?, registry: CapabilityRegistry) async -> String {
        let searchQuery: String
        if let domain {
            searchQuery = domain
        } else {
            searchQuery = query
        }

        let matches = await registry.search(query: searchQuery, maxResults: 1)

        guard let best = matches.first else {
            if domain != nil {
                return "No search backend matches domain \"\(domain!)\". Try without specifying a domain."
            }
            return "No search backend available for this query."
        }

        let request = CapabilityRequest(
            userMessage: query,
            extractedGoal: query,
            parameters: nil
        )
        return await best.capability.execute(request)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/LibraryToolTests 2>&1 | tail -20`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/LibraryTool.swift ConductorTests/LibraryToolTests.swift
git commit -m "(tools): add LibraryTool with domain routing and auto-selection"
```

---

### Task 5: Register Capabilities and Wire Up Session

**Files:**
- Modify: `Conductor/ContentView.swift:386-419` (session initialization)
- Modify: `Conductor/ContentView.swift:348-384` (system prompt)

- [ ] **Step 1: Add capability factory methods**

Add static methods on `ChatDetailView` that return `[Capability]` synchronously. Add these inside the `ChatDetailView` struct, after the existing `automatorIndex` property (around line 345).

```swift
private static func searchCapabilities(tracker: ToolUsageTracker) -> [Capability] {
    let searchTools: [(id: String, name: String, keywords: [String], description: String, tool: any BadgedTool)] = [
        ("search.pubmed", "PubMed", ["biomedical", "clinical", "medical", "health", "life science", "pubmed"], "Biomedical and clinical research papers", PubMedSearchTool(tracker: tracker)),
        ("search.wikipedia", "Wikipedia", ["general", "knowledge", "history", "overview", "encyclopedia", "wikipedia"], "General knowledge and encyclopedic information", WikipediaSearchTool(tracker: tracker)),
        ("search.arxiv", "arXiv", ["physics", "math", "computer science", "preprint", "machine learning", "arxiv"], "Cutting-edge preprints in physics, math, and CS", ArXivSearchTool(tracker: tracker)),
        ("search.semantic", "Semantic Scholar", ["academic", "scholarly", "citation", "cross-disciplinary", "semantic scholar"], "Cross-disciplinary academic research", SemanticScholarSearchTool(tracker: tracker)),
        ("search.openalex", "OpenAlex", ["bibliometric", "citation data", "scholarly works", "openalex"], "Scholarly works with citation and bibliometric data", OpenAlexSearchTool(tracker: tracker)),
        ("search.crossref", "CrossRef", ["doi", "publisher", "citation count", "crossref", "metadata"], "DOI metadata, publisher info, and citation counts", CrossRefSearchTool(tracker: tracker)),
    ]

    return searchTools.map { entry in
        let tool = entry.tool
        return Capability(
            id: entry.id,
            name: entry.name,
            description: entry.description,
            keywords: entry.keywords
        ) { request in
            await SearchCapabilityAdapter.execute(tool: tool, query: request.extractedGoal, tracker: tracker)
        }
    }
}

#if os(macOS)
private static func automatorCapability(tracker: ToolUsageTracker) -> Capability {
    Capability(
        id: "automator.build",
        name: "Build Automator Workflow",
        description: "Build a macOS Automator .workflow file from a description",
        keywords: ["automator", "workflow", "automate", "macro", "build workflow"]
    ) { request in
        let tool = BuildAutomatorWorkflowTool(tracker: tracker, index: Self.automatorIndex)
        let args = BuildAutomatorWorkflowTool.Arguments(workflowDescription: request.extractedGoal)
        return await tool.call(arguments: args)
    }
}
#endif
```

Note: `SearchCapabilityAdapter` is needed because each search tool has its own `Arguments` type. This is a lightweight adapter — see step 3.

- [ ] **Step 2: Add SearchCapabilityAdapter**

Add to `Conductor/Tools/ToolSupport.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
enum SearchCapabilityAdapter {
    static func execute(tool: any BadgedTool, query: String, tracker: ToolUsageTracker) async -> String {
        // Each search tool's call() takes tool-specific Arguments, but they all
        // accept a search query string. We call through the concrete types.
        switch tool {
        case let t as PubMedSearchTool:
            return await t.call(arguments: .init(searchQuery: query))
        case let t as WikipediaSearchTool:
            return (try? await t.call(arguments: .init(searchQuery: query))) ?? "Wikipedia search failed."
        case let t as ArXivSearchTool:
            return await t.call(arguments: .init(searchQuery: query))
        case let t as SemanticScholarSearchTool:
            return await t.call(arguments: .init(searchQuery: query))
        case let t as OpenAlexSearchTool:
            return await t.call(arguments: .init(searchQuery: query))
        case let t as CrossRefSearchTool:
            return await t.call(arguments: .init(searchQuery: query))
        default:
            return "Unknown search tool."
        }
    }
}
```

- [ ] **Step 3: Replace system prompt**

Replace the `instructions` static property in `ChatDetailView` (lines 348-384) with:

```swift
private static let instructions = """
You are The Conductor. You orchestrate device capabilities to fulfill user intent.
Use action to do. Use library to know. Use manual to explain yourself.
Respond tersely. One sentence when one sentence suffices.
If a tool errors, explain in one sentence. Do not apologize.
Never fabricate information. If you lack data, say so.
"""
```

- [ ] **Step 4: Replace session initialization**

Replace the `init(chat:chatManager:)` method (lines 386-419). Since `buildRegistry` is async (it registers on an actor), use a `Task` in `.task {}` or initialize the registry eagerly with a known set. The simplest approach: make `CapabilityRegistry` accept registrations in its init synchronously, then wrap with actor isolation after construction.

Alternatively, keep the init synchronous by making `CapabilityRegistry.register` nonisolated by collecting capabilities in the initializer:

```swift
init(chat: Chat, chatManager: ChatManager) {
    self.chat = chat
    self.chatManager = chatManager

    let tracker = ToolUsageTracker()

    // Build capabilities array synchronously
    var capabilities = Self.searchCapabilities(tracker: tracker)
    #if os(macOS)
    capabilities.append(Self.automatorCapability(tracker: tracker))
    #endif

    let registry = CapabilityRegistry(capabilities: capabilities)

    let tools: [any Tool] = [
        ActionTool(registry: registry, tracker: tracker),
        LibraryTool(registry: registry, tracker: tracker),
        ManualTool(),
    ]

    self.toolTracker = tracker
    self.tools = tools
    self._session = State(initialValue: LanguageModelSession(
        tools: tools,
        instructions: Self.instructions
    ))
}
```

This requires adding an `init(capabilities:)` to `CapabilityRegistry`:

```swift
actor CapabilityRegistry {
    private var capabilities: [Capability]

    init(capabilities: [Capability] = []) {
        self.capabilities = capabilities
    }

    func register(_ capability: Capability) {
        capabilities.append(capability)
    }
    // ... search unchanged
}
```

The `searchCapabilities` and `automatorCapability` factory methods are defined in Step 1 above.
```

- [ ] **Step 5: Remove Automator-specific system prompt addendum**

Delete the `#if os(macOS)` block that appended Automator instructions to the system prompt (lines 400-411 in the original). This is no longer needed — Automator is a registered capability, not a prompt concern.

- [ ] **Step 6: Update the refusal loop retry prompt**

In `sendMessage()` (around line 584), update the retry text from:

```swift
"(If you cannot answer from memory, use one of your search tools to look it up. Do not apologize — search or explain what you would need to answer.)"
```

to:

```swift
"(Use library to search. Use manual to describe capabilities. Do not apologize.)"
```

- [ ] **Step 7: Build to verify compilation**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Build succeeds.

- [ ] **Step 8: Run full test suite**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add Conductor/ContentView.swift Conductor/Tools/ToolSupport.swift
git commit -m "(session): wire three-tool gateway and terse system prompt"
```

---

### Task 6: Verify End-to-End Behavior

This task is manual verification on a real device/simulator with the on-device model.

- [ ] **Step 1: Test manual tool — capability question**

Launch the app. Send: "What can you do?"
Expected: Model calls `manual` (no page), receives the index, synthesizes a terse answer.
Verify: No hallucinated capabilities. Response references only documented pages.

- [ ] **Step 2: Test manual tool — specific page**

Send: "Tell me about your Automator capabilities"
Expected: Model calls `manual` with page `"automator"`, receives the static content.
Verify: No workflow is built. No `action` call. Just documentation.

- [ ] **Step 3: Test action tool — single match**

Send: "Build me an Automator workflow that renames files"
Expected: Model calls `action`, which matches `automator.build`, executes the Automator builder.
Verify: Workflow preview appears in the UI.

- [ ] **Step 4: Test library tool — auto-routing**

Send: "What are the latest papers on CRISPR?"
Expected: Model calls `library`, which auto-routes to PubMed based on keyword scoring.
Verify: PubMed results appear with source links.

- [ ] **Step 5: Test action tool — no match**

Send: "Order me a pizza"
Expected: Model calls `action`, gets "No program exists to fulfill this request."
Verify: Model relays this to the user without hallucinating a capability.

- [ ] **Step 6: Test context window pressure**

Have a 10+ message conversation mixing search queries and capability questions.
Expected: Conversation lasts longer before hitting compaction than with the old 7-tool setup.

- [ ] **Step 7: Commit verification notes**

```bash
git commit --allow-empty -m "(verify): manual end-to-end testing complete"
```
