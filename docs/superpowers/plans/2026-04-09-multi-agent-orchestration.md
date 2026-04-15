# Multi-Agent Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Conductor's single-session tool gateway with a multi-agent orchestration system where the Conductor decomposes user intent into a task graph, dispatches purpose-driven sub-agents with focused tool sets, and deterministically stitches results.

**Architecture:** The LLM is a thin translation layer (intent extraction + sub-agent tool argument translation). Everything else is deterministic: intent → task graph → dispatch → tool calls → stitch. The task graph is the unified plan, shared context, and completion tracker. Sub-agents get at most 2 tools each.

**Tech Stack:** Swift 6, SwiftUI, FoundationModels (`LanguageModelSession`, `@Generable`, `Tool` protocol), Swift Testing

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Conductor/Models/AgentPurpose.swift` | Purpose enum + display metadata (colors, headings, narration prefixes) |
| `Conductor/Models/LogEntry.swift` | `@Generable` structured entry for graph nodes |
| `Conductor/Models/ExtractedIntent.swift` | `@Generable` type the LLM produces from user input |
| `Conductor/Models/StitchedResponse.swift` | Deterministic assembly of graph results |
| `Conductor/Models/NarrationEvent.swift` | Event type published by TaskGraph for UI |
| `Conductor/Services/TaskGraph.swift` | Actor — unified plan + shared context + completion tracker |
| `Conductor/Services/SubAgent.swift` | Actor — lightweight worker with `LanguageModelSession` + tools |
| `Conductor/Services/ConductorOrchestrator.swift` | `@Observable` — intent extraction, graph construction, dispatch, stitch |
| `Conductor/Tools/AgentTool.swift` | Protocol extending `Tool` with `purpose` and `friendlyName` |
| `Conductor/Views/NarrationGroupView.swift` | Purpose-grouped status cells in chat |
| `Conductor/Views/TaskGraphSheet.swift` | Sheet overlay for info drilldown |
| `ConductorTests/AgentPurposeTests.swift` | Tests for purpose enum |
| `ConductorTests/TaskGraphTests.swift` | Tests for graph operations |
| ~~`ConductorTests/SubAgentTests.swift`~~ | SubAgent requires a live LanguageModelSession — tested indirectly via integration. Removed from plan. |
| `ConductorTests/ConductorOrchestratorTests.swift` | Tests for graph construction and dispatch |
| `ConductorTests/StitchedResponseTests.swift` | Tests for deterministic stitching |

### Modified Files
| File | Change |
|------|--------|
| `Conductor/Tools/WikipediaSearchTool.swift` | Conform to `AgentTool`, add `purpose: .overview`, `friendlyName` |
| `Conductor/Tools/PubMedSearchTool.swift` | Conform to `AgentTool`, add `purpose: .research`, `friendlyName` |
| `Conductor/Tools/ArXivSearchTool.swift` | Conform to `AgentTool`, add `purpose: .research`, `friendlyName` |
| `Conductor/Tools/SemanticScholarSearchTool.swift` | Conform to `AgentTool`, add `purpose: .research`, `friendlyName` |
| `Conductor/Tools/OpenAlexSearchTool.swift` | Conform to `AgentTool`, add `purpose: .research`, `friendlyName` |
| `Conductor/Tools/CrossRefSearchTool.swift` | Conform to `AgentTool`, add `purpose: .research`, `friendlyName` |
| `Conductor/Tools/WebReaderTool.swift` | Conform to `AgentTool`, add `purpose: .web`, `friendlyName` |
| `Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift` | Conform to `AgentTool`, add `purpose: .build`, `friendlyName` |
| `Conductor/Tools/ToolSupport.swift` | Remove `BadgedTool`, `ToolBadge`, `BadgeTint`, `ToolUsageTracker`, `SearchCapabilityAdapter`. Keep `ToolSource`. |
| `Conductor/ContentView.swift` | Replace `ChatDetailView` session logic with `ConductorOrchestrator`. Update `Message` model. Add narration and info drilldown UI. Remove badge display. |
| `Conductor/Models/WebReaderState.swift` | No change |

### Removed Files
| File | Reason |
|------|--------|
| `Conductor/Services/CapabilityRegistry.swift` | Replaced by purpose-based tool grouping |
| `Conductor/Tools/ActionTool.swift` | Gateway replaced by Conductor dispatch |
| `Conductor/Tools/LibraryTool.swift` | Gateway replaced by Conductor dispatch |
| `Conductor/Tools/ManualTool.swift` | Capability questions answered by Conductor directly |
| `ConductorTests/ActionToolTests.swift` | Tests for removed type |
| `ConductorTests/LibraryToolTests.swift` | Tests for removed type |
| `ConductorTests/ManualToolTests.swift` | Tests for removed type |
| `ConductorTests/CapabilityRegistryTests.swift` | Tests for removed type |

---

## Task 1: AgentPurpose and AgentTool Protocol

**Files:**
- Create: `Conductor/Models/AgentPurpose.swift`
- Create: `Conductor/Tools/AgentTool.swift`
- Test: `ConductorTests/AgentPurposeTests.swift`

- [ ] **Step 1: Write the failing test for AgentPurpose**

Create `ConductorTests/AgentPurposeTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("AgentPurpose Tests")
struct AgentPurposeTests {

    @Test("Each purpose has a display color")
    func purposeHasColor() {
        for purpose in AgentPurpose.allCases {
            // Verify color is accessible without crashing
            _ = purpose.displayColor
        }
    }

    @Test("Each purpose has a section heading")
    func purposeHasSectionHeading() {
        #expect(AgentPurpose.overview.sectionHeading == "Overview")
        #expect(AgentPurpose.research.sectionHeading == "Research Findings")
        #expect(AgentPurpose.web.sectionHeading == "Web Content")
        #expect(AgentPurpose.build.sectionHeading == "Workflow")
    }

    @Test("Each purpose has an agent description")
    func purposeHasAgentDescription() {
        for purpose in AgentPurpose.allCases {
            #expect(!purpose.agentDescription.isEmpty)
        }
    }

    @Test("Each purpose has a narration prefix")
    func purposeHasNarrationPrefix() {
        for purpose in AgentPurpose.allCases {
            #expect(!purpose.narrationPrefix.isEmpty)
        }
    }

    @Test("Raw values are stable strings")
    func rawValues() {
        #expect(AgentPurpose.overview.rawValue == "overview")
        #expect(AgentPurpose.research.rawValue == "research")
        #expect(AgentPurpose.web.rawValue == "web")
        #expect(AgentPurpose.build.rawValue == "build")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/AgentPurposeTests 2>&1 | tail -20`
Expected: FAIL — `AgentPurpose` not found

- [ ] **Step 3: Implement AgentPurpose**

Create `Conductor/Models/AgentPurpose.swift`:

```swift
import SwiftUI

enum AgentPurpose: String, Codable, CaseIterable, Sendable {
    case overview
    case research
    case web
    case build

    var displayColor: Color {
        switch self {
        case .overview: return .orange
        case .research: return .blue
        case .web:      return .purple
        case .build:    return .gray
        }
    }

    var sectionHeading: String {
        switch self {
        case .overview: return "Overview"
        case .research: return "Research Findings"
        case .web:      return "Web Content"
        case .build:    return "Workflow"
        }
    }

    var agentDescription: String {
        switch self {
        case .overview: return "a research assistant gathering background context"
        case .research: return "a research assistant finding authoritative sources"
        case .web:      return "a web reader extracting page content"
        case .build:    return "a workflow builder creating automations"
        }
    }

    var narrationPrefix: String {
        switch self {
        case .overview: return "Looking up background information"
        case .research: return "Searching research databases"
        case .web:      return "Reading web page"
        case .build:    return "Building workflow"
        }
    }
}
```

- [ ] **Step 4: Implement AgentTool protocol**

Create `Conductor/Tools/AgentTool.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol AgentTool: Tool {
    var purpose: AgentPurpose { get }
    var friendlyName: String { get }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/AgentPurposeTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Conductor/Models/AgentPurpose.swift Conductor/Tools/AgentTool.swift ConductorTests/AgentPurposeTests.swift
git commit -m "(model): add AgentPurpose enum and AgentTool protocol"
```

---

## Task 2: LogEntry and NarrationEvent Models

**Files:**
- Create: `Conductor/Models/LogEntry.swift`
- Create: `Conductor/Models/NarrationEvent.swift`

- [ ] **Step 1: Implement LogEntry**

Create `Conductor/Models/LogEntry.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let taskID: UUID
    let purpose: AgentPurpose
    let toolName: String
    let content: String
    let sourceURL: String?
    let timestamp: Date
}
```

- [ ] **Step 2: Implement NarrationEvent**

Create `Conductor/Models/NarrationEvent.swift`:

```swift
import Foundation

struct NarrationEvent: Sendable {
    let taskID: UUID
    let purpose: AgentPurpose
    let message: String
    let timestamp: Date

    init(taskID: UUID, purpose: AgentPurpose, message: String) {
        self.taskID = taskID
        self.purpose = purpose
        self.message = message
        self.timestamp = .now
    }
}
```

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Conductor/Models/LogEntry.swift Conductor/Models/NarrationEvent.swift
git commit -m "(model): add LogEntry and NarrationEvent types"
```

---

## Task 3: ExtractedIntent Model

**Files:**
- Create: `Conductor/Models/ExtractedIntent.swift`

- [ ] **Step 1: Implement ExtractedIntent**

Create `Conductor/Models/ExtractedIntent.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct ExtractedIntent: Sendable {
    @Guide(description: "The list of purpose-tagged tasks with dependency edges")
    var purposes: [PurposeTask]
}

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct PurposeTask: Sendable {
    @Guide(description: "The purpose category: overview, research, web, or build")
    var purpose: String

    @Guide(description: "What the agent should accomplish")
    var goal: String

    @Guide(description: "When the agent should stop, e.g. 'until you have 3 cited sources'")
    var completionCriteria: String

    @Guide(description: "Indices of tasks in this array that must complete before this one starts")
    var dependsOn: [Int]
}
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Conductor/Models/ExtractedIntent.swift
git commit -m "(model): add ExtractedIntent generable type for LLM output"
```

---

## Task 4: TaskGraph Actor

**Files:**
- Create: `Conductor/Services/TaskGraph.swift`
- Test: `ConductorTests/TaskGraphTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ConductorTests/TaskGraphTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("TaskGraph Tests", .serialized)
struct TaskGraphTests {

    private func makeDummyNode(
        id: UUID = UUID(),
        purpose: AgentPurpose = .research,
        dependsOn: Set<UUID> = []
    ) -> TaskGraph.TaskNode {
        TaskGraph.TaskNode(
            id: id,
            purpose: purpose,
            goal: "test goal",
            completionCriteria: "test criteria",
            toolNames: ["TestTool"],
            dependsOn: dependsOn
        )
    }

    @Test("New graph is not fully resolved when it has pending nodes")
    func notResolvedWhenPending() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        let resolved = await graph.isFullyResolved
        #expect(!resolved)
    }

    @Test("Graph is fully resolved when all nodes are completed")
    func resolvedWhenAllCompleted() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        await graph.updateStatus(node.id, to: .completed)
        let resolved = await graph.isFullyResolved
        #expect(resolved)
    }

    @Test("Graph is fully resolved when all nodes are terminal (completed or failed)")
    func resolvedWhenTerminal() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode()
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .completed)
        await graph.updateStatus(b.id, to: .failed)
        let resolved = await graph.isFullyResolved
        #expect(resolved)
    }

    @Test("readyToDispatch returns nodes with no unresolved dependencies")
    func readyNoDeps() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == node.id)
    }

    @Test("readyToDispatch blocks nodes with unresolved dependencies")
    func blockedByDeps() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode(dependsOn: [a.id])
        await graph.addNode(a)
        await graph.addNode(b)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == a.id)
    }

    @Test("readyToDispatch unblocks downstream when upstream completes")
    func unblocksDownstream() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode(dependsOn: [a.id])
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .completed)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == b.id)
    }

    @Test("readyToDispatch does not return running or completed nodes")
    func skipsNonPending() async {
        let graph = TaskGraph()
        let a = makeDummyNode()
        let b = makeDummyNode()
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .running)
        let ready = await graph.readyToDispatch()
        #expect(ready.count == 1)
        #expect(ready[0].id == b.id)
    }

    @Test("Append entry to node and retrieve it")
    func appendAndRetrieve() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)
        let entry = LogEntry(
            id: UUID(), taskID: node.id, purpose: .research,
            toolName: "PubMed", content: "test content",
            sourceURL: nil, timestamp: .now
        )
        await graph.append(entry, to: node.id)
        let entries = await graph.entries(for: node.id)
        #expect(entries.count == 1)
        #expect(entries[0].content == "test content")
    }

    @Test("upstreamResults returns entries from dependency nodes only")
    func upstreamResults() async {
        let graph = TaskGraph()
        let a = makeDummyNode(purpose: .overview)
        let b = makeDummyNode(dependsOn: [a.id])
        let c = makeDummyNode()
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.addNode(c)

        let entryA = LogEntry(
            id: UUID(), taskID: a.id, purpose: .overview,
            toolName: "Wikipedia", content: "upstream content",
            sourceURL: nil, timestamp: .now
        )
        let entryC = LogEntry(
            id: UUID(), taskID: c.id, purpose: .research,
            toolName: "PubMed", content: "unrelated content",
            sourceURL: nil, timestamp: .now
        )
        await graph.append(entryA, to: a.id)
        await graph.append(entryC, to: c.id)

        let upstream = await graph.upstreamResults(for: b.id)
        #expect(upstream.count == 1)
        #expect(upstream[0].content == "upstream content")
    }

    @Test("Topological sort respects dependencies")
    func topologicalSort() async {
        let graph = TaskGraph()
        let a = makeDummyNode(purpose: .overview)
        let b = makeDummyNode(purpose: .research, dependsOn: [a.id])
        let c = makeDummyNode(purpose: .build, dependsOn: [b.id])
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.addNode(c)
        let sorted = await graph.topologicalSort()
        let ids = sorted.map(\.id)
        #expect(ids.firstIndex(of: a.id)! < ids.firstIndex(of: b.id)!)
        #expect(ids.firstIndex(of: b.id)! < ids.firstIndex(of: c.id)!)
    }

    @Test("Narration events are published via stream")
    func narrationStream() async {
        let graph = TaskGraph()
        let node = makeDummyNode()
        await graph.addNode(node)

        let stream = await graph.narrationStream

        await graph.narrate(node.id, "Starting research...")

        var events: [NarrationEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == 1 { break }
        }
        #expect(events[0].message == "Starting research...")
        #expect(events[0].purpose == .research)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/TaskGraphTests 2>&1 | tail -20`
Expected: FAIL — `TaskGraph` not found

- [ ] **Step 3: Implement TaskGraph**

Create `Conductor/Services/TaskGraph.swift`:

```swift
import Foundation

actor TaskGraph {

    struct TaskNode: Sendable {
        let id: UUID
        let purpose: AgentPurpose
        let goal: String
        let completionCriteria: String
        let toolNames: [String]
        let dependsOn: Set<UUID>

        var entries: [LogEntry] = []
        var status: TaskStatus = .pending
    }

    enum TaskStatus: Sendable {
        case pending, running, completed, failed

        var isTerminal: Bool {
            self == .completed || self == .failed
        }
    }

    private var nodes: [UUID: TaskNode] = [:]
    private var narrationContinuation: AsyncStream<NarrationEvent>.Continuation?
    private var _narrationStream: AsyncStream<NarrationEvent>?

    var narrationStream: AsyncStream<NarrationEvent> {
        if let existing = _narrationStream { return existing }
        let stream = AsyncStream<NarrationEvent> { continuation in
            self.narrationContinuation = continuation
        }
        _narrationStream = stream
        return stream
    }

    func addNode(_ node: TaskNode) {
        nodes[node.id] = node
    }

    func updateStatus(_ id: UUID, to status: TaskStatus) {
        nodes[id]?.status = status
    }

    func append(_ entry: LogEntry, to taskID: UUID) {
        nodes[taskID]?.entries.append(entry)
    }

    func entries(for taskID: UUID) -> [LogEntry] {
        nodes[taskID]?.entries ?? []
    }

    func upstreamResults(for taskID: UUID) -> [LogEntry] {
        guard let node = nodes[taskID] else { return [] }
        return node.dependsOn.flatMap { nodes[$0]?.entries ?? [] }
    }

    func readyToDispatch() -> [TaskNode] {
        nodes.values.filter { node in
            node.status == .pending &&
            node.dependsOn.allSatisfy { nodes[$0]?.status.isTerminal == true }
        }
    }

    var isFullyResolved: Bool {
        !nodes.isEmpty && nodes.values.allSatisfy(\.status.isTerminal)
    }

    func narrate(_ taskID: UUID, _ message: String) {
        guard let node = nodes[taskID] else { return }
        let event = NarrationEvent(taskID: taskID, purpose: node.purpose, message: message)
        narrationContinuation?.yield(event)
    }

    func finishNarration() {
        narrationContinuation?.finish()
    }

    func topologicalSort() -> [TaskNode] {
        var sorted: [TaskNode] = []
        var visited = Set<UUID>()

        func visit(_ id: UUID) {
            guard !visited.contains(id), let node = nodes[id] else { return }
            visited.insert(id)
            for dep in node.dependsOn {
                visit(dep)
            }
            sorted.append(node)
        }

        for id in nodes.keys {
            visit(id)
        }
        return sorted
    }

    var allNodes: [TaskNode] {
        Array(nodes.values)
    }

    var nodeCount: Int {
        nodes.count
    }

    func node(for id: UUID) -> TaskNode? {
        nodes[id]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/TaskGraphTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/TaskGraph.swift ConductorTests/TaskGraphTests.swift
git commit -m "(service): add TaskGraph actor for plan coordination and shared context"
```

---

## Task 5: StitchedResponse

**Files:**
- Create: `Conductor/Models/StitchedResponse.swift`
- Test: `ConductorTests/StitchedResponseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ConductorTests/StitchedResponseTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("StitchedResponse Tests")
struct StitchedResponseTests {

    @Test("Formatted output includes section headings and content")
    func formattedOutput() {
        let sections = [
            StitchedResponse.ResponseSection(
                heading: "Overview",
                content: "CRISPR is a gene editing technology.",
                sources: []
            ),
            StitchedResponse.ResponseSection(
                heading: "Research Findings",
                content: "Frangoul et al. demonstrated clinical response.",
                sources: [ToolSource(title: "PubMed", url: "https://pubmed.ncbi.nlm.nih.gov/123")]
            ),
        ]
        let response = StitchedResponse(sections: sections)
        let output = response.formatted
        #expect(output.contains("## Overview"))
        #expect(output.contains("CRISPR is a gene editing technology."))
        #expect(output.contains("## Research Findings"))
        #expect(output.contains("Frangoul"))
    }

    @Test("Empty sections produce empty formatted output")
    func emptyResponse() {
        let response = StitchedResponse(sections: [])
        #expect(response.formatted.isEmpty)
    }

    @Test("Stitch from TaskGraph produces sections in topological order")
    func stitchFromGraph() async {
        let graph = TaskGraph()

        let a = TaskGraph.TaskNode(
            id: UUID(), purpose: .overview, goal: "overview",
            completionCriteria: "done", toolNames: ["Wikipedia"],
            dependsOn: []
        )
        let b = TaskGraph.TaskNode(
            id: UUID(), purpose: .research, goal: "research",
            completionCriteria: "done", toolNames: ["PubMed"],
            dependsOn: [a.id]
        )
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .completed)
        await graph.updateStatus(b.id, to: .completed)

        let entryA = LogEntry(
            id: UUID(), taskID: a.id, purpose: .overview,
            toolName: "Wikipedia", content: "Overview content",
            sourceURL: "https://en.wikipedia.org/wiki/Test", timestamp: .now
        )
        let entryB = LogEntry(
            id: UUID(), taskID: b.id, purpose: .research,
            toolName: "PubMed", content: "Research content",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/123", timestamp: .now
        )
        await graph.append(entryA, to: a.id)
        await graph.append(entryB, to: b.id)

        let response = await graph.stitch()
        #expect(response.sections.count == 2)
        #expect(response.sections[0].heading == "Overview")
        #expect(response.sections[1].heading == "Research Findings")
        #expect(response.sections[0].sources.count == 1)
    }

    @Test("Stitch skips failed nodes")
    func stitchSkipsFailed() async {
        let graph = TaskGraph()
        let a = TaskGraph.TaskNode(
            id: UUID(), purpose: .overview, goal: "overview",
            completionCriteria: "done", toolNames: ["Wikipedia"],
            dependsOn: []
        )
        await graph.addNode(a)
        await graph.updateStatus(a.id, to: .failed)
        let response = await graph.stitch()
        #expect(response.sections.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/StitchedResponseTests 2>&1 | tail -20`
Expected: FAIL — `StitchedResponse` not found

- [ ] **Step 3: Implement StitchedResponse and TaskGraph.stitch()**

Create `Conductor/Models/StitchedResponse.swift`:

```swift
import Foundation

struct StitchedResponse: Sendable {
    let sections: [ResponseSection]

    struct ResponseSection: Sendable {
        let heading: String
        let content: String
        let sources: [ToolSource]
    }

    var formatted: String {
        sections.map { section in
            "## \(section.heading)\n\n\(section.content)"
        }.joined(separator: "\n\n")
    }
}

extension TaskGraph {
    func stitch() -> StitchedResponse {
        let ordered = topologicalSort()
        let sections = ordered
            .filter { $0.status == .completed }
            .map { node in
                StitchedResponse.ResponseSection(
                    heading: node.purpose.sectionHeading,
                    content: node.entries.map(\.content).joined(separator: "\n\n"),
                    sources: node.entries.compactMap { entry in
                        entry.sourceURL.map { ToolSource(title: entry.toolName, url: $0) }
                    }
                )
            }
        return StitchedResponse(sections: sections)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/StitchedResponseTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/StitchedResponse.swift ConductorTests/StitchedResponseTests.swift
git commit -m "(model): add StitchedResponse and deterministic graph stitching"
```

---

## Task 6: Adapt Existing Tools to AgentTool Protocol

**Files:**
- Modify: `Conductor/Tools/WikipediaSearchTool.swift`
- Modify: `Conductor/Tools/PubMedSearchTool.swift`
- Modify: `Conductor/Tools/ArXivSearchTool.swift`
- Modify: `Conductor/Tools/SemanticScholarSearchTool.swift`
- Modify: `Conductor/Tools/OpenAlexSearchTool.swift`
- Modify: `Conductor/Tools/CrossRefSearchTool.swift`
- Modify: `Conductor/Tools/WebReaderTool.swift`
- Modify: `Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift`

Each tool needs: (1) conform to `AgentTool` instead of `BadgedTool`, (2) add `purpose` and `friendlyName` properties, (3) remove `badge` property and `tracker` dependency. The `tracker` references in `call()` are removed — tool output goes through the TaskGraph now, not ToolUsageTracker.

- [ ] **Step 1: Adapt WikipediaSearchTool**

In `Conductor/Tools/WikipediaSearchTool.swift`, change the struct declaration and remove tracker:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct WikipediaSearchTool: AgentTool {
    let name = "searchWikipedia"
    let description = "Search Wikipedia for general knowledge, overviews, historical context, and encyclopedic information."
    let purpose: AgentPurpose = .overview
    let friendlyName = "Wikipedia"
```

Remove the `tracker` property, `badge` property, and all `await tracker.record(badge)` / `await tracker.addSource(...)` calls from `call(arguments:)`. The method should still return the same `String` output — just without tracker side effects.

- [ ] **Step 2: Adapt PubMedSearchTool**

In `Conductor/Tools/PubMedSearchTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct PubMedSearchTool: AgentTool {
    let name = "searchPubMed"
    let description = "Search PubMed for biomedical and clinical research articles."
    let purpose: AgentPurpose = .research
    let friendlyName = "PubMed"
```

Remove `tracker` property, `badge` property, and all tracker calls.

- [ ] **Step 3: Adapt ArXivSearchTool**

In `Conductor/Tools/ArXivSearchTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct ArXivSearchTool: AgentTool {
    let name = "searchArXiv"
    let description = "Search arXiv for preprints in physics, mathematics, computer science, and related fields."
    let purpose: AgentPurpose = .research
    let friendlyName = "arXiv"
```

Remove `tracker`, `badge`, and all tracker calls.

- [ ] **Step 4: Adapt SemanticScholarSearchTool**

In `Conductor/Tools/SemanticScholarSearchTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct SemanticScholarSearchTool: AgentTool {
    let name = "searchSemanticScholar"
    let description = "Search Semantic Scholar for cross-disciplinary academic research with citation data."
    let purpose: AgentPurpose = .research
    let friendlyName = "Semantic Scholar"
```

Remove `tracker`, `badge`, and all tracker calls.

- [ ] **Step 5: Adapt OpenAlexSearchTool**

In `Conductor/Tools/OpenAlexSearchTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct OpenAlexSearchTool: AgentTool {
    let name = "searchOpenAlex"
    let description = "Search OpenAlex for scholarly works with citation and bibliometric data."
    let purpose: AgentPurpose = .research
    let friendlyName = "OpenAlex"
```

Remove `tracker`, `badge`, and all tracker calls.

- [ ] **Step 6: Adapt CrossRefSearchTool**

In `Conductor/Tools/CrossRefSearchTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct CrossRefSearchTool: AgentTool {
    let name = "searchCrossRef"
    let description = "Search CrossRef for DOI metadata, publisher info, and citation counts."
    let purpose: AgentPurpose = .research
    let friendlyName = "CrossRef"
```

Remove `tracker`, `badge`, and all tracker calls.

- [ ] **Step 7: Adapt WebReaderTool**

In `Conductor/Tools/WebReaderTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct WebReaderTool: AgentTool {
    let name = "readWeb"
    let description = "Read a web page and extract its text content. Call when the user provides a URL they want to read, analyze, or summarize."
    let purpose: AgentPurpose = .web
    let friendlyName = "Web"
```

Remove `tracker`, `badge`, and all tracker calls. Remove the `WebReaderStatus` updates — the sub-agent lifecycle handles status narration now. The `call()` method still creates a `WebReaderService`, reads the URL, and returns the text.

- [ ] **Step 8: Adapt BuildAutomatorWorkflowTool**

In `Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct BuildAutomatorWorkflowTool: AgentTool {
    let name = "buildAutomatorWorkflow"
    let description = "Build a macOS Automator .workflow file from a natural language description."
    let purpose: AgentPurpose = .build
    let friendlyName = "Automator"
```

Remove `tracker`, `badge`, and all tracker calls. Keep the `index: AutomatorActionIndex` dependency — this is tool-specific, not tracker-related.

- [ ] **Step 9: Verify build compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Build may fail due to remaining references to `BadgedTool` / `tracker` in other files — that's expected and will be cleaned up in the next task.

- [ ] **Step 10: Commit**

```bash
git add Conductor/Tools/WikipediaSearchTool.swift Conductor/Tools/PubMedSearchTool.swift \
  Conductor/Tools/ArXivSearchTool.swift Conductor/Tools/SemanticScholarSearchTool.swift \
  Conductor/Tools/OpenAlexSearchTool.swift Conductor/Tools/CrossRefSearchTool.swift \
  Conductor/Tools/WebReaderTool.swift Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift
git commit -m "(tools): adapt all tools to AgentTool protocol with purpose and friendlyName"
```

---

## Task 7: Remove Legacy Gateway Infrastructure

**Files:**
- Modify: `Conductor/Tools/ToolSupport.swift` — strip down to just `ToolSource`
- Delete: `Conductor/Services/CapabilityRegistry.swift`
- Delete: `Conductor/Tools/ActionTool.swift`
- Delete: `Conductor/Tools/LibraryTool.swift`
- Delete: `Conductor/Tools/ManualTool.swift`
- Delete: `ConductorTests/ActionToolTests.swift`
- Delete: `ConductorTests/LibraryToolTests.swift`
- Delete: `ConductorTests/ManualToolTests.swift`
- Delete: `ConductorTests/CapabilityRegistryTests.swift`

- [ ] **Step 1: Strip ToolSupport.swift**

Replace `Conductor/Tools/ToolSupport.swift` with only what's still needed:

```swift
import Foundation

struct ToolSource: Codable, Hashable, Sendable {
    let title: String
    let url: String
}
```

This removes `BadgeTint`, `ToolBadge`, `BadgedTool`, `ToolUsageTracker`, and `SearchCapabilityAdapter`.

- [ ] **Step 2: Delete gateway tools and registry**

```bash
git rm Conductor/Services/CapabilityRegistry.swift
git rm Conductor/Tools/ActionTool.swift
git rm Conductor/Tools/LibraryTool.swift
git rm Conductor/Tools/ManualTool.swift
```

- [ ] **Step 3: Delete corresponding tests**

```bash
git rm ConductorTests/ActionToolTests.swift
git rm ConductorTests/LibraryToolTests.swift
git rm ConductorTests/ManualToolTests.swift
git rm ConductorTests/CapabilityRegistryTests.swift
```

- [ ] **Step 4: Verify build compiles (excluding ContentView which will be updated in Task 9)**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD'`
Expected: Errors only in `ContentView.swift` referencing removed types — those are fixed in Task 9.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "(tools): remove gateway tools, registry, badges, and tracker"
```

---

## Task 8: SubAgent and ConductorOrchestrator

**Files:**
- Create: `Conductor/Services/SubAgent.swift`
- Create: `Conductor/Services/ConductorOrchestrator.swift`
- Test: `ConductorTests/ConductorOrchestratorTests.swift`

- [ ] **Step 1: Write the failing test for graph construction**

Create `ConductorTests/ConductorOrchestratorTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ConductorOrchestrator Tests", .serialized)
struct ConductorOrchestratorTests {

    @Test("buildGraph creates nodes grouped by purpose with correct tool count")
    func buildGraphGroupsByPurpose() async {
        let toolbox: [any AgentTool] = [
            WikipediaSearchTool(),
            PubMedSearchTool(),
            ArXivSearchTool(),
            SemanticScholarSearchTool(),
        ]
        let orchestrator = ConductorOrchestrator(toolbox: toolbox)

        let intent = ExtractedIntent(purposes: [
            PurposeTask(purpose: "overview", goal: "understand topic",
                        completionCriteria: "until summarized", dependsOn: []),
            PurposeTask(purpose: "research", goal: "find papers",
                        completionCriteria: "until 3 sources found", dependsOn: [0]),
        ])

        let graph = await orchestrator.buildGraph(from: intent)
        let nodes = await graph.allNodes

        // overview has 1 tool (Wikipedia) → 1 node
        let overviewNodes = nodes.filter { $0.purpose == .overview }
        #expect(overviewNodes.count == 1)
        #expect(overviewNodes[0].toolNames.count == 1)

        // research has 3 tools → 2 nodes (chunks of 2: [PubMed, arXiv], [SemanticScholar])
        let researchNodes = nodes.filter { $0.purpose == .research }
        #expect(researchNodes.count == 2)
    }

    @Test("buildGraph sets correct dependencies across chunked nodes")
    func buildGraphDependencies() async {
        let toolbox: [any AgentTool] = [
            WikipediaSearchTool(),
            PubMedSearchTool(),
            ArXivSearchTool(),
        ]
        let orchestrator = ConductorOrchestrator(toolbox: toolbox)

        let intent = ExtractedIntent(purposes: [
            PurposeTask(purpose: "overview", goal: "overview",
                        completionCriteria: "done", dependsOn: []),
            PurposeTask(purpose: "research", goal: "research",
                        completionCriteria: "done", dependsOn: [0]),
        ])

        let graph = await orchestrator.buildGraph(from: intent)
        let nodes = await graph.allNodes
        let overviewNode = nodes.first { $0.purpose == .overview }!
        let researchNodes = nodes.filter { $0.purpose == .research }

        for researchNode in researchNodes {
            #expect(researchNode.dependsOn.contains(overviewNode.id))
        }
    }

    @Test("buildGraph with no matching tools creates no nodes for that purpose")
    func buildGraphNoMatchingTools() async {
        let toolbox: [any AgentTool] = [WikipediaSearchTool()]
        let orchestrator = ConductorOrchestrator(toolbox: toolbox)

        let intent = ExtractedIntent(purposes: [
            PurposeTask(purpose: "build", goal: "build something",
                        completionCriteria: "done", dependsOn: []),
        ])

        let graph = await orchestrator.buildGraph(from: intent)
        let count = await graph.nodeCount
        #expect(count == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/ConductorOrchestratorTests 2>&1 | tail -20`
Expected: FAIL — `ConductorOrchestrator` not found

- [ ] **Step 3: Implement SubAgent**

Create `Conductor/Services/SubAgent.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
actor SubAgent {
    let task: TaskGraph.TaskNode
    let graph: TaskGraph
    let tools: [any AgentTool]
    private let session: LanguageModelSession

    init(task: TaskGraph.TaskNode, tools: [any AgentTool], graph: TaskGraph) {
        self.task = task
        self.tools = tools
        self.graph = graph
        self.session = LanguageModelSession(
            tools: tools,
            instructions: """
            You are \(task.purpose.agentDescription).
            Your goal: \(task.goal)
            You have these tools: \(task.toolNames.joined(separator: ", "))
            Keep working until: \(task.completionCriteria)
            """
        )
    }

    func run() async {
        await graph.updateStatus(task.id, to: .running)
        await graph.narrate(
            task.id,
            "\(task.purpose.narrationPrefix) (\(task.toolNames.joined(separator: ", ")))"
        )

        let upstream = await graph.upstreamResults(for: task.id)
        let prompt = buildPrompt(upstream: upstream)

        do {
            var content = ""
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                content = partial.content
            }

            if !content.isEmpty {
                let entry = LogEntry(
                    id: UUID(),
                    taskID: task.id,
                    purpose: task.purpose,
                    toolName: task.toolNames.joined(separator: ", "),
                    content: content,
                    sourceURL: nil,
                    timestamp: .now
                )
                await graph.append(entry, to: task.id)
            }
            await graph.updateStatus(task.id, to: .completed)
            await graph.narrate(task.id, "Completed.")
        } catch {
            let errorEntry = LogEntry(
                id: UUID(),
                taskID: task.id,
                purpose: task.purpose,
                toolName: "error",
                content: error.localizedDescription,
                sourceURL: nil,
                timestamp: .now
            )
            await graph.append(errorEntry, to: task.id)
            await graph.updateStatus(task.id, to: .failed)
            await graph.narrate(task.id, "Failed: \(error.localizedDescription)")
        }
    }

    private func buildPrompt(upstream: [LogEntry]) -> String {
        if upstream.isEmpty { return task.goal }
        let context = upstream
            .map { "[\($0.purpose.rawValue)] \($0.content)" }
            .joined(separator: "\n---\n")
        return """
        Context from prior work:
        \(context)

        Your task: \(task.goal)
        """
    }
}
```

- [ ] **Step 4: Implement ConductorOrchestrator**

Create `Conductor/Services/ConductorOrchestrator.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Observable
final class ConductorOrchestrator {
    let toolbox: [any AgentTool]
    private(set) var activeGraph: TaskGraph?

    private static let instructions = """
    Extract the user's intent as a structured plan.
    Identify what purposes are needed and how they depend on each other.
    Available purposes: overview (background context via Wikipedia), research (academic papers), web (read a specific URL), build (create Automator workflow).
    Do not perform any tasks yourself. Only produce the plan.
    """

    init(toolbox: [any AgentTool]) {
        self.toolbox = toolbox
    }

    func handle(userMessage: String) async throws -> StitchedResponse {
        let intentSession = LanguageModelSession(
            tools: [IntentExtractionTool()],
            instructions: Self.instructions
        )

        let response = try await intentSession.respond(
            to: userMessage,
            generating: ExtractedIntent.self
        )

        let graph = await buildGraph(from: response)
        activeGraph = graph

        await execute(graph)

        let stitched = await graph.stitch()
        await graph.finishNarration()
        return stitched
    }

    func buildGraph(from intent: ExtractedIntent) async -> TaskGraph {
        let graph = TaskGraph()
        var idMap: [Int: [UUID]] = [:]

        for (index, purposeTask) in intent.purposes.enumerated() {
            guard let purpose = AgentPurpose(rawValue: purposeTask.purpose) else { continue }
            let tools = toolbox.filter { $0.purpose == purpose }
            guard !tools.isEmpty else { continue }

            let chunks = tools.chunked(into: 2)
            var nodeIDs: [UUID] = []
            let dependencies = Set(purposeTask.dependsOn.flatMap { idMap[$0] ?? [] })

            for chunk in chunks {
                let id = UUID()
                nodeIDs.append(id)
                let node = TaskGraph.TaskNode(
                    id: id,
                    purpose: purpose,
                    goal: purposeTask.goal,
                    completionCriteria: purposeTask.completionCriteria,
                    toolNames: chunk.map(\.friendlyName),
                    dependsOn: dependencies
                )
                await graph.addNode(node)
            }
            idMap[index] = nodeIDs
        }
        return graph
    }

    private func execute(_ graph: TaskGraph) async {
        while await !graph.isFullyResolved {
            let ready = await graph.readyToDispatch()
            guard !ready.isEmpty else { break }

            await withTaskGroup(of: Void.self) { group in
                for node in ready {
                    let tools = toolbox.filter { $0.purpose == node.purpose }
                    let nodeTools = tools.filter { node.toolNames.contains($0.friendlyName) }
                    group.addTask {
                        let agent = SubAgent(task: node, tools: nodeTools, graph: graph)
                        await agent.run()
                    }
                }
            }
        }
    }
}

// MARK: - IntentExtractionTool

@available(iOS 19.0, macOS 26.0, *)
struct IntentExtractionTool: Tool {
    let name = "extractIntent"
    let description = "Break down the user's message into a structured plan of purpose-tagged tasks with dependencies."

    @Generable
    struct Arguments {
        @Guide(description: "The user's original message to decompose")
        var userMessage: String
    }

    func call(arguments: Arguments) async throws -> String {
        // This tool exists so the LLM can structure its output.
        // The actual intent is extracted via respond(generating: ExtractedIntent.self).
        return arguments.userMessage
    }
}

// MARK: - Array Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/ConductorOrchestratorTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Conductor/Services/SubAgent.swift Conductor/Services/ConductorOrchestrator.swift ConductorTests/ConductorOrchestratorTests.swift
git commit -m "(service): add SubAgent actor and ConductorOrchestrator with graph-based dispatch"
```

---

## Task 9: Update ContentView — Wire ConductorOrchestrator and Narration UI

**Files:**
- Modify: `Conductor/ContentView.swift`
- Create: `Conductor/Views/NarrationGroupView.swift`
- Create: `Conductor/Views/TaskGraphSheet.swift`

This is the largest task — it replaces the inline session logic in `ChatDetailView` with the `ConductorOrchestrator`, updates the `Message` model, adds narration display, and adds the info drilldown sheet.

- [ ] **Step 1: Update Message model**

In `Conductor/ContentView.swift`, replace the `Message` struct (lines 20-56) with:

```swift
struct Message: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    var sources: [ToolSource]
    var narrationLog: [NarrationRecord]

    struct NarrationRecord: Codable, Sendable {
        let purpose: String
        let messages: [String]
    }

    // Non-codable — populated at runtime for info drilldown
    var taskGraphSnapshot: TaskGraphSnapshot?

    enum CodingKeys: String, CodingKey {
        case id, content, isUser, timestamp, sources, narrationLog
    }

    init(
        id: UUID = UUID(),
        content: String,
        isUser: Bool,
        timestamp: Date,
        sources: [ToolSource] = [],
        narrationLog: [NarrationRecord] = [],
        taskGraphSnapshot: TaskGraphSnapshot? = nil
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.sources = sources
        self.narrationLog = narrationLog
        self.taskGraphSnapshot = taskGraphSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        isUser = try container.decode(Bool.self, forKey: .isUser)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sources = try container.decodeIfPresent([ToolSource].self, forKey: .sources) ?? []
        narrationLog = try container.decodeIfPresent([NarrationRecord].self, forKey: .narrationLog) ?? []
    }
}

struct TaskGraphSnapshot {
    let nodes: [NodeSnapshot]
    let totalDuration: TimeInterval
    let toolCallCount: Int

    struct NodeSnapshot {
        let purpose: AgentPurpose
        let toolNames: [String]
        let status: String
        let entries: [LogEntry]
        let duration: TimeInterval
    }
}
```

- [ ] **Step 2: Create NarrationGroupView**

Create `Conductor/Views/NarrationGroupView.swift`:

```swift
import SwiftUI

struct NarrationGroupView: View {
    let records: [Message.NarrationRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(records, id: \.purpose) { record in
                if let purpose = AgentPurpose(rawValue: record.purpose) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(purpose.sectionHeading.uppercased())
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(purpose.displayColor)
                            .tracking(0.5)

                        ForEach(record.messages, id: \.self) { message in
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(purpose.displayColor)
                            .frame(width: 3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Create TaskGraphSheet**

Create `Conductor/Views/TaskGraphSheet.swift`:

```swift
import SwiftUI

struct TaskGraphSheet: View {
    let snapshot: TaskGraphSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(snapshot.nodes.enumerated()), id: \.offset) { _, node in
                        nodeView(node)
                    }

                    // Summary
                    HStack {
                        Text("\(snapshot.nodes.count) agents")
                        Text("·")
                        Text("\(snapshot.toolCallCount) tool calls")
                        Text("·")
                        Text(String(format: "%.1fs", snapshot.totalDuration))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Research Log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func nodeView(_ node: TaskGraphSnapshot.NodeSnapshot) -> some View {
        let purpose = node.purpose
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(purpose.sectionHeading.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(purpose.displayColor)
                    .tracking(0.5)
                Spacer()
                Text(node.status)
                    .font(.caption2)
                    .foregroundStyle(node.status == "completed" ? .green : .red)
                Text(String(format: "%.1fs", node.duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(node.entries, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.toolName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(entry.content)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(4)
                    if let url = entry.sourceURL {
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .italic()
                    }
                }
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(purpose.displayColor)
                .frame(width: 3)
        }
    }
}
```

- [ ] **Step 4: Rewrite ChatDetailView to use ConductorOrchestrator**

Replace the `ChatDetailView` struct in `Conductor/ContentView.swift`. Key changes:
- Remove `session`, `tools`, `toolTracker` properties
- Add `orchestrator: ConductorOrchestrator` property
- Remove `searchCapabilities()`, `automatorCapability()` static methods
- Remove `compactSession()`, `isRepeatedResponse()` methods
- Replace `streamResponse(to:)` with orchestrator-based flow
- Add narration observation
- Add info drilldown sheet trigger

The new `ChatDetailView.init`:

```swift
init(chat: Chat, chatManager: ChatManager) {
    self.chat = chat
    self.chatManager = chatManager

    var toolbox: [any AgentTool] = [
        WikipediaSearchTool(),
        PubMedSearchTool(),
        ArXivSearchTool(),
        SemanticScholarSearchTool(),
        OpenAlexSearchTool(),
        CrossRefSearchTool(),
        WebReaderTool(),
    ]
    #if os(macOS)
    toolbox.append(BuildAutomatorWorkflowTool(index: Self.automatorIndex))
    #endif

    self._orchestrator = State(initialValue: ConductorOrchestrator(toolbox: toolbox))
}
```

The new `sendMessage()`:

```swift
private func sendMessage() async {
    guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard modelAvailability == .available else { return }
    guard !isResponding else { return }

    let userMessageContent = messageText
    messageText = ""

    let userMessage = Message(content: userMessageContent, isUser: true, timestamp: .now)
    messages.append(userMessage)
    chatManager.addMessage(userMessage, to: chat.id)

    isResponding = true
    narrationEvents = []

    do {
        // Start narration observation
        if let graph = orchestrator.activeGraph {
            observeNarration(graph)
        }

        let startTime = Date()
        let response = try await orchestrator.handle(userMessage: userMessageContent)
        let duration = Date().timeIntervalSince(startTime)

        // Build narration log from collected events
        let narrationLog = buildNarrationLog(from: narrationEvents)

        // Build graph snapshot for drilldown
        let snapshot = await buildSnapshot(duration: duration)

        let assistantMessage = Message(
            content: response.formatted,
            isUser: false,
            timestamp: .now,
            sources: response.sections.flatMap(\.sources),
            narrationLog: narrationLog,
            taskGraphSnapshot: snapshot
        )
        messages.append(assistantMessage)
        chatManager.addMessage(assistantMessage, to: chat.id)
    } catch {
        let errorMessage = Message(
            content: "Something went wrong: \(error.localizedDescription)",
            isUser: false,
            timestamp: .now
        )
        messages.append(errorMessage)
        chatManager.addMessage(errorMessage, to: chat.id)
    }

    isResponding = false
}
```

- [ ] **Step 5: Update MessageBubbleView**

In `MessageBubbleView`, replace badge display with narration display and add info button:
- Remove `ToolBadge` rendering (the HStack of badges)
- Remove `WorkflowCardView` and `WebReaderCardView` references
- Add `NarrationGroupView` above the message content
- Add info button below the message content when `taskGraphSnapshot != nil`
- Add `.sheet` modifier for `TaskGraphSheet`

- [ ] **Step 6: Verify build compiles and app runs**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Conductor/ContentView.swift Conductor/Views/NarrationGroupView.swift Conductor/Views/TaskGraphSheet.swift
git commit -m "(views): wire ConductorOrchestrator into chat UI with narration and info drilldown"
```

---

## Task 10: Update Existing Tool Tests

**Files:**
- Modify: `ConductorTests/PubMedTests.swift`
- Modify: `ConductorTests/ArXivTests.swift`
- Modify: `ConductorTests/CrossRefTests.swift`
- Modify: `ConductorTests/SemanticScholarTests.swift`
- Modify: `ConductorTests/OpenAlexTests.swift`
- Modify: `ConductorTests/WebReaderToolTests.swift`

Existing tests that construct tools with `tracker:` parameter need updating since the tracker was removed.

- [ ] **Step 1: Update each test file**

In each test file, remove `tracker` argument from tool construction. For example, in `PubMedTests.swift`, change:

```swift
let tool = PubMedSearchTool(tracker: ToolUsageTracker())
```

to:

```swift
let tool = PubMedSearchTool()
```

Apply the same change to all test files listed above.

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass (existing tool behavior is unchanged, only tracker dependency removed)

- [ ] **Step 3: Commit**

```bash
git add ConductorTests/
git commit -m "(test): update tool tests to match tracker-free AgentTool interface"
```

---

## Task 11: Clean Up Unused Views and Final Verification

**Files:**
- Evaluate: `Conductor/Views/WebReaderCardView.swift` — may still be useful if WebReaderTool output is displayed specially
- Evaluate: `Conductor/Views/WebReaderHost.swift` — used by WebReaderService, keep

- [ ] **Step 1: Remove WebReaderCardView if no longer referenced**

If `WebReaderCardView` was only used by `MessageBubbleView` to display `WebReaderStatus` (which was tracked by `ToolUsageTracker`), and that display is now replaced by narration, delete it:

```bash
git rm Conductor/Views/WebReaderCardView.swift
```

Keep `WebReaderHost.swift` — it's used by `WebReaderService`.

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 3: Run the app and verify basic flow**

Build and run the app. Verify:
1. App launches without crash
2. Creating a new chat works
3. Sending a message triggers the orchestrator
4. Narration messages appear grouped by purpose
5. Stitched response appears as final message
6. Info button opens the task graph sheet

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "(cleanup): remove unused views and verify multi-agent orchestration end-to-end"
```
