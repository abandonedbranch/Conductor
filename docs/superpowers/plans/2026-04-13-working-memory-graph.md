# Working Memory Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ephemeral `TaskGraph`/`SubAgent`/`AgentPurpose` stack with a persistent `WorkingMemoryGraph` where every LLM call is stateless typed inference, planning and state live in Swift, and the LLM only translates language into typed values.

**Architecture:** Four-slot graph actor (Intent, Actions, Subjects, Outcome) persisted per-chat. Three LLM touchpoints per turn: intent (`parseIntent`/`updateIntent` → `LanguageIntentQuery`), sub-agents (generic `Agent` with narrow memory-verb + tool set), synthesis (`composeResponse` with RAG). Observer cascade inside the actor rewires Actions/Subjects on intent write. `deterministicSearch` over `AffordanceBearing` picks tools and verbs per Action. UI bridges via `AsyncStream<ChangeKind>` + `@MainActor @Observable GraphProxy`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Apple Foundation Models (`@Generable`, `LanguageModelSession`, `Tool`), Swift Testing (`import Testing`, `@Test`, `#expect`), UserDefaults persistence.

**Companion spec:** `docs/superpowers/specs/2026-04-11-working-memory-graph-design.md` — read this first.

**Xcode project note:** Every new `.swift` file created under `Conductor/` must be added to the `Conductor` target in `Conductor.xcodeproj`. Every new file created under `ConductorTests/` must be added to the `ConductorTests` target. If `swift build` or `xcodebuild` doesn't pick up a new file, it's almost always a missing target membership — fix that before debugging the code.

**Commit style (per `CLAUDE.md`):** `(topic): subject`. No AI attribution, no `claude.ai` links.

---

## Phase 1 — Vocabulary, Intent, Atoms

### Task 1: Vocabulary enums

**Files:**
- Create: `Conductor/Models/Vocabulary.swift`
- Test: `ConductorTests/VocabularyTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("Vocabulary")
struct VocabularyTests {
    @Test("IntentVerb covers the seed set")
    func intentVerbCases() {
        let raws = IntentVerb.allCases.map(\.rawValue).sorted()
        #expect(raws == ["build", "find", "read", "recall", "summarize"])
    }

    @Test("IntentSubject covers the seed set")
    func intentSubjectCases() {
        #expect(IntentSubject.allCases.count == 7)
        #expect(IntentSubject(rawValue: "academic") == .academic)
    }

    @Test("AnswerShape covers the seed set")
    func answerShapeCases() {
        let raws = Set(AnswerShape.allCases.map(\.rawValue))
        #expect(raws == ["overview", "summary", "citations", "workflow", "direct"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -only-testing:ConductorTests/VocabularyTests`
Expected: FAIL — `IntentVerb` / `IntentSubject` / `AnswerShape` undefined.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum IntentVerb: String, Codable, CaseIterable, Sendable {
    case find
    case summarize
    case recall
    case build
    case read
}

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum IntentSubject: String, Codable, CaseIterable, Sendable {
    case academic
    case biomedical
    case preprint
    case encyclopedic
    case webpage
    case workflow
    case conversational
}

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum AnswerShape: String, Codable, CaseIterable, Sendable {
    case overview
    case summary
    case citations
    case workflow
    case direct
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -only-testing:ConductorTests/VocabularyTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/Vocabulary.swift ConductorTests/VocabularyTests.swift
git commit -m "(model): add vocabulary enums for intent verbs, subjects, answer shapes"
```

---

### Task 2: LanguageIntentQuery

**Files:**
- Create: `Conductor/Models/LanguageIntentQuery.swift`
- Test: `ConductorTests/LanguageIntentQueryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("LanguageIntentQuery")
struct LanguageIntentQueryTests {
    @Test("Round-trips through JSONEncoder/Decoder")
    func codable() throws {
        let original = LanguageIntentQuery(
            verbs: [.find, .summarize],
            subjects: ["CRISPR"],
            answerShape: .overview,
            continuation: .extends
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LanguageIntentQuery.self, from: data)
        #expect(decoded.verbs == [.find, .summarize])
        #expect(decoded.subjects == ["CRISPR"])
        #expect(decoded.answerShape == .overview)
        #expect(decoded.continuation == .extends)
    }

    @Test("Continuation accepts all four cases")
    func continuationCases() {
        let cases: [LanguageIntentQuery.Continuation] = [.refines, .extends, .pivots, .recalls]
        #expect(cases.count == 4)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test ... -only-testing:ConductorTests/LanguageIntentQueryTests`
Expected: FAIL — `LanguageIntentQuery` undefined.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct LanguageIntentQuery: Sendable, Codable {
    @Guide(description: "The verbs describing what the user wants done")
    var verbs: [IntentVerb]

    @Guide(description: "The subjects the user is asking about — short noun phrases")
    var subjects: [String]

    @Guide(description: "The shape of the answer the user expects")
    var answerShape: AnswerShape

    @Guide(description: "How this turn relates to the prior turn, if at all")
    var continuation: Continuation?

    @Generable
    enum Continuation: String, Codable, Sendable {
        case refines
        case extends
        case pivots
        case recalls
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test ... -only-testing:ConductorTests/LanguageIntentQueryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/LanguageIntentQuery.swift ConductorTests/LanguageIntentQueryTests.swift
git commit -m "(model): add LanguageIntentQuery Generable type"
```

---

### Task 3: Atom and ErrorAtom

**Files:**
- Create: `Conductor/Models/Atom.swift`
- Test: `ConductorTests/AtomTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("Atom")
struct AtomTests {
    @Test("Success atom round-trips through Codable")
    func successCodable() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let atom: Atom = .success(
            content: "hello",
            source: URL(string: "https://example.com"),
            toolName: "Wikipedia",
            timestamp: timestamp
        )
        let data = try JSONEncoder().encode(atom)
        let decoded = try JSONDecoder().decode(Atom.self, from: data)
        if case let .success(content, source, toolName, ts) = decoded {
            #expect(content == "hello")
            #expect(source?.absoluteString == "https://example.com")
            #expect(toolName == "Wikipedia")
            #expect(ts == timestamp)
        } else {
            Issue.record("expected .success atom")
        }
    }

    @Test("ErrorAtom round-trips")
    func errorCodable() throws {
        let err = ErrorAtom(
            actionID: UUID(),
            toolName: "PubMed",
            kind: .timeout,
            message: "slow",
            timestamp: .now
        )
        let data = try JSONEncoder().encode(err)
        let decoded = try JSONDecoder().decode(ErrorAtom.self, from: data)
        #expect(decoded.kind == .timeout)
        #expect(decoded.message == "slow")
    }

    @Test("ErrorKind has the seed set")
    func errorKindCases() {
        #expect(ErrorKind.allCases.count == 5)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — types undefined.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

enum Atom: Codable, Sendable {
    case success(content: String, source: URL?, toolName: String, timestamp: Date)
    case error(ErrorAtom)
    case note(text: String, timestamp: Date)
}

struct ErrorAtom: Codable, Sendable, Hashable {
    let actionID: UUID
    let toolName: String?
    let kind: ErrorKind
    let message: String
    let timestamp: Date
}

enum ErrorKind: String, Codable, Sendable, CaseIterable {
    case networkError
    case unsafeContent
    case timeout
    case noResults
    case unknown
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/Atom.swift ConductorTests/AtomTests.swift
git commit -m "(model): add Atom, ErrorAtom, and ErrorKind"
```

---

### Task 4: SubjectStack

**Files:**
- Create: `Conductor/Models/SubjectStack.swift`
- Test: `ConductorTests/SubjectStackTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("SubjectStack")
struct SubjectStackTests {
    @Test("Push appends to active when under cap")
    func pushUnderCap() {
        var stack = SubjectStack()
        stack.push(name: "CRISPR", turn: 1, relatesTo: nil)
        #expect(stack.active.count == 1)
        #expect(stack.active.first?.name == "CRISPR")
    }

    @Test("Active overflow moves oldest entry to archived")
    func activeOverflow() {
        var stack = SubjectStack()
        for i in 0..<9 {
            stack.push(name: "subject-\(i)", turn: i, relatesTo: nil)
        }
        #expect(stack.active.count == 8)
        #expect(stack.archived.count == 1)
        #expect(stack.archived.first?.name == "subject-0")
    }

    @Test("Archive overflow drops least-recently-touched entry")
    func archiveLRU() {
        var stack = SubjectStack()
        for i in 0..<8 {
            stack.push(name: "active-\(i)", turn: i, relatesTo: nil)
        }
        for i in 0..<21 {
            stack.push(name: "overflow-\(i)", turn: 100 + i, relatesTo: nil)
        }
        #expect(stack.active.count == 8)
        #expect(stack.archived.count == 20)
        #expect(!stack.archived.contains { $0.name == "active-0" })
    }

    @Test("Archive all moves active entries into archived in order")
    func archiveAll() {
        var stack = SubjectStack()
        stack.push(name: "a", turn: 1, relatesTo: nil)
        stack.push(name: "b", turn: 2, relatesTo: nil)
        stack.archiveAll()
        #expect(stack.active.isEmpty)
        #expect(stack.archived.count == 2)
    }

    @Test("touch updates lastTouchedTurn on an active entry")
    func touchUpdates() {
        var stack = SubjectStack()
        stack.push(name: "a", turn: 1, relatesTo: nil)
        let id = stack.active[0].id
        stack.touch(id: id, turn: 5)
        #expect(stack.active[0].lastTouchedTurn == 5)
    }

    @Test("Codable round-trip preserves both tiers")
    func codable() throws {
        var stack = SubjectStack()
        stack.push(name: "alpha", turn: 1, relatesTo: nil)
        stack.push(name: "beta", turn: 2, relatesTo: stack.active[0].id)
        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(SubjectStack.self, from: data)
        #expect(decoded.active.count == 2)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — type undefined.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

struct SubjectStack: Codable, Sendable {
    static let activeCap = 8
    static let archivedCap = 20

    private(set) var active: [Entry]
    private(set) var archived: [Entry]

    init(active: [Entry] = [], archived: [Entry] = []) {
        self.active = active
        self.archived = archived
    }

    struct Entry: Identifiable, Codable, Sendable, Hashable {
        let id: UUID
        let name: String
        let introducedAt: Date
        let introducedByTurn: Int
        var lastTouchedTurn: Int
        let relatesTo: UUID?

        init(
            id: UUID = UUID(),
            name: String,
            introducedAt: Date = .now,
            introducedByTurn: Int,
            lastTouchedTurn: Int,
            relatesTo: UUID? = nil
        ) {
            self.id = id
            self.name = name
            self.introducedAt = introducedAt
            self.introducedByTurn = introducedByTurn
            self.lastTouchedTurn = lastTouchedTurn
            self.relatesTo = relatesTo
        }
    }

    mutating func push(name: String, turn: Int, relatesTo: UUID?) {
        let entry = Entry(
            name: name,
            introducedByTurn: turn,
            lastTouchedTurn: turn,
            relatesTo: relatesTo
        )
        active.append(entry)
        enforceActiveCap()
    }

    mutating func archiveAll() {
        for entry in active {
            archived.insert(entry, at: 0)
        }
        active.removeAll()
        enforceArchivedCap()
    }

    mutating func touch(id: UUID, turn: Int) {
        if let i = active.firstIndex(where: { $0.id == id }) {
            active[i].lastTouchedTurn = turn
        } else if let i = archived.firstIndex(where: { $0.id == id }) {
            archived[i].lastTouchedTurn = turn
        }
    }

    private mutating func enforceActiveCap() {
        while active.count > Self.activeCap {
            let oldest = active.removeFirst()
            archived.insert(oldest, at: 0)
        }
        enforceArchivedCap()
    }

    private mutating func enforceArchivedCap() {
        guard archived.count > Self.archivedCap else { return }
        // Drop the least-recently-touched entries.
        archived.sort { $0.lastTouchedTurn > $1.lastTouchedTurn }
        archived = Array(archived.prefix(Self.archivedCap))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/SubjectStack.swift ConductorTests/SubjectStackTests.swift
git commit -m "(model): add two-tier SubjectStack with LRU archive"
```

---

## Phase 2 — Affordances, Actions

### Task 5: ToolAffordance, AffordanceBearing, AffordanceDescriptor

**Files:**
- Create: `Conductor/Models/ToolAffordance.swift`
- Test: `ConductorTests/ToolAffordanceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ToolAffordance")
struct ToolAffordanceTests {
    @Test("AffordanceDescriptor surfaces the embedded affordance")
    func descriptorAffordance() {
        let aff = ToolAffordance(
            verbs: [.find],
            subjects: [.academic],
            answerShapes: [.citations],
            priority: 10
        )
        let desc = AffordanceDescriptor(name: "PubMed", affordance: aff)
        #expect(desc.affordance.verbs.contains(.find))
        #expect(desc.name == "PubMed")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — undefined types.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct ToolAffordance: Sendable, Hashable {
    let verbs: Set<IntentVerb>
    let subjects: Set<IntentSubject>
    let answerShapes: Set<AnswerShape>
    let priority: Int
}

@available(iOS 19.0, macOS 26.0, *)
protocol AffordanceBearing {
    var affordance: ToolAffordance { get }
}

@available(iOS 19.0, macOS 26.0, *)
struct AffordanceDescriptor: Sendable, AffordanceBearing, Hashable {
    let name: String
    let affordance: ToolAffordance
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/ToolAffordance.swift ConductorTests/ToolAffordanceTests.swift
git commit -m "(model): add ToolAffordance, AffordanceBearing, and AffordanceDescriptor"
```

---

### Task 6: ActionNode

**Files:**
- Create: `Conductor/Models/ActionNode.swift`
- Test: `ConductorTests/ActionNodeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ActionNode")
struct ActionNodeTests {
    @Test("Terminal statuses are .completed and .failed")
    func terminalStatuses() {
        #expect(ActionStatus.completed.isTerminal)
        #expect(ActionStatus.failed.isTerminal)
        #expect(!ActionStatus.pending.isTerminal)
        #expect(!ActionStatus.running.isTerminal)
        #expect(!ActionStatus.awaitingUser.isTerminal)
    }

    @Test("Default node has empty atoms and pending status")
    func defaults() {
        let node = ActionNode(
            kind: .work,
            goal: "find CRISPR papers",
            verbs: [.find],
            subjects: [.academic],
            answerShape: .citations,
            assignedVerbNames: ["getContext"],
            assignedToolNames: ["PubMed"],
            dependsOn: []
        )
        #expect(node.status == .pending)
        #expect(node.atoms.isEmpty)
        #expect(node.kind == .work)
    }

    @Test("Codable round-trip preserves assignments")
    func codable() throws {
        let node = ActionNode(
            kind: .work, goal: "g",
            verbs: [.find], subjects: [.academic],
            answerShape: .citations,
            assignedVerbNames: ["append"],
            assignedToolNames: ["PubMed"],
            dependsOn: []
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ActionNode.self, from: data)
        #expect(decoded.assignedToolNames == ["PubMed"])
        #expect(decoded.assignedVerbNames == ["append"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

struct ActionNode: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: ActionKind
    let goal: String
    let verbs: [IntentVerb]
    let subjects: [IntentSubject]
    let answerShape: AnswerShape
    let assignedVerbNames: [String]
    let assignedToolNames: [String]
    var status: ActionStatus
    var atoms: [Atom]
    let dependsOn: Set<UUID>
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ActionKind,
        goal: String,
        verbs: [IntentVerb],
        subjects: [IntentSubject],
        answerShape: AnswerShape,
        assignedVerbNames: [String],
        assignedToolNames: [String],
        status: ActionStatus = .pending,
        atoms: [Atom] = [],
        dependsOn: Set<UUID>,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.goal = goal
        self.verbs = verbs
        self.subjects = subjects
        self.answerShape = answerShape
        self.assignedVerbNames = assignedVerbNames
        self.assignedToolNames = assignedToolNames
        self.status = status
        self.atoms = atoms
        self.dependsOn = dependsOn
        self.createdAt = createdAt
    }
}

enum ActionKind: String, Codable, Sendable { case work, clarification }

enum ActionStatus: String, Codable, Sendable {
    case pending, running, completed, failed, awaitingUser

    var isTerminal: Bool {
        self == .completed || self == .failed
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/ActionNode.swift ConductorTests/ActionNodeTests.swift
git commit -m "(model): add ActionNode with kind, status, and verb/tool assignments"
```

---

## Phase 3 — Budget, Projections, Memory Verb Protocol

### Task 7: ProjectionBudget

**Files:**
- Create: `Conductor/Models/ProjectionBudget.swift`
- Test: `ConductorTests/ProjectionBudgetTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ProjectionBudget")
struct ProjectionBudgetTests {
    @Test("Worst-case sub-agent budget fits in 4096 tokens")
    func worstCase() {
        let systemPrompt = 200
        let verbDefs = 4 * 150
        let toolDefs = 3 * 150
        let driver = 100
        let verbOutput =
            ProjectionBudget.contextProjection +
            ProjectionBudget.actionsProjection +
            ProjectionBudget.findRelatedResults
        let toolOutput = 800
        let modelGen = 512
        let total = systemPrompt + verbDefs + toolDefs + driver +
                    (verbOutput / 4) + toolOutput + modelGen
        #expect(total < 4096)
    }

    @Test("Truncation sentinel mentions findRelated for recovery")
    func sentinel() {
        let s = ProjectionBudget.truncationSentinel(remaining: 5)
        #expect(s.contains("5"))
        #expect(s.contains("findRelated"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

enum ProjectionBudget {
    static let contextProjection         = 512
    static let actionsProjection         = 256
    static let findRelatedResults        = 384
    static let atomContent               = 256
    static let composeResponseProjection = 1024

    /// English heuristic: ~4 characters per token.
    static func estimatedTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Truncate `text` to fit in `characterBudget`. If truncated, append the sentinel.
    static func bound(_ text: String, characterBudget: Int, remainingHint: Int = 0) -> String {
        guard text.count > characterBudget else { return text }
        let prefix = String(text.prefix(characterBudget))
        return prefix + "\n" + truncationSentinel(remaining: remainingHint)
    }

    static func truncationSentinel(remaining: Int) -> String {
        "... [truncated; \(remaining) more entries available via findRelated]"
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/ProjectionBudget.swift ConductorTests/ProjectionBudgetTests.swift
git commit -m "(model): add ProjectionBudget caps and truncation sentinel"
```

---

### Task 8: Memory verb projections and protocol

**Files:**
- Create: `Conductor/Models/MemoryVerbProjections.swift`
- Create: `Conductor/Services/MemoryVerb.swift`
- Test: `ConductorTests/MemoryVerbProjectionsTests.swift`

Projections are the bounded, `Sendable` shapes memory verbs return. The `MemoryVerb` protocol lives alongside verb implementations.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("MemoryVerbProjections")
struct MemoryVerbProjectionsTests {
    @Test("AppendSlot has both slots and is Generable-compatible Codable")
    func slotCodable() throws {
        let data = try JSONEncoder().encode(AppendSlot.outcome)
        let decoded = try JSONDecoder().decode(AppendSlot.self, from: data)
        #expect(decoded == .outcome)
    }

    @Test("AppendReceipt distinguishes acceptance from refusal")
    func receiptVariants() {
        let accepted = AppendReceipt.accepted(atomID: UUID())
        let refused = AppendReceipt.refused(reason: "unauthorized slot")
        switch accepted { case .accepted: #expect(true); default: Issue.record("accepted") }
        switch refused { case .refused: #expect(true); default: Issue.record("refused") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

`Conductor/Models/MemoryVerbProjections.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum AppendSlot: String, Codable, Sendable {
    case action
    case outcome
}

struct ContextProjection: Sendable, Codable {
    let intent: LanguageIntentQuery?
    let activeSubjects: [SubjectStack.Entry]
}

struct ActionProjection: Sendable, Codable, Identifiable {
    let id: UUID
    let kind: ActionKind
    let goal: String
    let status: ActionStatus
    let atomCount: Int
}

struct AtomProjection: Sendable, Codable {
    let actionID: UUID?
    let subjectID: UUID?
    let preview: String
    let source: URL?
    let toolName: String?
    let timestamp: Date
}

enum AppendReceipt: Sendable, Codable {
    case accepted(atomID: UUID)
    case refused(reason: String)
}
```

`Conductor/Services/MemoryVerb.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol MemoryVerb: Tool, AffordanceBearing {
    /// Stable identifier used in `assignedVerbNames`.
    var verbName: String { get }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/MemoryVerbProjections.swift Conductor/Services/MemoryVerb.swift ConductorTests/MemoryVerbProjectionsTests.swift
git commit -m "(model): add memory verb projections and MemoryVerb protocol"
```

---

## Phase 4 — Deterministic Search, Clarification

### Task 9: deterministicSearch

**Files:**
- Create: `Conductor/Services/DeterministicSearch.swift`
- Test: `ConductorTests/DeterministicSearchTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("deterministicSearch")
struct DeterministicSearchTests {
    private func desc(
        _ name: String,
        verbs: Set<IntentVerb>,
        subjects: Set<IntentSubject>,
        shapes: Set<AnswerShape>,
        priority: Int = 0
    ) -> AffordanceDescriptor {
        AffordanceDescriptor(
            name: name,
            affordance: .init(verbs: verbs, subjects: subjects, answerShapes: shapes, priority: priority)
        )
    }

    @Test("Filters out tools that don't share any verb")
    func verbFilter() {
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .citations, continuation: nil)
        let pool = [
            desc("A", verbs: [.find], subjects: [.academic], shapes: [.citations]),
            desc("B", verbs: [.build], subjects: [.academic], shapes: [.citations]),
        ]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.map(\.name) == ["A"])
    }

    @Test("Filters out tools that don't contain the requested answerShape")
    func shapeFilter() {
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .workflow, continuation: nil)
        let pool = [
            desc("Wiki", verbs: [.find], subjects: [.academic], shapes: [.overview]),
            desc("Auto", verbs: [.find], subjects: [.academic], shapes: [.workflow]),
        ]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.map(\.name) == ["Auto"])
    }

    @Test("Ranks by priority descending when tools tie on matches")
    func priorityOrder() {
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .citations, continuation: nil)
        let pool = [
            desc("Low", verbs: [.find], subjects: [.academic], shapes: [.citations], priority: 1),
            desc("High", verbs: [.find], subjects: [.academic], shapes: [.citations], priority: 9),
        ]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.map(\.name) == ["High", "Low"])
    }

    @Test("Truncates to cap")
    func cap() {
        let intent = LanguageIntentQuery(verbs: [.find], subjects: [], answerShape: .citations, continuation: nil)
        let pool = (0..<10).map {
            desc("T\($0)", verbs: [.find], subjects: [.academic], shapes: [.citations], priority: $0)
        }
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 3)
        #expect(result.count == 3)
    }

    @Test("Empty result when no pool entries match")
    func empty() {
        let intent = LanguageIntentQuery(verbs: [.build], subjects: [], answerShape: .workflow, continuation: nil)
        let pool = [desc("X", verbs: [.find], subjects: [.academic], shapes: [.citations])]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — function undefined.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

@available(iOS 19.0, macOS 26.0, *)
func deterministicSearch<T: AffordanceBearing>(
    intent: LanguageIntentQuery,
    intentSubjects: [IntentSubject],
    pool: [T],
    cap: Int
) -> [T] {
    struct Scored { let item: Any; let score: Int; let priority: Int }

    let intentVerbs = Set(intent.verbs)
    let intentSubjectSet = Set(intentSubjects)

    let matched = pool.compactMap { item -> (T, Int)? in
        let aff = item.affordance
        let sharedVerbs = aff.verbs.intersection(intentVerbs)
        guard !sharedVerbs.isEmpty else { return nil }
        guard aff.answerShapes.contains(intent.answerShape) else { return nil }
        // Subject: if caller passes a filter set, require overlap; if empty, allow anything.
        if !intentSubjectSet.isEmpty {
            let sharedSubjects = aff.subjects.intersection(intentSubjectSet)
            guard !sharedSubjects.isEmpty else { return nil }
        }
        let density = sharedVerbs.count + aff.subjects.intersection(intentSubjectSet).count
        let score = aff.priority * 100 + density
        return (item, score)
    }
    .sorted { $0.1 > $1.1 }
    .prefix(cap)
    .map(\.0)

    return Array(matched)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/DeterministicSearch.swift ConductorTests/DeterministicSearchTests.swift
git commit -m "(service): add deterministicSearch over AffordanceBearing pools"
```

---

### Task 10: ClarificationTemplate

**Files:**
- Create: `Conductor/Services/ClarificationTemplate.swift`
- Test: `ConductorTests/ClarificationTemplateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ClarificationTemplate")
struct ClarificationTemplateTests {
    @Test("Renders user-visible text that includes the verbs and subjects")
    func renders() {
        let intent = LanguageIntentQuery(
            verbs: [.build],
            subjects: ["quantum chromodynamics"],
            answerShape: .workflow,
            continuation: nil
        )
        let tools = [
            AffordanceDescriptor(name: "PubMed", affordance: .init(
                verbs: [.find], subjects: [.academic], answerShapes: [.citations], priority: 1
            )),
        ]
        let text = ClarificationTemplate.render(intent: intent, toolbox: tools)
        #expect(text.contains("build"))
        #expect(text.contains("quantum chromodynamics"))
        // Hint should mention something from the toolbox affordances.
        #expect(text.contains("academic") || text.contains("citations"))
    }

    @Test("Hint is empty-safe when toolbox is empty")
    func emptyToolbox() {
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)
        let text = ClarificationTemplate.render(intent: intent, toolbox: [])
        #expect(!text.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

@available(iOS 19.0, macOS 26.0, *)
enum ClarificationTemplate {
    static func render(
        intent: LanguageIntentQuery,
        toolbox: [AffordanceDescriptor]
    ) -> String {
        let verbs = intent.verbs.map(\.rawValue).joined(separator: ", ")
        let subjects = intent.subjects.joined(separator: ", ")
        let hint = availableHint(from: toolbox)
        var lines: [String] = []
        lines.append("I couldn't match that to any available tools.")
        lines.append("You asked for: \(verbs.isEmpty ? "(no verbs)" : verbs) on \(subjects.isEmpty ? "(no subjects)" : subjects).")
        if !hint.isEmpty {
            lines.append("I can help with: \(hint).")
        }
        lines.append("Could you rephrase, or point me at a specific source?")
        return lines.joined(separator: "\n")
    }

    private static func availableHint(from toolbox: [AffordanceDescriptor]) -> String {
        let subjects = Set(toolbox.flatMap { $0.affordance.subjects }).map(\.rawValue).sorted()
        let shapes = Set(toolbox.flatMap { $0.affordance.answerShapes }).map(\.rawValue).sorted()
        let parts = [subjects, shapes].filter { !$0.isEmpty }.map { $0.joined(separator: ", ") }
        return parts.joined(separator: "; ")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/ClarificationTemplate.swift ConductorTests/ClarificationTemplateTests.swift
git commit -m "(service): add ClarificationTemplate for zero-match fallback"
```

---

## Phase 5 — Graph Actor

### Task 11: GraphSnapshot

**Files:**
- Create: `Conductor/Models/GraphSnapshot.swift`
- Test: `ConductorTests/GraphSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("GraphSnapshot")
struct GraphSnapshotTests {
    @Test("Default snapshot carries currentSchemaVersion")
    func schemaVersion() {
        let snap = GraphSnapshot(
            intentStack: [], subjects: SubjectStack(), actions: [], outcome: []
        )
        #expect(snap.schemaVersion == GraphSnapshot.currentSchemaVersion)
    }

    @Test("Round-trips through Codable")
    func codable() throws {
        let snap = GraphSnapshot(
            intentStack: [
                LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)
            ],
            subjects: SubjectStack(),
            actions: [],
            outcome: []
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(GraphSnapshot.self, from: data)
        #expect(decoded.intentStack.count == 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

@available(iOS 19.0, macOS 26.0, *)
struct GraphSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let intentStack: [LanguageIntentQuery]
    let subjects: SubjectStack
    let actions: [ActionNode]
    let outcome: [Atom]
    let turn: Int

    init(
        schemaVersion: Int = GraphSnapshot.currentSchemaVersion,
        intentStack: [LanguageIntentQuery],
        subjects: SubjectStack,
        actions: [ActionNode],
        outcome: [Atom],
        turn: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.intentStack = intentStack
        self.subjects = subjects
        self.actions = actions
        self.outcome = outcome
        self.turn = turn
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/GraphSnapshot.swift ConductorTests/GraphSnapshotTests.swift
git commit -m "(model): add GraphSnapshot with schema versioning"
```

---

### Task 12: WorkingMemoryGraph actor — reads, writes, ChangeKind

**Files:**
- Create: `Conductor/Services/WorkingMemoryGraph.swift`
- Test: `ConductorTests/WorkingMemoryGraphTests.swift`

This task introduces the actor with basic reads, writes, and the `ChangeKind` notification stream. Observers are wired in Task 13 and Task 14.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("WorkingMemoryGraph")
struct WorkingMemoryGraphTests {
    @Test("Reads return empty before any writes")
    func emptyReads() async {
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let intent = await graph.currentIntent()
        let subjects = await graph.activeSubjects()
        let actions = await graph.allActions()
        #expect(intent == nil)
        #expect(subjects.isEmpty)
        #expect(actions.isEmpty)
    }

    @Test("append(intent:) stores the value and emits .intent")
    func appendIntent() async {
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let stream = graph.changes
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)
        await graph.append(intent: intent)

        let stored = await graph.currentIntent()
        #expect(stored?.verbs == [.find])

        var received: [ChangeKind] = []
        for await change in stream {
            received.append(change)
            if received.contains(.intent) { break }
        }
        #expect(received.contains(.intent))
    }

    @Test("updateStatus reflects in allActions")
    func updateStatus() async {
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let node = ActionNode(
            kind: .work, goal: "g", verbs: [.find], subjects: [.academic],
            answerShape: .citations, assignedVerbNames: [],
            assignedToolNames: ["PubMed"], dependsOn: []
        )
        await graph.insertAction(node)
        await graph.updateStatus(.running, for: node.id)
        let actions = await graph.allActions()
        #expect(actions.first?.status == .running)
    }

    @Test("Snapshot and restore preserves graph contents")
    func snapshotRestore() async {
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let intent = LanguageIntentQuery(verbs: [.read], subjects: ["doc"], answerShape: .summary, continuation: nil)
        await graph.append(intent: intent)
        let snap = await graph.snapshot()

        let restored = WorkingMemoryGraph.restore(from: snap, toolDescriptors: [], verbDescriptors: [])
        let intent2 = await restored.currentIntent()
        #expect(intent2?.subjects == ["doc"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

enum ChangeKind: Sendable { case intent, actions, subject, outcome }

@available(iOS 19.0, macOS 26.0, *)
actor WorkingMemoryGraph {
    private var intentStack: [LanguageIntentQuery] = []
    private var actions: [UUID: ActionNode] = [:]
    private var subjects: SubjectStack
    private var outcome: [Atom] = []
    private var turn: Int = 0

    let toolDescriptors: [AffordanceDescriptor]
    let verbDescriptors: [AffordanceDescriptor]

    nonisolated let changes: AsyncStream<ChangeKind>
    private let changesContinuation: AsyncStream<ChangeKind>.Continuation

    init(
        toolDescriptors: [AffordanceDescriptor],
        verbDescriptors: [AffordanceDescriptor],
        subjects: SubjectStack = SubjectStack(),
        turn: Int = 0
    ) {
        self.toolDescriptors = toolDescriptors
        self.verbDescriptors = verbDescriptors
        self.subjects = subjects
        self.turn = turn
        var continuation: AsyncStream<ChangeKind>.Continuation!
        self.changes = AsyncStream { continuation = $0 }
        self.changesContinuation = continuation
    }

    // MARK: - Writes

    func append(intent: LanguageIntentQuery) {
        intentStack.insert(intent, at: 0)
        turn += 1
        // Observers are wired in later tasks.
        changesContinuation.yield(.intent)
    }

    func insertAction(_ node: ActionNode) {
        actions[node.id] = node
        changesContinuation.yield(.actions)
    }

    func updateStatus(_ status: ActionStatus, for actionID: UUID) {
        actions[actionID]?.status = status
        changesContinuation.yield(.actions)
    }

    func append(atom: Atom, to actionID: UUID) {
        actions[actionID]?.atoms.append(atom)
        outcome.append(atom)
        changesContinuation.yield(.actions)
        changesContinuation.yield(.outcome)
    }

    func appendOutcome(_ atom: Atom) {
        outcome.append(atom)
        changesContinuation.yield(.outcome)
    }

    // MARK: - Reads (Sendable projections)

    func currentIntent() -> LanguageIntentQuery? { intentStack.first }

    func intentStackCopy() -> [LanguageIntentQuery] { intentStack }

    func activeSubjects() -> [SubjectStack.Entry] { subjects.active }

    func archivedSubjects() -> [SubjectStack.Entry] { subjects.archived }

    func allActions() -> [ActionNode] { Array(actions.values).sorted { $0.createdAt < $1.createdAt } }

    func action(for id: UUID) -> ActionNode? { actions[id] }

    func currentOutcome() -> [Atom] { outcome }

    func currentTurn() -> Int { turn }

    // MARK: - Persistence

    func snapshot() -> GraphSnapshot {
        GraphSnapshot(
            intentStack: intentStack,
            subjects: subjects,
            actions: allActions(),
            outcome: outcome,
            turn: turn
        )
    }

    static func restore(
        from snapshot: GraphSnapshot,
        toolDescriptors: [AffordanceDescriptor],
        verbDescriptors: [AffordanceDescriptor]
    ) -> WorkingMemoryGraph {
        let graph = WorkingMemoryGraph(
            toolDescriptors: toolDescriptors,
            verbDescriptors: verbDescriptors,
            subjects: snapshot.subjects,
            turn: snapshot.turn
        )
        graph.rehydrate(intentStack: snapshot.intentStack, actions: snapshot.actions, outcome: snapshot.outcome)
        return graph
    }

    private func rehydrate(intentStack: [LanguageIntentQuery], actions: [ActionNode], outcome: [Atom]) {
        self.intentStack = intentStack
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        self.outcome = outcome
    }

    // MARK: - Scoped mutations for observers (same-actor privileged access)

    func updateSubjects(_ transform: (inout SubjectStack) -> Void) {
        transform(&subjects)
        changesContinuation.yield(.subject)
    }
}
```

Note: we use `Dictionary(uniqueKeysWithValues:)` above; rehydrate is a trusted internal call and the snapshot is assumed well-formed. If this ever changes, the call site is the only place to revisit.

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/WorkingMemoryGraph.swift ConductorTests/WorkingMemoryGraphTests.swift
git commit -m "(service): add WorkingMemoryGraph actor with reads, writes, and ChangeKind stream"
```

---

### Task 13: Observer — rebuildActionNodes

**Files:**
- Modify: `Conductor/Services/WorkingMemoryGraph.swift`
- Test: `ConductorTests/RebuildActionNodesTests.swift`

This observer runs synchronously inside `append(intent:)`. It (a) marks any pre-existing `.awaitingUser` clarifications `.completed`, (b) decomposes the new intent into one work Action per (verb-group, subject-group) using `deterministicSearch` over tool + verb descriptors, and (c) falls back to a single `.clarification` Action when the tool pool is empty.

V1 decomposition: **one Action per intent** — the whole `LanguageIntentQuery` becomes a single Action whose assigned tools/verbs are the top-cap of `deterministicSearch`. Multi-Action decomposition is deferred.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("rebuildActionNodes observer")
struct RebuildActionNodesTests {
    private func tools() -> [AffordanceDescriptor] {
        [
            AffordanceDescriptor(name: "PubMed", affordance: .init(
                verbs: [.find], subjects: [.academic], answerShapes: [.citations], priority: 10
            )),
            AffordanceDescriptor(name: "Wikipedia", affordance: .init(
                verbs: [.find, .summarize], subjects: [.encyclopedic], answerShapes: [.overview, .direct], priority: 5
            )),
        ]
    }

    @Test("Appending intent creates one pending Action matching the toolbox")
    func createsAction() async {
        let graph = WorkingMemoryGraph(toolDescriptors: tools(), verbDescriptors: [])
        let intent = LanguageIntentQuery(
            verbs: [.find], subjects: ["CRISPR"],
            answerShape: .citations, continuation: nil
        )
        await graph.append(intent: intent)
        let actions = await graph.allActions()
        #expect(actions.count == 1)
        #expect(actions[0].kind == .work)
        #expect(actions[0].status == .pending)
        #expect(actions[0].assignedToolNames.contains("PubMed"))
    }

    @Test("Empty toolbox match produces a clarification Action")
    func clarification() async {
        let graph = WorkingMemoryGraph(toolDescriptors: tools(), verbDescriptors: [])
        let intent = LanguageIntentQuery(
            verbs: [.build], subjects: ["CRISPR"],
            answerShape: .workflow, continuation: nil
        )
        await graph.append(intent: intent)
        let actions = await graph.allActions()
        #expect(actions.count == 1)
        #expect(actions[0].kind == .clarification)
        #expect(actions[0].status == .awaitingUser)
    }

    @Test("Prior awaitingUser clarifications transition to completed on new turn")
    func priorClarificationResolves() async {
        let graph = WorkingMemoryGraph(toolDescriptors: tools(), verbDescriptors: [])
        let bad = LanguageIntentQuery(verbs: [.build], subjects: ["x"], answerShape: .workflow, continuation: nil)
        await graph.append(intent: bad)
        let stale = await graph.allActions().first!.id
        let follow = LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: .refines)
        await graph.append(intent: follow)
        let staleNow = await graph.action(for: stale)
        #expect(staleNow?.status == .completed)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — observer not wired.

- [ ] **Step 3: Write the minimal implementation**

Add to `WorkingMemoryGraph.swift`. Replace the current `append(intent:)` with the observed version:

```swift
    func append(intent: LanguageIntentQuery) {
        intentStack.insert(intent, at: 0)
        turn += 1
        rebuildActionNodes(for: intent)
        updateSubjectStack(for: intent)
        changesContinuation.yield(.intent)
    }

    // MARK: - Observers

    private func rebuildActionNodes(for intent: LanguageIntentQuery) {
        // 1. Any prior awaitingUser clarifications are now answered.
        for (id, node) in actions where node.status == .awaitingUser && node.kind == .clarification {
            actions[id]?.status = .completed
        }
        changesContinuation.yield(.actions)

        // 2. Decide intent subjects to filter on (best-effort map from strings to enum).
        let intentSubjects = intent.subjects.compactMap(IntentSubject.init(rawValue:))

        // 3. Search toolbox.
        let toolMatches = deterministicSearch(
            intent: intent, intentSubjects: intentSubjects,
            pool: toolDescriptors, cap: 4
        )
        let verbMatches = deterministicSearch(
            intent: intent, intentSubjects: intentSubjects,
            pool: verbDescriptors, cap: 4
        )

        // 4. If the toolbox doesn't match, write a clarification and stop.
        guard !toolMatches.isEmpty else {
            let clarification = ActionNode(
                kind: .clarification,
                goal: ClarificationTemplate.render(intent: intent, toolbox: toolDescriptors),
                verbs: intent.verbs,
                subjects: intentSubjects,
                answerShape: intent.answerShape,
                assignedVerbNames: [],
                assignedToolNames: [],
                status: .awaitingUser,
                dependsOn: []
            )
            actions[clarification.id] = clarification
            changesContinuation.yield(.actions)
            return
        }

        // 5. One work Action per intent (v1).
        let work = ActionNode(
            kind: .work,
            goal: intent.subjects.joined(separator: ", "),
            verbs: intent.verbs,
            subjects: intentSubjects,
            answerShape: intent.answerShape,
            assignedVerbNames: verbMatches.map(\.name),
            assignedToolNames: toolMatches.map(\.name),
            status: .pending,
            dependsOn: []
        )
        actions[work.id] = work
        changesContinuation.yield(.actions)
    }

    private func updateSubjectStack(for intent: LanguageIntentQuery) {
        // Wired in Task 14.
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/WorkingMemoryGraph.swift ConductorTests/RebuildActionNodesTests.swift
git commit -m "(service): wire rebuildActionNodes observer into WorkingMemoryGraph"
```

---

### Task 14: Observer — updateSubjectStack

**Files:**
- Modify: `Conductor/Services/WorkingMemoryGraph.swift`
- Test: `ConductorTests/UpdateSubjectStackTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("updateSubjectStack observer")
struct UpdateSubjectStackTests {
    private let pool = [
        AffordanceDescriptor(name: "Wikipedia", affordance: .init(
            verbs: [.find, .summarize], subjects: [.encyclopedic],
            answerShapes: [.overview, .direct, .summary, .citations], priority: 5
        )),
    ]

    @Test(".extends appends a new active subject")
    func extendsAppends() async {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        let a = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil)
        await graph.append(intent: a)
        let b = LanguageIntentQuery(verbs: [.find], subjects: ["transformers"], answerShape: .overview, continuation: .extends)
        await graph.append(intent: b)
        let active = await graph.activeSubjects()
        #expect(active.map(\.name) == ["CRISPR", "transformers"])
    }

    @Test(".pivots archives current active subjects and pushes new one")
    func pivotsArchives() async {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil))
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["transformers"], answerShape: .overview, continuation: .pivots))
        let active = await graph.activeSubjects()
        let archived = await graph.archivedSubjects()
        #expect(active.map(\.name) == ["transformers"])
        #expect(archived.map(\.name) == ["CRISPR"])
    }

    @Test(".refines touches the matching active subject")
    func refinesTouches() async {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil))
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: .refines))
        let active = await graph.activeSubjects()
        #expect(active.count == 1)
        #expect(active[0].lastTouchedTurn == 2)
    }

    @Test(".recalls does not change structure")
    func recallsNoop() async {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .overview, continuation: nil))
        await graph.append(intent: LanguageIntentQuery(verbs: [.recall], subjects: ["CRISPR"], answerShape: .summary, continuation: .recalls))
        let active = await graph.activeSubjects()
        #expect(active.count == 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — observer body is empty.

- [ ] **Step 3: Write the minimal implementation**

Replace the placeholder body in `updateSubjectStack`:

```swift
    private func updateSubjectStack(for intent: LanguageIntentQuery) {
        let currentTurn = turn
        switch intent.continuation {
        case .none, .refines:
            for name in intent.subjects {
                if let match = subjects.active.first(where: { $0.name == name }) {
                    subjects.touch(id: match.id, turn: currentTurn)
                } else {
                    subjects.push(name: name, turn: currentTurn, relatesTo: nil)
                }
            }
        case .extends:
            for name in intent.subjects where !subjects.active.contains(where: { $0.name == name }) {
                subjects.push(name: name, turn: currentTurn, relatesTo: nil)
            }
        case .pivots:
            subjects.archiveAll()
            for name in intent.subjects {
                subjects.push(name: name, turn: currentTurn, relatesTo: nil)
            }
        case .recalls:
            break
        }
        changesContinuation.yield(.subject)
    }
```

Note: `subjects` is an actor-isolated value type; `touch`/`push`/`archiveAll` are `mutating` on the struct and safe to call directly here because we're on the actor.

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/WorkingMemoryGraph.swift ConductorTests/UpdateSubjectStackTests.swift
git commit -m "(service): wire updateSubjectStack observer driven by continuation"
```

---

## Phase 6 — Memory Verbs

### Task 15: getContext verb

**Files:**
- Create: `Conductor/Services/Verbs/GetContextVerb.swift`
- Test: `ConductorTests/GetContextVerbTests.swift`

Each verb holds a handle to the `WorkingMemoryGraph`. Verbs are `Tool`s so they are passed to a `LanguageModelSession`. Each verb's `call(arguments:)` does an `await` hop into the actor, returns a bounded `String` (what `Tool.call` must return), and the projection type is carried by the string via JSON-encoded body.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("GetContextVerb")
struct GetContextVerbTests {
    @Test("Returns empty context when graph is untouched")
    func empty() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let verb = GetContextVerb(graph: graph)
        let result = try await verb.call(arguments: .init())
        #expect(result.contains("intent"))
    }

    @Test("Includes the current intent's verbs in the projection")
    func projectsIntent() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: [
            AffordanceDescriptor(name: "Wiki", affordance: .init(verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview], priority: 1))
        ], verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["alpha"], answerShape: .overview, continuation: nil))
        let verb = GetContextVerb(graph: graph)
        let result = try await verb.call(arguments: .init())
        #expect(result.contains("find"))
        #expect(result.contains("alpha"))
    }

    @Test("Declares the expected affordance")
    func affordance() {
        let verb = GetContextVerb(graph: WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: []))
        #expect(verb.affordance.verbs.contains(.recall))
        #expect(verb.verbName == "getContext")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct GetContextVerb: MemoryVerb {
    let graph: WorkingMemoryGraph

    let name = "getContext"
    let verbName = "getContext"
    let description = "Return the current user intent and the active subjects under discussion."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.recall, .summarize, .find, .read, .build],
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 100
        )
    }

    @Generable
    struct Arguments { }

    func call(arguments: Arguments) async throws -> String {
        let intent = await graph.currentIntent()
        let active = await graph.activeSubjects()
        let projection = ContextProjection(intent: intent, activeSubjects: active)
        let data = try JSONEncoder().encode(projection)
        let raw = String(data: data, encoding: .utf8) ?? "{}"
        return ProjectionBudget.bound(raw, characterBudget: ProjectionBudget.contextProjection)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/GetContextVerb.swift ConductorTests/GetContextVerbTests.swift
git commit -m "(service): add getContext memory verb"
```

---

### Task 16: getActions verb

**Files:**
- Create: `Conductor/Services/Verbs/GetActionsVerb.swift`
- Test: `ConductorTests/GetActionsVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("GetActionsVerb")
struct GetActionsVerbTests {
    private let pool = [
        AffordanceDescriptor(name: "Wiki", affordance: .init(
            verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
        ))
    ]

    @Test("Filter by status returns matching actions only")
    func filters() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["a"], answerShape: .citations, continuation: nil))
        let verb = GetActionsVerb(graph: graph)
        let all = try await verb.call(arguments: .init(status: nil))
        let pending = try await verb.call(arguments: .init(status: .pending))
        #expect(all.contains("pending"))
        #expect(pending.contains("pending"))
    }

    @Test("Affordance maps to .recall")
    func aff() {
        let verb = GetActionsVerb(graph: WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: []))
        #expect(verb.affordance.verbs.contains(.recall))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct GetActionsVerb: MemoryVerb {
    let graph: WorkingMemoryGraph

    let name = "getActions"
    let verbName = "getActions"
    let description = "List action nodes in the working memory graph, optionally filtered by status."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.recall, .summarize],
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 80
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "Filter by action status (pending, running, completed, failed, awaitingUser). If omitted, all actions are returned.")
        var status: ActionStatusArg?
    }

    @Generable
    enum ActionStatusArg: String, Codable {
        case pending, running, completed, failed, awaitingUser
        var asStatus: ActionStatus {
            switch self {
            case .pending: return .pending
            case .running: return .running
            case .completed: return .completed
            case .failed: return .failed
            case .awaitingUser: return .awaitingUser
            }
        }
    }

    func call(arguments: Arguments) async throws -> String {
        let all = await graph.allActions()
        let filtered = arguments.status.map { arg in all.filter { $0.status == arg.asStatus } } ?? all
        let projections = filtered.map {
            ActionProjection(id: $0.id, kind: $0.kind, goal: $0.goal, status: $0.status, atomCount: $0.atoms.count)
        }
        let data = try JSONEncoder().encode(projections)
        let raw = String(data: data, encoding: .utf8) ?? "[]"
        return ProjectionBudget.bound(raw, characterBudget: ProjectionBudget.actionsProjection, remainingHint: max(0, projections.count - 10))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/GetActionsVerb.swift ConductorTests/GetActionsVerbTests.swift
git commit -m "(service): add getActions memory verb"
```

---

### Task 17: append verb

**Files:**
- Create: `Conductor/Services/Verbs/AppendVerb.swift`
- Test: `ConductorTests/AppendVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("AppendVerb")
struct AppendVerbTests {
    private let pool = [
        AffordanceDescriptor(name: "Wiki", affordance: .init(
            verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
        ))
    ]

    @Test("Writes to an action's atoms when slot is .action")
    func actionAppend() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["a"], answerShape: .citations, continuation: nil))
        let actionID = await graph.allActions().first!.id
        let verb = AppendVerb(graph: graph, actionID: actionID)
        _ = try await verb.call(arguments: .init(slot: .action, content: "found 3 papers", sourceURL: nil, toolName: "PubMed"))
        let stored = await graph.action(for: actionID)?.atoms.count ?? 0
        #expect(stored == 1)
    }

    @Test("Writing with no bound actionID to slot .action is refused")
    func refusesUnbound() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        let verb = AppendVerb(graph: graph, actionID: nil)
        let receipt = try await verb.call(arguments: .init(slot: .action, content: "x", sourceURL: nil, toolName: nil))
        #expect(receipt.contains("refused"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct AppendVerb: MemoryVerb {
    let graph: WorkingMemoryGraph
    /// The Action this agent is authorized to write to, if any. Supplied at construction time.
    let actionID: UUID?

    let name = "append"
    let verbName = "append"
    let description = "Append an atom to the caller's Action node or to the running outcome."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: Set(IntentVerb.allCases),
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 100
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "Where to append: action (this agent's node) or outcome (shared running result)")
        var slot: AppendSlot
        @Guide(description: "The atom's text body")
        var content: String
        @Guide(description: "Optional source URL for citations")
        var sourceURL: String?
        @Guide(description: "Tool or subsystem name producing this atom")
        var toolName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let bounded = ProjectionBudget.bound(arguments.content, characterBudget: ProjectionBudget.atomContent)
        let source = arguments.sourceURL.flatMap(URL.init(string:))
        let atom = Atom.success(
            content: bounded,
            source: source,
            toolName: arguments.toolName ?? "unknown",
            timestamp: .now
        )
        let atomID = UUID()

        let receipt: AppendReceipt
        switch arguments.slot {
        case .action:
            guard let actionID else {
                receipt = .refused(reason: "No bound Action for this agent; slot .action is unavailable.")
                break
            }
            await graph.append(atom: atom, to: actionID)
            receipt = .accepted(atomID: atomID)
        case .outcome:
            await graph.appendOutcome(atom)
            receipt = .accepted(atomID: atomID)
        }

        let data = try JSONEncoder().encode(receipt)
        return String(data: data, encoding: .utf8) ?? "{\"error\":\"encode\"}"
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/AppendVerb.swift ConductorTests/AppendVerbTests.swift
git commit -m "(service): add append memory verb with scoped write discipline"
```

---

### Task 18: findRelated verb

**Files:**
- Create: `Conductor/Services/Verbs/FindRelatedVerb.swift`
- Test: `ConductorTests/FindRelatedVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("FindRelatedVerb")
struct FindRelatedVerbTests {
    private let pool = [
        AffordanceDescriptor(name: "Wiki", affordance: .init(
            verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
        ))
    ]

    @Test("Matches an atom in the outcome by case-insensitive substring")
    func matchesOutcome() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: nil))
        await graph.appendOutcome(.success(content: "CRISPR cas9 editing", source: nil, toolName: "Wiki", timestamp: .now))
        let verb = FindRelatedVerb(graph: graph)
        let result = try await verb.call(arguments: .init(keyword: "crispr"))
        #expect(result.contains("CRISPR") || result.contains("cas9"))
    }

    @Test("Empty result yields []")
    func empty() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        let verb = FindRelatedVerb(graph: graph)
        let result = try await verb.call(arguments: .init(keyword: "ghost"))
        #expect(result == "[]")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct FindRelatedVerb: MemoryVerb {
    let graph: WorkingMemoryGraph

    let name = "findRelated"
    let verbName = "findRelated"
    let description = "Search the running outcome and archived subjects for entries matching a keyword."

    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.recall, .find],
            subjects: Set(IntentSubject.allCases),
            answerShapes: Set(AnswerShape.allCases),
            priority: 90
        )
    }

    @Generable
    struct Arguments {
        @Guide(description: "The keyword to search for, case-insensitive substring")
        var keyword: String
    }

    func call(arguments: Arguments) async throws -> String {
        let needle = arguments.keyword.lowercased()
        let outcome = await graph.currentOutcome()
        let archived = await graph.archivedSubjects()

        var hits: [AtomProjection] = []
        for atom in outcome {
            switch atom {
            case let .success(content, source, toolName, timestamp):
                if content.lowercased().contains(needle) {
                    hits.append(AtomProjection(actionID: nil, subjectID: nil, preview: content, source: source, toolName: toolName, timestamp: timestamp))
                }
            case let .note(text, timestamp):
                if text.lowercased().contains(needle) {
                    hits.append(AtomProjection(actionID: nil, subjectID: nil, preview: text, source: nil, toolName: nil, timestamp: timestamp))
                }
            case .error:
                continue
            }
        }
        for entry in archived where entry.name.lowercased().contains(needle) {
            hits.append(AtomProjection(actionID: nil, subjectID: entry.id, preview: entry.name, source: nil, toolName: nil, timestamp: entry.introducedAt))
        }

        let data = try JSONEncoder().encode(hits)
        let raw = String(data: data, encoding: .utf8) ?? "[]"
        return ProjectionBudget.bound(raw, characterBudget: ProjectionBudget.findRelatedResults)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/FindRelatedVerb.swift ConductorTests/FindRelatedVerbTests.swift
git commit -m "(service): add findRelated memory verb"
```

---

## Phase 7 — Refactor Domain Tools

### Task 19: Refactor AgentTool protocol

**Files:**
- Modify: `Conductor/Tools/AgentTool.swift`

The existing protocol requires `purpose`. The new one requires `affordance` via `AffordanceBearing`, keeping `friendlyName`. This is a breaking change compiled against: all tools in Phase 7 Task 20 get updated in the same PR; old `AgentPurpose` stays in-tree until Phase 10.

- [ ] **Step 1: Write the failing test**

No test needed — the compile failures across tool files are the test. Proceed directly to implementation; the next task will restore compilation.

- [ ] **Step 2: Write the minimal implementation**

Replace the body of `Conductor/Tools/AgentTool.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol AgentTool: Tool, AffordanceBearing {
    var friendlyName: String { get }
}
```

- [ ] **Step 3: Do not commit yet**

Compilation will fail until Task 20 lands. Carry the uncommitted change into the next task.

---

### Task 20: Migrate all domain tools to ToolAffordance

**Files:**
- Modify: `Conductor/Tools/WikipediaSearchTool.swift`
- Modify: `Conductor/Tools/PubMedSearchTool.swift`
- Modify: `Conductor/Tools/ArXivSearchTool.swift`
- Modify: `Conductor/Tools/SemanticScholarSearchTool.swift`
- Modify: `Conductor/Tools/OpenAlexSearchTool.swift`
- Modify: `Conductor/Tools/CrossRefSearchTool.swift`
- Modify: `Conductor/Tools/WebReaderTool.swift`
- Modify: `Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift`
- Test: `ConductorTests/ToolAffordanceWiringTests.swift`

Per-tool: remove `let purpose: AgentPurpose = ...` and add a computed `affordance: ToolAffordance` using the seed mapping from the spec.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@available(iOS 19.0, macOS 26.0, *)
@Suite("Tool affordance wiring")
struct ToolAffordanceWiringTests {
    @Test("WikipediaSearchTool declares overview + encyclopedic")
    func wikipedia() {
        let t = WikipediaSearchTool()
        #expect(t.affordance.verbs.contains(.find))
        #expect(t.affordance.subjects.contains(.encyclopedic))
        #expect(t.affordance.answerShapes.contains(.overview))
    }

    @Test("PubMedSearchTool declares biomedical citations")
    func pubmed() {
        let t = PubMedSearchTool()
        #expect(t.affordance.subjects.contains(.biomedical))
        #expect(t.affordance.answerShapes.contains(.citations))
    }

    @Test("WebReaderTool declares webpage + summary/direct")
    func web() {
        let t = WebReaderTool()
        #expect(t.affordance.verbs.contains(.read))
        #expect(t.affordance.subjects.contains(.webpage))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: FAIL — build errors plus assertion failures.

- [ ] **Step 3: Write the minimal implementation**

In each tool, replace `let purpose: AgentPurpose = ...` with an affordance. Example for `WikipediaSearchTool.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct WikipediaSearchTool: AgentTool {
    let name = "searchWikipedia"
    let description = "Search Wikipedia for general knowledge, overviews, historical context, and encyclopedic information."
    let friendlyName = "Wikipedia"
    var affordance: ToolAffordance {
        ToolAffordance(
            verbs: [.find, .summarize],
            subjects: [.encyclopedic],
            answerShapes: [.overview, .summary, .direct],
            priority: 5
        )
    }
    // ... existing body unchanged
}
```

Apply the seed mapping from the spec for each tool:

| Tool | verbs | subjects | answerShapes | priority |
|---|---|---|---|---|
| `WikipediaSearchTool` | `[.find, .summarize]` | `[.encyclopedic]` | `[.overview, .summary, .direct]` | 5 |
| `PubMedSearchTool` | `[.find]` | `[.academic, .biomedical]` | `[.citations, .direct]` | 10 |
| `ArXivSearchTool` | `[.find]` | `[.preprint, .academic]` | `[.citations, .direct]` | 10 |
| `SemanticScholarSearchTool` | `[.find]` | `[.academic]` | `[.citations, .direct]` | 10 |
| `OpenAlexSearchTool` | `[.find]` | `[.academic]` | `[.citations, .direct]` | 9 |
| `CrossRefSearchTool` | `[.find]` | `[.academic]` | `[.citations, .direct]` | 8 |
| `WebReaderTool` | `[.read, .summarize]` | `[.webpage]` | `[.summary, .direct]` | 10 |
| `BuildAutomatorWorkflowTool` | `[.build]` | `[.workflow]` | `[.workflow]` | 10 |

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test ...`
Expected: PASS for `ToolAffordanceWiringTests`. Existing `AgentPurposeTests` will fail in later phases once `AgentPurpose` is removed; for now they still compile against the old enum which is still in-tree.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/ Conductor/Tools/Automator/ ConductorTests/ToolAffordanceWiringTests.swift
git commit -m "(tools): migrate all domain tools from AgentPurpose to ToolAffordance"
```

---

## Phase 8 — Sessions: Intent and Synthesis

### Task 21: Intent session

**Files:**
- Create: `Conductor/Services/IntentSession.swift`
- Test: `ConductorTests/IntentSessionTests.swift`

This task wraps the LLM call that parses or updates an intent. `parseIntent` runs on the first turn (intent stack empty); `updateIntent` runs on subsequent turns and is given `getContext` so it can reference prior work.

Because the on-device model isn't available in unit tests, the session exposes a protocol-based seam so tests can stub it.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("IntentSession")
struct IntentSessionTests {
    struct Stub: IntentSessionRunning {
        let output: LanguageIntentQuery
        func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery { output }
    }

    @Test("parseIntent uses the stub runner and appends to the graph")
    func parseIntent() async throws {
        let graph = WorkingMemoryGraph(toolDescriptors: [
            AffordanceDescriptor(name: "Wiki", affordance: .init(verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview], priority: 1))
        ], verbDescriptors: [])
        let stub = Stub(output: LanguageIntentQuery(verbs: [.find], subjects: ["crispr"], answerShape: .overview, continuation: nil))
        let session = IntentSession(runner: stub, graph: graph)
        try await session.handle(message: "tell me about crispr")
        let intent = await graph.currentIntent()
        #expect(intent?.verbs == [.find])
        #expect(intent?.subjects == ["crispr"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol IntentSessionRunning: Sendable {
    func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery
}

@available(iOS 19.0, macOS 26.0, *)
struct IntentSession {
    let runner: any IntentSessionRunning
    let graph: WorkingMemoryGraph

    func handle(message: String) async throws {
        let turn = await graph.currentTurn()
        let contextVerb: GetContextVerb? = (turn == 0) ? nil : GetContextVerb(graph: graph)
        let intent = try await runner.extract(message: message, contextVerb: contextVerb)
        await graph.append(intent: intent)
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct LiveIntentRunner: IntentSessionRunning {
    static let parseInstructions = """
    You translate the user's message into a structured LanguageIntentQuery.
    Do not answer the user. Do not speculate. Only emit the typed value.
    Pick verbs from: find, summarize, recall, build, read.
    Pick answerShape from: overview, summary, citations, workflow, direct.
    If this message continues a prior turn, set continuation accordingly.
    """

    func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery {
        let tools: [any Tool] = contextVerb.map { [$0 as any Tool] } ?? []
        let session = LanguageModelSession(
            tools: tools,
            instructions: Self.parseInstructions
        )
        let response = try await session.respond(to: message, generating: LanguageIntentQuery.self)
        return response.content
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/IntentSession.swift ConductorTests/IntentSessionTests.swift
git commit -m "(service): add IntentSession producing LanguageIntentQuery via stateless inference"
```

---

### Task 22: Generic Agent actor

**Files:**
- Create: `Conductor/Services/Agent.swift`
- Test: `ConductorTests/AgentTests.swift`

The `Agent` is the one sub-agent primitive. It is given verbs, tools, a goal, and a graph handle. Its run flow:
1. Mark Action `.running`
2. Construct a disposable `LanguageModelSession` with `verbs + tools`
3. Prompt the session with the goal
4. On completion or error, write the appropriate atom and mark Action terminal

For tests, `AgentRunning` provides a seam.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("Agent")
struct AgentTests {
    struct Stub: AgentRunning {
        let output: String
        let shouldThrow: Bool
        func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String {
            if shouldThrow { throw NSError(domain: "test", code: 1) }
            return output
        }
    }

    private let pool = [
        AffordanceDescriptor(name: "Wiki", affordance: .init(
            verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview, .citations], priority: 1
        ))
    ]

    @Test("Success completes the Action and appends a success atom")
    func success() async {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: nil))
        let action = await graph.allActions().first!
        let agent = Agent(
            actionID: action.id, goal: "g",
            verbs: [], tools: [], graph: graph,
            runner: Stub(output: "found 3 papers", shouldThrow: false)
        )
        await agent.run()
        let refreshed = await graph.action(for: action.id)
        #expect(refreshed?.status == .completed)
        #expect(refreshed?.atoms.count == 1)
    }

    @Test("Runner failure marks Action .failed and appends an error atom")
    func failure() async {
        let graph = WorkingMemoryGraph(toolDescriptors: pool, verbDescriptors: [])
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .citations, continuation: nil))
        let action = await graph.allActions().first!
        let agent = Agent(
            actionID: action.id, goal: "g",
            verbs: [], tools: [], graph: graph,
            runner: Stub(output: "", shouldThrow: true)
        )
        await agent.run()
        let refreshed = await graph.action(for: action.id)
        #expect(refreshed?.status == .failed)
        #expect(refreshed?.atoms.count == 1)
        if case .error = refreshed!.atoms[0] { #expect(true) } else { Issue.record("expected error atom") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol AgentRunning: Sendable {
    func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String
}

@available(iOS 19.0, macOS 26.0, *)
actor Agent {
    let actionID: UUID
    let goal: String
    let verbs: [any MemoryVerb]
    let tools: [any AgentTool]
    let graph: WorkingMemoryGraph
    let runner: any AgentRunning

    init(
        actionID: UUID,
        goal: String,
        verbs: [any MemoryVerb],
        tools: [any AgentTool],
        graph: WorkingMemoryGraph,
        runner: any AgentRunning
    ) {
        self.actionID = actionID
        self.goal = goal
        self.verbs = verbs
        self.tools = tools
        self.graph = graph
        self.runner = runner
    }

    func run() async {
        await graph.updateStatus(.running, for: actionID)
        do {
            let content = try await runner.run(goal: goal, verbs: verbs, tools: tools)
            let bounded = ProjectionBudget.bound(content, characterBudget: ProjectionBudget.atomContent)
            let atom = Atom.success(content: bounded, source: nil, toolName: tools.first?.friendlyName ?? "agent", timestamp: .now)
            await graph.append(atom: atom, to: actionID)
            await graph.updateStatus(.completed, for: actionID)
        } catch {
            let err = ErrorAtom(
                actionID: actionID,
                toolName: nil,
                kind: classify(error),
                message: error.localizedDescription,
                timestamp: .now
            )
            await graph.append(atom: .error(err), to: actionID)
            await graph.updateStatus(.failed, for: actionID)
        }
    }

    private func classify(_ error: Error) -> ErrorKind {
        let s = String(describing: error).lowercased()
        if s.contains("unsafe") { return .unsafeContent }
        if s.contains("timeout") || s.contains("timed out") { return .timeout }
        if s.contains("no results") { return .noResults }
        if s.contains("network") || s.contains("internet") { return .networkError }
        return .unknown
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct LiveAgentRunner: AgentRunning {
    func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String {
        let allTools: [any Tool] = (verbs as [any Tool]) + (tools as [any Tool])
        let session = LanguageModelSession(
            tools: allTools,
            instructions: """
            Your goal: \(goal)
            You have memory verbs for reading the graph and appending results, and domain tools for calling external sources.
            Read only what you need, call tools, and append a concise atom when done.
            """
        )
        var content = ""
        for try await partial in session.streamResponse(to: goal) {
            content = partial.content
        }
        return content
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Agent.swift ConductorTests/AgentTests.swift
git commit -m "(service): add generic Agent primitive with pluggable runner"
```

---

### Task 23: composeResponse synthesis session

**Files:**
- Create: `Conductor/Services/ComposeResponseSession.swift`
- Test: `ConductorTests/ComposeResponseSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ComposeResponseSession")
struct ComposeResponseSessionTests {
    struct Stub: ComposeResponseRunning {
        func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse {
            ComposedResponse(prose: "synthesized: \(intent.subjects.joined(separator: ", "))", sections: nil)
        }
    }

    @Test("Composes prose from intent + RAG projection")
    func composes() async throws {
        let session = ComposeResponseSession(runner: Stub())
        let intent = LanguageIntentQuery(verbs: [.summarize], subjects: ["crispr"], answerShape: .summary, continuation: nil)
        let outcome: [Atom] = [.success(content: "edits DNA", source: nil, toolName: "PubMed", timestamp: .now)]
        let response = try await session.compose(intent: intent, outcome: outcome)
        #expect(response.prose.contains("crispr"))
    }

    @Test("RAG projection is bounded by ProjectionBudget")
    func bounded() {
        let giant = Array(repeating: Atom.success(content: String(repeating: "x", count: 1000), source: nil, toolName: "T", timestamp: .now), count: 20)
        let projection = ComposeResponseSession.ragProjection(from: giant)
        #expect(projection.count <= ProjectionBudget.composeResponseProjection + 100)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct ComposedResponse: Sendable, Codable {
    @Guide(description: "The main prose response to the user")
    var prose: String
    @Guide(description: "Optional section breakdown")
    var sections: [Section]?

    @Generable
    struct Section: Codable, Sendable {
        @Guide(description: "Heading for this section")
        var heading: String
        @Guide(description: "Content under this heading")
        var content: String
    }
}

@available(iOS 19.0, macOS 26.0, *)
protocol ComposeResponseRunning: Sendable {
    func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse
}

@available(iOS 19.0, macOS 26.0, *)
struct ComposeResponseSession {
    let runner: any ComposeResponseRunning

    func compose(intent: LanguageIntentQuery, outcome: [Atom]) async throws -> ComposedResponse {
        let rag = Self.ragProjection(from: outcome)
        return try await runner.compose(intent: intent, ragBlock: rag)
    }

    static func ragProjection(from outcome: [Atom]) -> String {
        let lines = outcome.compactMap { atom -> String? in
            switch atom {
            case let .success(content, source, toolName, _):
                if let source { return "[\(toolName) · \(source.absoluteString)] \(content)" }
                return "[\(toolName)] \(content)"
            case let .note(text, _): return "[note] \(text)"
            case .error: return nil
            }
        }
        return ProjectionBudget.bound(
            lines.joined(separator: "\n---\n"),
            characterBudget: ProjectionBudget.composeResponseProjection
        )
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct LiveComposeRunner: ComposeResponseRunning {
    func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse {
        let session = LanguageModelSession(
            tools: [],
            instructions: """
            You are synthesizing a response. You do not have memory verbs or domain tools.
            The user asked for: \(intent.subjects.joined(separator: ", ")).
            AnswerShape: \(intent.answerShape.rawValue).
            Use the following RAG block as your only source of truth:
            ---
            \(ragBlock)
            ---
            Produce a ComposedResponse. Be concise. Cite by tool name when relevant.
            """
        )
        let response = try await session.respond(to: "Synthesize.", generating: ComposedResponse.self)
        return response.content
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/ComposeResponseSession.swift ConductorTests/ComposeResponseSessionTests.swift
git commit -m "(service): add composeResponse synthesis session with RAG projection"
```

---

## Phase 9 — Orchestrator Shell, Persistence, UI Bridge

### Task 24: GraphProxy

**Files:**
- Create: `Conductor/Services/GraphProxy.swift`
- Test: `ConductorTests/GraphProxyTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("GraphProxy")
@MainActor
struct GraphProxyTests {
    @Test("Proxy reflects the graph's current intent after an append")
    func reflectsIntent() async {
        let graph = WorkingMemoryGraph(toolDescriptors: [
            AffordanceDescriptor(name: "Wiki", affordance: .init(verbs: [.find], subjects: [.encyclopedic], answerShapes: [.overview], priority: 1))
        ], verbDescriptors: [])
        let proxy = GraphProxy(graph: graph)
        await graph.append(intent: LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .overview, continuation: nil))
        // Let the subscription drain
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(proxy.intent?.verbs == [.find])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

@available(iOS 19.0, macOS 26.0, *)
@MainActor
@Observable
final class GraphProxy {
    private(set) var intent: LanguageIntentQuery?
    private(set) var subjects: [SubjectStack.Entry] = []
    private(set) var actions: [ActionNode] = []
    private(set) var outcome: [Atom] = []

    private let graph: WorkingMemoryGraph
    private var subscribeTask: Task<Void, Never>?

    init(graph: WorkingMemoryGraph) {
        self.graph = graph
        self.subscribeTask = Task { [weak self] in
            guard let self else { return }
            // Prime
            await self.refreshAll()
            for await kind in graph.changes {
                if Task.isCancelled { return }
                switch kind {
                case .intent:  self.intent = await graph.currentIntent()
                case .subject: self.subjects = await graph.activeSubjects()
                case .actions: self.actions = await graph.allActions()
                case .outcome: self.outcome = await graph.currentOutcome()
                }
            }
        }
    }

    deinit { subscribeTask?.cancel() }

    private func refreshAll() async {
        self.intent = await graph.currentIntent()
        self.subjects = await graph.activeSubjects()
        self.actions = await graph.allActions()
        self.outcome = await graph.currentOutcome()
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/GraphProxy.swift ConductorTests/GraphProxyTests.swift
git commit -m "(service): add GraphProxy bridging the graph actor to SwiftUI"
```

---

### Task 25: Chat snapshot persistence

**Files:**
- Modify: `Conductor/ContentView.swift` (extend `ChatManager`)
- Test: `ConductorTests/ChatManagerSnapshotTests.swift`

`ChatManager` gains a `chatSnapshots: [UUID: Data]` store keyed by chat id. The stored value is JSON-encoded `GraphSnapshot`. Messages remain untouched.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("ChatManager snapshot persistence")
struct ChatManagerSnapshotTests {
    @Test("Saving and loading a snapshot round-trips")
    @MainActor
    func roundTrip() throws {
        let manager = ChatManager()
        let chat = manager.createNewChat()
        let snap = GraphSnapshot(
            intentStack: [LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)],
            subjects: SubjectStack(),
            actions: [],
            outcome: []
        )
        manager.saveSnapshot(snap, for: chat.id)
        let loaded = manager.loadSnapshot(for: chat.id)
        #expect(loaded?.intentStack.count == 1)
    }

    @Test("Loading a snapshot with a mismatched schemaVersion returns nil")
    @MainActor
    func schemaMismatch() throws {
        let manager = ChatManager()
        let chat = manager.createNewChat()
        let old = GraphSnapshot(
            schemaVersion: 999,
            intentStack: [], subjects: SubjectStack(), actions: [], outcome: []
        )
        manager.saveSnapshotRaw(try JSONEncoder().encode(old), for: chat.id)
        let loaded = manager.loadSnapshot(for: chat.id)
        #expect(loaded == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

Add to `ChatManager`:

```swift
    private let snapshotsKey = "conductor.savedSnapshots"
    private var chatSnapshots: [UUID: Data] = [:]

    func saveSnapshot(_ snapshot: GraphSnapshot, for chatID: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        chatSnapshots[chatID] = data
        persistSnapshots()
    }

    func saveSnapshotRaw(_ data: Data, for chatID: UUID) {
        chatSnapshots[chatID] = data
        persistSnapshots()
    }

    func loadSnapshot(for chatID: UUID) -> GraphSnapshot? {
        guard let data = chatSnapshots[chatID] else { return nil }
        guard let decoded = try? JSONDecoder().decode(GraphSnapshot.self, from: data) else {
            // Could not decode — treat as schema-mismatch / corrupt; return nil.
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
```

Update `init()` to call `loadSnapshots()` after `loadChats()`. In `deleteChat`, also `chatSnapshots.removeValue(forKey: chat.id)` and call `persistSnapshots()`.

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/ContentView.swift ConductorTests/ChatManagerSnapshotTests.swift
git commit -m "(model): persist GraphSnapshot per chat with schema version gate"
```

---

### Task 26: New `Conductor` orchestrator shell

**Files:**
- Create: `Conductor/Services/Conductor.swift`
- Test: `ConductorTests/ConductorShellTests.swift`

This replaces `ConductorOrchestrator`. Named `Conductor` to match the design doc; the old class will be deleted in Phase 10. The new shell:
1. Holds a `WorkingMemoryGraph`.
2. Runs `IntentSession.handle(message:)`.
3. Dispatches ready Actions via generic `Agent` instances in parallel.
4. When all Actions are terminal, fires `composeResponse` for `.overview`/`.summary` shapes.
5. Returns a `TurnResult` containing the assistant string and a count of failures.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("Conductor shell")
struct ConductorShellTests {
    struct IntentStub: IntentSessionRunning {
        let out: LanguageIntentQuery
        func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery { out }
    }
    struct AgentStub: AgentRunning {
        let body: String
        func run(goal: String, verbs: [any MemoryVerb], tools: [any AgentTool]) async throws -> String { body }
    }
    struct ComposeStub: ComposeResponseRunning {
        func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse {
            ComposedResponse(prose: "composed from \(ragBlock.prefix(20))", sections: nil)
        }
    }

    private func sampleTools() -> [any AgentTool] { [WikipediaSearchTool()] }

    @Test("Deterministic answer shape produces a stitched response")
    func deterministicShape() async throws {
        let conductor = Conductor(
            tools: sampleTools(),
            intentRunner: IntentStub(out: LanguageIntentQuery(
                verbs: [.find], subjects: ["crispr"],
                answerShape: .citations, continuation: nil
            )),
            agentRunner: AgentStub(body: "found: crispr paper"),
            composeRunner: ComposeStub()
        )
        let result = try await conductor.handle(message: "find crispr papers")
        #expect(result.text.contains("crispr paper"))
        #expect(result.failureCount == 0)
    }

    @Test("Overview answer shape routes through synthesis")
    func synthesisShape() async throws {
        let conductor = Conductor(
            tools: sampleTools(),
            intentRunner: IntentStub(out: LanguageIntentQuery(
                verbs: [.find, .summarize], subjects: ["crispr"],
                answerShape: .overview, continuation: nil
            )),
            agentRunner: AgentStub(body: "edits DNA"),
            composeRunner: ComposeStub()
        )
        let result = try await conductor.handle(message: "overview of crispr")
        #expect(result.text.starts(with: "composed"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

@available(iOS 19.0, macOS 26.0, *)
struct TurnResult: Sendable {
    let text: String
    let failureCount: Int
    let sources: [ToolSource]
}

@available(iOS 19.0, macOS 26.0, *)
@MainActor
@Observable
final class Conductor {
    let tools: [any AgentTool]
    private(set) var graph: WorkingMemoryGraph
    private(set) var proxy: GraphProxy

    private let intentRunner: any IntentSessionRunning
    private let agentRunner: any AgentRunning
    private let composeRunner: any ComposeResponseRunning

    init(
        tools: [any AgentTool],
        snapshot: GraphSnapshot? = nil,
        intentRunner: any IntentSessionRunning = LiveIntentRunner(),
        agentRunner: any AgentRunning = LiveAgentRunner(),
        composeRunner: any ComposeResponseRunning = LiveComposeRunner()
    ) {
        self.tools = tools
        let toolDescriptors = tools.map { AffordanceDescriptor(name: $0.friendlyName, affordance: $0.affordance) }
        let verbDescriptorNames = ["getContext", "getActions", "append", "findRelated"]
        // Verb descriptors: constructed by querying each verb's affordance through a dummy instance.
        // We need an instance to read the affordance, but verbs hold a graph ref — break the cycle by
        // constructing descriptors from static affordance builders below.
        let verbDescriptors = Self.verbDescriptors()
        _ = verbDescriptorNames // silence

        let g: WorkingMemoryGraph
        if let snapshot {
            g = WorkingMemoryGraph.restore(from: snapshot, toolDescriptors: toolDescriptors, verbDescriptors: verbDescriptors)
        } else {
            g = WorkingMemoryGraph(toolDescriptors: toolDescriptors, verbDescriptors: verbDescriptors)
        }
        self.graph = g
        self.proxy = GraphProxy(graph: g)
        self.intentRunner = intentRunner
        self.agentRunner = agentRunner
        self.composeRunner = composeRunner
    }

    private static func verbDescriptors() -> [AffordanceDescriptor] {
        let dummyGraph = WorkingMemoryGraph(toolDescriptors: [], verbDescriptors: [])
        let verbs: [any MemoryVerb] = [
            GetContextVerb(graph: dummyGraph),
            GetActionsVerb(graph: dummyGraph),
            AppendVerb(graph: dummyGraph, actionID: nil),
            FindRelatedVerb(graph: dummyGraph),
        ]
        return verbs.map { AffordanceDescriptor(name: $0.verbName, affordance: $0.affordance) }
    }

    func handle(message: String) async throws -> TurnResult {
        // 1. Intent
        let session = IntentSession(runner: intentRunner, graph: graph)
        try await session.handle(message: message)

        // 2. Dispatch until all Actions are terminal or awaitingUser
        try await dispatchLoop()

        // 3. Compose response
        let intent = await graph.currentIntent()!
        let actions = await graph.allActions()
        let failures = actions.filter { $0.status == .failed }.count
        let text = try await buildText(intent: intent, actions: actions)
        let sources = actions.flatMap { action in
            action.atoms.compactMap { atom -> ToolSource? in
                if case let .success(_, source, toolName, _) = atom, let source {
                    return ToolSource(title: toolName, url: source.absoluteString)
                }
                return nil
            }
        }
        return TurnResult(text: text, failureCount: failures, sources: sources)
    }

    func snapshot() async -> GraphSnapshot {
        await graph.snapshot()
    }

    // MARK: - Private

    private func dispatchLoop() async throws {
        while true {
            let actions = await graph.allActions()
            let ready = actions.filter { $0.status == .pending && $0.kind == .work }
            if ready.isEmpty { break }

            await withTaskGroup(of: Void.self) { [self] group in
                for action in ready {
                    group.addTask { await self.runAgent(for: action) }
                }
            }
        }
    }

    private func runAgent(for action: ActionNode) async {
        let verbInstances = resolveVerbs(names: action.assignedVerbNames, actionID: action.id)
        let toolInstances = tools.filter { action.assignedToolNames.contains($0.friendlyName) }
        let agent = Agent(
            actionID: action.id,
            goal: action.goal,
            verbs: verbInstances,
            tools: toolInstances,
            graph: graph,
            runner: agentRunner
        )
        await agent.run()
    }

    private func resolveVerbs(names: [String], actionID: UUID) -> [any MemoryVerb] {
        names.compactMap { name in
            switch name {
            case "getContext":  return GetContextVerb(graph: graph)
            case "getActions":  return GetActionsVerb(graph: graph)
            case "append":      return AppendVerb(graph: graph, actionID: actionID)
            case "findRelated": return FindRelatedVerb(graph: graph)
            default:            return nil
            }
        }
    }

    private func buildText(intent: LanguageIntentQuery, actions: [ActionNode]) async throws -> String {
        switch intent.answerShape {
        case .overview, .summary:
            let outcome = await graph.currentOutcome()
            let response = try await ComposeResponseSession(runner: composeRunner).compose(intent: intent, outcome: outcome)
            return response.prose
        case .citations, .workflow, .direct:
            return stitchDeterministic(actions: actions)
        }
    }

    private func stitchDeterministic(actions: [ActionNode]) -> String {
        let lines = actions.flatMap { action -> [String] in
            action.atoms.compactMap { atom in
                if case let .success(content, _, _, _) = atom { return content }
                return nil
            }
        }
        // Clarifications surface directly as the response.
        let clarifications = actions.filter { $0.kind == .clarification }.map(\.goal)
        if !clarifications.isEmpty { return clarifications.joined(separator: "\n\n") }
        return lines.joined(separator: "\n\n")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Conductor.swift ConductorTests/ConductorShellTests.swift
git commit -m "(service): add Conductor shell wiring intent, dispatch, and synthesis"
```

---

## Phase 10 — Wire UI, Delete Legacy

### Task 27: Wire `ContentView` to the new `Conductor`

**Files:**
- Modify: `Conductor/ContentView.swift`

This swaps the `ConductorOrchestrator`-based chat detail view for one that uses the new `Conductor`. The narration UI is temporarily replaced by a thin action list sourced from `GraphProxy` — full narration view replacement lands with Task 29.

- [ ] **Step 1: Edit `ChatDetailView`**

Replace the `@State private var orchestrator: ConductorOrchestrator` with a `@State private var conductor: Conductor`, initialize with the same tools array, and restore a snapshot if present:

```swift
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
    // body continues — replace the `NarrationGroupView(events: orchestrator.narrationEvents)` block with a lightweight
    // `ActiveActionsView(actions: conductor.proxy.actions.filter { $0.status == .running })` placeholder view.
    // `sendMessage` body is rewritten below.

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
                sources: result.sources,
                narrationLog: []
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
```

- [ ] **Step 2: Add the `ActiveActionsView` stub**

Place it just below `ChatDetailView` in `ContentView.swift`:

```swift
@available(iOS 19.0, macOS 26.0, *)
struct ActiveActionsView: View {
    let actions: [ActionNode]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(actions) { action in
                HStack {
                    ProgressView().controlSize(.small)
                    Text(action.goal).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }
}
```

- [ ] **Step 3: Remove references to `ConductorOrchestrator`, `NarrationGroupView`, and `TaskGraphSheet` from this file**

Delete the `if isResponding { NarrationGroupView(events: orchestrator.narrationEvents) }` block and any `.sheet` presenting `TaskGraphSheet`. Replace with `ActiveActionsView(actions: conductor.proxy.actions.filter { $0.status == .running })` gated by `isResponding`.

- [ ] **Step 4: Run the full test suite to verify nothing broke**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor`
Expected: PASS for all new tests; legacy tests that reference `ConductorOrchestrator`/`TaskGraph` still exist and may fail. If they do, note which ones and proceed — Task 28 deletes them.

- [ ] **Step 5: Commit**

```bash
git add Conductor/ContentView.swift
git commit -m "(views): wire ChatDetailView to the new Conductor shell with snapshot restore"
```

---

### Task 28: Delete legacy orchestration stack

**Files:**
- Delete: `Conductor/Services/ConductorOrchestrator.swift`
- Delete: `Conductor/Services/TaskGraph.swift`
- Delete: `Conductor/Services/SubAgent.swift`
- Delete: `Conductor/Models/AgentPurpose.swift`
- Delete: `Conductor/Models/ExtractedIntent.swift`
- Delete: `Conductor/Models/LogEntry.swift`
- Delete: `Conductor/Models/NarrationEvent.swift`
- Delete: `Conductor/Models/StitchedResponse.swift`
- Delete: `Conductor/Views/NarrationGroupView.swift`
- Delete: `Conductor/Views/TaskGraphSheet.swift`
- Delete: `ConductorTests/AgentPurposeTests.swift`
- Delete: `ConductorTests/ConductorOrchestratorTests.swift`
- Delete: `ConductorTests/TaskGraphTests.swift`
- Delete: `ConductorTests/StitchedResponseTests.swift`
- Modify: `Conductor/ContentView.swift` — remove `narrationLog` field from `Message` (and its decode branch), or leave it as a `[NarrationEvent]` typedef if kept for back-compat. For v1 in-place, remove entirely.

Also remove the `chunked(into:)` extension from the old orchestrator file (it was defined there). Nothing in the new code uses it.

- [ ] **Step 1: Delete the files**

```bash
git rm \
  Conductor/Services/ConductorOrchestrator.swift \
  Conductor/Services/TaskGraph.swift \
  Conductor/Services/SubAgent.swift \
  Conductor/Models/AgentPurpose.swift \
  Conductor/Models/ExtractedIntent.swift \
  Conductor/Models/LogEntry.swift \
  Conductor/Models/NarrationEvent.swift \
  Conductor/Models/StitchedResponse.swift \
  Conductor/Views/NarrationGroupView.swift \
  Conductor/Views/TaskGraphSheet.swift \
  ConductorTests/AgentPurposeTests.swift \
  ConductorTests/ConductorOrchestratorTests.swift \
  ConductorTests/TaskGraphTests.swift \
  ConductorTests/StitchedResponseTests.swift
```

Also remove their entries from `Conductor.xcodeproj/project.pbxproj` so the targets don't reference missing files. Use Xcode's UI ("Remove Reference" was already implied by `git rm`, but the pbxproj lines need hand-editing or a second pass in Xcode).

- [ ] **Step 2: Strip `narrationLog` from `Message` in `ContentView.swift`**

Remove `var narrationLog: [NarrationEvent]` and its encode/decode path, plus the `MessageBubbleView` block that reads `message.narrationLog`.

- [ ] **Step 3: Build**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor`
Expected: clean build.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor`
Expected: PASS across the board.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "(cleanup): remove ConductorOrchestrator, TaskGraph, SubAgent, and purpose-era types"
```

---

### Task 29: Action-group UI cell

**Files:**
- Create: `Conductor/Views/ActionGroupView.swift`
- Modify: `Conductor/ContentView.swift`

Replace the stub `ActiveActionsView` with a proper group view that observes `conductor.proxy.actions` and groups by `ActionStatus`. This preserves the spirit of the old narration cells without the purpose color stripes.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI

@available(iOS 19.0, macOS 26.0, *)
struct ActionGroupView: View {
    let actions: [ActionNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(groups, id: \.status) { group in
                Text(group.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(group.actions) { action in
                    HStack(spacing: 8) {
                        statusIcon(action.status)
                        Text(actionSummary(action))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private struct Group { let status: ActionStatus; let actions: [ActionNode] }

    private var groups: [Group] {
        let order: [ActionStatus] = [.running, .pending, .completed, .failed, .awaitingUser]
        return order.compactMap { status in
            let bucket = actions.filter { $0.status == status }
            return bucket.isEmpty ? nil : Group(status: status, actions: bucket)
        }
    }

    private func actionSummary(_ action: ActionNode) -> String {
        let tools = action.assignedToolNames.joined(separator: ", ")
        if tools.isEmpty { return action.goal }
        return "\(action.goal) — \(tools)"
    }

    @ViewBuilder
    private func statusIcon(_ status: ActionStatus) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .awaitingUser: Image(systemName: "questionmark.circle").foregroundStyle(.orange)
        }
    }
}

private extension ActionStatus {
    var label: String {
        switch self {
        case .running: return "Running"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .awaitingUser: return "Awaiting your reply"
        }
    }
}
```

- [ ] **Step 2: Swap `ActiveActionsView` for `ActionGroupView`**

In `ContentView.swift`, replace the placeholder cell with `ActionGroupView(actions: conductor.proxy.actions)` inside the `isResponding` branch. Remove `ActiveActionsView`.

- [ ] **Step 3: Build and run the app**

Run the app on macOS or iOS Simulator. Send a message. Watch action groups update.

Expected: actions appear as they start, progress, and complete. If the UI doesn't update, check that `ChatDetailView` uses `conductor.proxy.actions` (not a local copy) and that `ActionGroupView` is observing via the `@Observable` proxy.

- [ ] **Step 4: Commit**

```bash
git add Conductor/Views/ActionGroupView.swift Conductor/ContentView.swift
git commit -m "(views): add ActionGroupView grouped by status, wired to GraphProxy"
```

---

### Task 30: Final verification pass

**Files:** none — verification only

- [ ] **Step 1: Swift 6 strict concurrency check**

Open the Xcode project, confirm `SWIFT_STRICT_CONCURRENCY=complete` is still set on both the app and test targets. Build. Every new file must compile clean with no concurrency warnings.

- [ ] **Step 2: On-device run-through**

Walk the spec's User Journeys on a real build:

1. `"What is CRISPR?"` → expect `overview` answer shape, one Wikipedia-backed action, composed prose.
2. `"What are the latest CRISPR therapies?"` → expect `citations` answer shape, academic tools selected.
3. `"Build me a file renamer"` on macOS → expect `workflow` answer shape, Automator tool selected.
4. `"Read https://example.com and summarize"` → expect `summary` shape, WebReader tool.
5. `"What did we find earlier about crispr?"` → expect `recall` verb, response sourced via `findRelated` against outcome.
6. Close and reopen the chat → graph is restored, prior intent still top of stack.

- [ ] **Step 3: Verify no legacy references remain**

Run:
```
grep -r "AgentPurpose\|TaskGraph\|SubAgent\|ConductorOrchestrator\|NarrationEvent\|ExtractedIntent\|PurposeTask\|IntentExtractionTool" Conductor/ ConductorTests/
```
Expected: no matches.

- [ ] **Step 4: Full test suite**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor`
Expected: all tests pass.

- [ ] **Step 5: Commit marker (optional)**

No code change needed. If any small fixes surfaced, commit them individually with `(topic): fix ...` style.

---

## Self-Review

**Spec coverage check:**

| Spec section | Task(s) |
|---|---|
| Stateless Typed Inference | Tasks 21, 22, 23, 26 (architecture enforced by design; no single task implements the principle) |
| Three LLM Touchpoints | 21 (intent), 22 (sub-agent), 23 (compose) |
| LanguageIntentQuery | 2 |
| Vocabulary (`IntentVerb`, `IntentSubject`, `AnswerShape`) | 1 |
| SubjectStack (two-tier, caps, relatesTo) | 4, 14 |
| ActionNode + kinds + statuses | 6 |
| Atom, ErrorAtom, ErrorKind | 3 |
| WorkingMemoryGraph actor | 12 |
| ChangeKind + AsyncStream | 12 |
| GraphProxy @Observable @MainActor | 24 |
| Memory verbs: `getContext`, `getActions`, `append`, `findRelated` | 15, 16, 17, 18 |
| `AffordanceBearing`, `AgentTool` refactor, `AffordanceDescriptor` | 5, 19, 20 |
| deterministicSearch | 9 |
| rebuildActionNodes observer | 13 |
| updateSubjectStack observer | 14 |
| Clarification template + lifecycle | 10, 13 |
| Generic Agent primitive | 22 |
| composeResponse synthesis | 23 |
| Turn lifecycle wiring | 26 |
| ProjectionBudget + truncation sentinel | 7 |
| GraphSnapshot + schema versioning | 11 |
| Per-chat persistence | 25 |
| Failure policy (per-tool failures, partial synthesis) | 22, 26 |
| UI bridge, action group view | 27, 29 |
| Legacy removals | 28 |

**Type consistency check:** verb name strings match between registration (`GetContextVerb.name = "getContext"`) and resolution (`Conductor.resolveVerbs` case `"getContext"`). `AppendSlot` cases (`.action`, `.outcome`) match both the enum and `AppendVerb` argument handling. `ActionStatus` is `Codable` and used uniformly. `AffordanceBearing` is the parent protocol for `AgentTool`, `MemoryVerb`, and `AffordanceDescriptor`.

**Placeholder scan:** no "TBD" / "implement later" / "similar to above" / `"...": true` markers remain. Each code step shows the full code that goes in the file.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-13-working-memory-graph.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

**Which approach?**
