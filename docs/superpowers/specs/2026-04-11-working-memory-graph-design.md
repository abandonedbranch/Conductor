# Working Memory Graph Architecture

## Summary

Replace the current per-turn `TaskGraph` plus hand-written sub-agent prompts with a persistent, in-memory **working memory graph** that serves as the single source of truth for everything Conductor knows about the current conversation. Every interaction with the on-device LLM is a **stateless typed inference** call: translate language into a typed value, then act on the value in deterministic Swift. Planning, state, history, subject tracking, and tool selection all live outside the LLM.

This is a direct response to Apple's on-device model having a hard **4,096 token** context window. The only way to scale capability under that ceiling is to stop storing anything in the LLM's context that can live in system memory instead.

## Problem

The current `ConductorOrchestrator` (`Conductor/Services/ConductorOrchestrator.swift`) has three structural limits:

1. **Context exhaustion by tool count.** Every tool added to the toolbox inflates the baseline context for any agent that might need it. Today `SubAgent` caps at 2 tools per node via `chunked(into: 2)`, which is a workaround. As the toolbox grows we can't even inject the tool *definitions* without crowding out the prompt itself.
2. **No memory across turns.** `TaskGraph` is created fresh inside `handle(userMessage:)` and dies when the turn ends. A follow-up like *"now do the same for transformers"* re-plans from scratch and the model has no handle on *"that"*, *"those papers"*, or *"the previous query"*.
3. **Purpose is a hard enum, not emergent.** `AgentPurpose` is hand-maintained in three places — the enum, the orchestrator's system prompt, and every tool's `purpose` property. Adding a new capability class means touching all three. Worse, a tool can only live in one bucket.

The on-device model's context window is the forcing function. It is **4,096 tokens, total per call**. That budget covers the system prompt, every registered tool definition, the user's message, the tool-call trace, and the model's own generated output — all of it, inside the same 4K.

## Core Principle: Stateless Typed Inference

Every LLM call in Conductor is a pure function:

```
(instructions, user-provided input, tool set) → @Generable output
```

Sessions are disposable. `LanguageModelSession` instances are constructed per call and destroyed on return. Nothing carries across calls inside a session. Results cross call boundaries only through the working memory graph.

This rule includes the user-facing chat. The Conductor does not reply to the user in prose from an LLM session. The Conductor's LLM call produces a typed `LanguageIntentQuery`; the user-visible message is assembled afterward by deterministic code, or by a separate synthesis call whose context is injected through instructions (RAG), not session history.

Natural language is a user interface, not a dialogue partner. The LLM translates human language into structured values; everything else is Swift.

See also: `CLAUDE.md` → LLM Usage.

## The Three LLM Touchpoints

A turn contains up to three discrete LLM sessions, each with its own fresh 4K budget:

1. **Intent session** — `parseIntent` (turn 1) or `updateIntent` (turn N>1). Produces `LanguageIntentQuery`. Budget: ~500–800 tokens.
2. **Sub-agent sessions** — zero or more, one per ready Action node. Each runs a narrow goal with a narrow verb + tool set. Writes atoms to the graph. Budget: ~3,000–3,800 tokens worst case.
3. **Synthesis session** — `composeResponse`, fired only when `answerShape` requires prose. Read-only scope, no domain tools. RAG injected through instructions.

Session N cannot see session N-1's context. The graph is the only carrier between them.

## LanguageIntentQuery

The canonical `@Generable` output of the intent session. **Monomorphic** — one shape for all turns. Stored as a newest-first stack in the Intent slot.

```swift
@Generable
struct LanguageIntentQuery: Sendable, Codable {
    let verbs: [IntentVerb]
    let subjects: [String]
    let answerShape: AnswerShape
    let continuation: Continuation?

    @Generable
    enum Continuation: String, Codable {
        case refines   // narrow to X — same subject, tighter scope
        case extends   // also look at Y — additional subject
        case pivots    // now do Z instead — new subject, keep verbs
        case recalls   // what did we find earlier about X — read-only query
    }
}
```

Design rules:

- **No free-text field.** Prose escape hatches become dumping grounds that deterministic code can't route on.
- **`subjects` is `[String]`**, not `[SubjectRef]`. The graph resolves strings to `Subject` entries. The intent value stays lightweight.
- **`continuation` replaces** the original spec's informal "references to prior context." Each enum case has a precise meaning for `SubjectStack` operations (see below).

## Vocabulary

Shared controlled vocabulary between `LanguageIntentQuery.verbs` and `ToolAffordance.verbs`. Lives in `Conductor/Models/Vocabulary.swift`.

```swift
@Generable
enum IntentVerb: String, Codable, CaseIterable {
    case find         // search, look up, discover
    case summarize    // explain, overview, TL;DR
    case recall       // what did we find, go back to
    case build        // make, create, generate
    case read         // read this page, URL extraction
}

@Generable
enum IntentSubject: String, Codable, CaseIterable {
    case academic
    case biomedical
    case preprint
    case encyclopedic
    case webpage
    case workflow
    case conversational
}

@Generable
enum AnswerShape: String, Codable, CaseIterable {
    case overview     // prose — concept explanation (synthesis call)
    case summary      // prose — condense prior context (synthesis call)
    case citations    // deterministic — list of references
    case workflow     // deterministic — executable artifact
    case direct       // deterministic — single-tool passthrough
}
```

Curation model:

- **Growth is a code change.** No runtime extension, no config file, no server-driven dictionary.
- **Enums, not `Set<String>`.** The LLM cannot produce values outside the set — drift becomes impossible.
- **New tool requires vocabulary review.** Adding a tool with an unrecognized verb/subject fails at compile time.
- **Persisted data references raw strings.** Decode failures for unknown cases fall back to snapshot-is-unreadable (see Persistence).

## The Working Memory Graph

The graph is the single source of truth. It persists for the lifetime of a chat. The LLM sees projections of it only via memory verbs.

### Top-Level Shape

Four slots, fixed schema:

| Slot | Shape |
|---|---|
| **Intent** | Stack of `LanguageIntentQuery`, newest first |
| **Actions** | `[UUID: ActionNode]` — the plan and execution state, one node per decomposed goal |
| **Subject** | `SubjectStack` — what is under discussion, two-tier |
| **Current outcome** | `[Atom]` — append-only running synthesis |

### SubjectStack

```swift
struct SubjectStack: Codable, Sendable {
    private(set) var active: [Entry]      // front-of-mind; default context. Cap: 8
    private(set) var archived: [Entry]    // reachable via findRelated. Cap: 20, LRU

    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        let name: String
        let introducedAt: Date
        let introducedByTurn: Int
        var lastTouchedTurn: Int
        let relatesTo: UUID?
    }
}
```

`Continuation` → `SubjectStack` operations:

| Continuation case | Operation |
|---|---|
| `.refines` | No structural change; bump `lastTouchedTurn` on primary |
| `.extends` | Append new entry to `active` |
| `.pivots` | Archive all current `active`; push new entry |
| `.recalls` | No structural change; lookup only |

When `active.count > 8`, the oldest `active` entry moves to `archived`. When `archived.count > 20`, LRU entry is dropped. Caps are architectural; the `ProjectionBudget` layer may further window at projection time.

### ActionNode

```swift
struct ActionNode: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: ActionKind               // .work, .clarification
    let goal: String
    let verbs: [IntentVerb]
    let subjects: [IntentSubject]
    let answerShape: AnswerShape
    let assignedVerbNames: [String]    // MemoryVerb names for persistence
    let assignedToolNames: [String]    // friendlyName values for persistence
    var status: ActionStatus           // .pending, .running, .completed, .failed, .awaitingUser
    var atoms: [Atom]
    let dependsOn: Set<UUID>
    let createdAt: Date
}

enum ActionKind: String, Codable, Sendable { case work, clarification }
enum ActionStatus: String, Codable, Sendable {
    case pending, running, completed, failed, awaitingUser
}
```

### Atom

```swift
enum Atom: Codable, Sendable {
    case success(content: String, source: URL?, toolName: String, timestamp: Date)
    case error(ErrorAtom)
    case note(text: String, timestamp: Date)
}
```

### Write Discipline

| Writer | May write |
|---|---|
| Intent session | `Intent` (appends new `LanguageIntentQuery`) |
| Observer: rebuildActionNodes | `Actions` (pending set derived from Intent) |
| Observer: updateSubjectStack | `Subject` |
| Sub-agents | Their own `Actions` node (status + atoms); append-only to `Current outcome` |
| Synthesis session | Nothing — read-only |
| User | Nothing directly — writes flow through the intent session |

Violations are programmer errors. Enforced via actor isolation and access control.

### Live Reads

Sub-agents always see current graph state through memory verbs. No frozen snapshots. If a peer sub-agent appended an atom five seconds ago, a subsequent read sees it. Where budget pressure demands it, a verb may return a windowed projection (top-N, most recent) with an explicit truncation marker. The window is a projection detail, not a freshness tradeoff.

## Concurrency & UI Bridge

### Graph actor

```swift
actor WorkingMemoryGraph {
    private var intentStack: [LanguageIntentQuery] = []
    private var actions: [UUID: ActionNode] = [:]
    private var subjects: SubjectStack
    private var outcome: [Atom] = []

    // Affordance descriptors the observer needs for deterministicSearch.
    // Passed in at init; immutable for the lifetime of the graph.
    // Lightweight values (name + ToolAffordance) — not the concrete tools themselves.
    private let toolDescriptors: [AffordanceDescriptor]
    private let verbDescriptors: [AffordanceDescriptor]

    // Writes
    func append(intent: LanguageIntentQuery)
    func append(atom: Atom, to actionID: UUID)
    func updateStatus(_ status: ActionStatus, for actionID: UUID)

    // Reads return Sendable projections
    func currentIntent() -> LanguageIntentQuery?
    func activeSubjects() -> [SubjectStack.Entry]
    func allActions() -> [ActionNode]
    func currentOutcome() -> [Atom]

    // Persistence
    func snapshot() -> GraphSnapshot
    static func restore(from snapshot: GraphSnapshot) -> WorkingMemoryGraph

    // UI notification
    nonisolated let changes: AsyncStream<ChangeKind>
    private let changesContinuation: AsyncStream<ChangeKind>.Continuation
}

enum ChangeKind: Sendable { case intent, actions, subject, outcome }
```

All writes return without re-entering the actor. All reads return `Sendable` values.

### Observer cascade

Observers are private methods on the actor, called synchronously from each write method in source order. No dynamic registry, no priority sort.

```swift
func append(intent: LanguageIntentQuery) {
    intentStack.append(intent)
    rebuildActionNodes()             // observer
    updateSubjectStack(for: intent)  // observer
    emit(.intent)
}
```

Rules:

1. An observer **cannot write to the slot it observes**. No implicit cycles.
2. **Cascade terminates in one hop.** If a secondary cascade is needed, it is wired explicitly in source.
3. **Observers do not call the LLM.** They are pure functions over graph state (and, for `rebuildActionNodes`, pure functions over the toolbox's affordance descriptors — see below).

### UI bridge

The graph actor cannot directly drive SwiftUI: `@Observable` requires synchronous property access. The bridge is an `AsyncStream<ChangeKind>` plus a `@MainActor @Observable` proxy.

```swift
@MainActor
@Observable
final class GraphProxy {
    private(set) var intent: LanguageIntentQuery?
    private(set) var subjects: [SubjectStack.Entry] = []
    private(set) var actions: [ActionNode] = []
    private(set) var outcome: [Atom] = []

    private let graph: WorkingMemoryGraph

    init(graph: WorkingMemoryGraph) {
        self.graph = graph
        Task { await subscribe() }
    }

    private func subscribe() async {
        for await kind in graph.changes {
            switch kind {
            case .intent:  intent = await graph.currentIntent()
            case .subject: subjects = await graph.activeSubjects()
            case .actions: actions = await graph.allActions()
            case .outcome: outcome = await graph.currentOutcome()
            }
        }
    }
}
```

Sub-agents and LLM sessions talk to the graph actor directly via memory verbs. Views read `GraphProxy` properties synchronously. The stream is plumbing.

`ChangeKind` is coarse by design — four cases, no payload. The stream is a *poke*; consumers re-read the graph. This preserves the live-reads principle and enables natural coalescing when many rapid writes target the same slot.

## Memory Verbs

```swift
protocol MemoryVerb: Tool, AffordanceBearing {}
```

`AffordanceBearing` is introduced in [Tool Affordances](#tool-affordances) below. Four verbs, each registered as a distinct Foundation Models `Tool`:

| Verb | Signature | Purpose |
|---|---|---|
| `getContext` | `() → ContextProjection` | Current intent + active subjects |
| `getActions` | `(status: ActionStatus?) → [ActionProjection]` | Queryable view of action nodes; `nil` returns all |
| `append` | `(slot: AppendSlot, atom: Atom) → AppendReceipt` | Scoped write into the caller's permitted slots |
| `findRelated` | `(keyword: String) → [AtomProjection]` | Fuzzy lookup across outcome atoms and archived subjects |

`AppendSlot` is LLM-facing input and therefore `@Generable`:

```swift
@Generable
enum AppendSlot: String, Codable {
    case action         // atom attached to the caller's Action node
    case outcome        // atom appended to Current outcome
}
```

An agent's `append` call is constrained by write discipline: its `AppendReceipt` either confirms the write or returns a typed refusal if the agent attempted to write outside its permitted slots.

Design rules:

- **`@Generable` arguments.** The LLM cannot escape the grammar.
- **Stable verb names.** No path strings; the LLM asks questions, not traversals.
- **Bounded return size.** Each verb enforces `ProjectionBudget` caps. Truncation produces an explicit sentinel marker.
- **Verbs are selected, not always-on.** The same `deterministicSearch` that picks domain tools also picks which verbs a given call gets. A turn-1 `parseIntent` gets no verbs (nothing to read yet). A synthesis call gets only `getContext`.

## Tool Affordances

```swift
struct ToolAffordance: Sendable {
    let verbs: Set<IntentVerb>
    let subjects: Set<IntentSubject>
    let answerShapes: Set<AnswerShape>
    let priority: Int
}

protocol AffordanceBearing {
    var affordance: ToolAffordance { get }
}

protocol AgentTool: Tool, AffordanceBearing {
    var friendlyName: String { get }
}

// Lightweight, Sendable descriptor the graph actor carries so rebuildActionNodes
// can run deterministicSearch without holding concrete tool instances across the
// actor boundary.
struct AffordanceDescriptor: Sendable, AffordanceBearing {
    let name: String                 // friendlyName for tools, verb identifier for verbs
    let affordance: ToolAffordance
}
```

Both `AgentTool` and `MemoryVerb` conform to `AffordanceBearing`, which lets `deterministicSearch` operate uniformly over either pool. The graph actor holds immutable `[AffordanceDescriptor]` lists (one for verbs, one for domain tools) derived from the registered toolbox at graph creation time. Concrete tool and verb instances live in the dispatcher outside the actor.

Seed mapping for the current toolbox:

| Tool | verbs | subjects | answerShapes |
|---|---|---|---|
| WikipediaSearchTool | `[.find, .summarize]` | `[.encyclopedic]` | `[.overview, .summary, .direct]` |
| PubMedSearchTool | `[.find]` | `[.academic, .biomedical]` | `[.citations, .direct]` |
| ArXivSearchTool | `[.find]` | `[.preprint, .academic]` | `[.citations, .direct]` |
| SemanticScholarSearchTool | `[.find]` | `[.academic]` | `[.citations, .direct]` |
| OpenAlexSearchTool | `[.find]` | `[.academic]` | `[.citations, .direct]` |
| CrossRefSearchTool | `[.find]` | `[.academic]` | `[.citations, .direct]` |
| WebReaderTool | `[.read, .summarize]` | `[.webpage]` | `[.summary, .direct]` |
| BuildAutomatorWorkflowTool | `[.build]` | `[.workflow]` | `[.workflow]` |

## Deterministic Search

One pure function, generic over any `AffordanceBearing` pool:

```swift
func deterministicSearch<T: AffordanceBearing>(
    intent: LanguageIntentQuery,
    pool: [T]
) -> [T]
```

Algorithm (v1):

1. Multi-set intersection of `intent.verbs × tool.affordance.verbs`.
2. Filter by `intent.subjects × tool.affordance.subjects` (any match).
3. Check `intent.answerShape` against `tool.affordance.answerShapes` (must contain).
4. Rank remaining by `priority + match density`.
5. Truncate to a context-aware cap (v1: 4 tools per sub-agent).

No LLM. No embeddings. No runtime inference. Memory verbs bear affordances too (declared in source alongside each verb) so the same function picks them.

### Zero-match fallback

See [Clarification](#clarification).

## Clarification

If `deterministicSearch` over the domain toolbox returns empty for a well-formed intent, Conductor does not guess and does not fire a second LLM call to ask. It writes a single `ActionNode(kind: .clarification, ...)` with templated text:

```swift
enum ClarificationTemplate {
    static func render(from intent: LanguageIntentQuery) -> String {
        """
        I couldn't match that to any available tools.
        You asked for: \(intent.verbs.map(\.rawValue).joined(separator: ", ")) \
        on \(intent.subjects.joined(separator: ", ")).

        I can help with: \(availableAffordanceHint()).
        Could you rephrase, or point me at a specific source?
        """
    }
}
```

`availableAffordanceHint()` is deterministic — it walks the toolbox, collects the union of `subjects` and `answerShapes` across all registered `AgentTool` instances, and formats them into a brief human-readable sentence (e.g., "searching academic papers, reading web pages, building Automator workflows"). No hand-written copy; when the toolbox grows, the hint grows.

The clarification surfaces as a normal assistant message bubble — no dedicated UI component. The user's reply drives the next turn's `updateIntent`, which runs against the intact graph.

When the next turn begins, `rebuildActionNodes` observes any `.awaitingUser` clarification Actions left from the prior turn and marks them `.completed` (the user has answered — the clarification served its purpose) before decomposing the new Intent into fresh pending Actions. This is the only case where the observer modifies an existing Action node; in all other cases it only appends.

## The Sub-Agent Primitive

Sub-agents are generic. There is no `OverviewAgent`, `ResearchAgent`, etc. One primitive:

```swift
actor Agent {
    let actionID: UUID
    let goal: String
    let verbs: [any MemoryVerb]
    let tools: [any AgentTool]
    let graph: WorkingMemoryGraph      // live reference, not a snapshot

    func run() async
}
```

The agent's system prompt is a narrow goal statement. It does not contain context — the agent pulls context via memory verbs as it needs it. It does not contain a persona — persona is emergent from the verbs and tools it received. It does not know about other agents — coordination happens through the graph.

Purpose, in this model, is the result of *"which verbs and tools did the search give me?"*, not a declared property of the agent.

## Synthesis: composeResponse

When `answerShape` is `.overview` or `.summary`, after all Action nodes are terminal, Conductor fires a third LLM session.

```swift
@Generable
struct ComposedResponse: Sendable, Codable {
    let prose: String
    let sections: [Section]?

    @Generable
    struct Section: Codable {
        let heading: String
        let content: String
    }
}

func composeResponse(
    intent: LanguageIntentQuery,
    projection: OutcomeProjection
) async throws -> ComposedResponse
```

- **Scope: read-only.** Verbs: `[getContext]`. No `append`, no `findRelated`, no domain tools.
- **RAG, not verbs.** The atoms the synthesis summarizes are baked into the session's instructions string, bounded by `ProjectionBudget.composeResponseProjection`.
- **Fresh 4K.** Isolated from intent and sub-agent sessions.

`answerShape` drives the deterministic-vs-synthesis choice:

| `answerShape` | Assembly |
|---|---|
| `.citations` | Deterministic — atom list |
| `.workflow` | Deterministic — workflow atom is the answer |
| `.direct` | Deterministic — single-tool passthrough |
| `.overview` | Synthesis LLM call |
| `.summary` | Synthesis LLM call |

## Turn Lifecycle

```
1. User message arrives.

2. Intent session fires.
   Turn 1: parseIntent. Tools: [parseIntentTool] only. No graph yet.
   Turn N>1: updateIntent. Tools: [getContext verb, updateIntentTool].
   Output: LanguageIntentQuery appended to the Intent stack.

3. Observer cascade (synchronous inside the actor):
   - rebuildActionNodes: for each decomposed goal, run deterministicSearch
     over the memory verb pool and the toolbox, and write pending Action
     nodes with assignedVerbNames and assignedToolNames populated.
     If deterministicSearch over the toolbox returns empty, write a single
     ActionNode(kind: .clarification, status: .awaitingUser) instead.
   - updateSubjectStack: apply Continuation to SubjectStack.

4. Dispatcher reads ready Action nodes. For each:
   - Resolve `assignedVerbNames` and `assignedToolNames` (written by
     rebuildActionNodes) to concrete verb and tool instances.
   - Spawn a generic Agent with (verbs + tools + graph + actionID).

5. Agents run in parallel where dependencies allow. Each:
   a. Pulls context via memory verbs.
   b. Calls its domain tools.
   c. Writes atoms back via append(slot:, atom:).
   d. Marks its Action node terminal (.completed or .failed).

6. When all Actions are terminal:
   - If answerShape requires prose: fire composeResponse (fresh session, RAG).
   - Else: deterministic stitch over outcome atoms.

7. Response surfaced to user via GraphProxy.
   GraphSnapshot persisted by ChatManager.
   Turn ends.
```

No step holds state in an LLM session across call boundaries.

## Persistence

```swift
struct GraphSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let intentStack: [LanguageIntentQuery]
    let subjects: SubjectStack
    let actions: [ActionNode]
    let outcome: [Atom]
}
```

- **When:** written on turn boundaries, after the response is surfaced. One write per completed turn.
- **Where:** `ChatManager` extends each `Chat` with an optional `GraphSnapshot`. Storage medium unchanged (currently UserDefaults; any migration is separate work).
- **Restore:** on chat open, if snapshot present, rehydrate `WorkingMemoryGraph` via `restore(from:)`. If absent (pre-feature chats), start empty.
- **Crash mid-turn:** in-flight turn is lost. Restore from last completed turn. No crash recovery.
- **Schema mismatch:** `snapshot.schemaVersion != GraphSnapshot.currentSchemaVersion` → fail to rehydrate. Messages preserved, graph empty. Log a warning. The first migration is authored when the first schema change lands.

No append-only diff log. No replay. YAGNI.

## Budget

Static per-verb caps enforced at the verb level. Token estimate: `characterCount / 4` (English heuristic, conservative).

```swift
enum ProjectionBudget {
    static let contextProjection         = 512
    static let actionsProjection         = 256
    static let findRelatedResults        = 384
    static let atomContent               = 256   // per atom written via append
    static let composeResponseProjection = 1024  // dedicated synthesis call
}
```

Truncation sentinel:

```
... [truncated; N more entries available via findRelated]
```

Design rules:

- **No central budget actor.** Verbs are independently bounded; their sum, times expected concurrent activation, fits under 4K by design.
- **No runtime tokenizer.** `characterCount / 4` is an explicit heuristic. Revisit if Apple exposes a tokenizer on the Foundation Models session.
- **Overruns are tuning bugs, not architecture bugs.** Lower caps and re-run.

Sanity check — worst-case sub-agent call:

| Element | Tokens |
|---|---|
| System prompt (goal statement) | ~200 |
| 4 verb definitions | ~600 |
| 3 domain tool definitions | ~450 |
| Driver prompt | ~100 |
| Three verb calls + outputs (512+256+384) | ~1,150 |
| Two domain tool calls + outputs | ~800 |
| Model generation budget | ~512 |
| **Total** | **~3,810** |

~280 tokens of slack under 4,096 in the worst combination. Typical sub-agent calls (1–2 verbs, 1–2 tools) sit well under 3,000.

## Failure Policy

**Per-tool failures don't fail the Action.** A sub-agent with multiple tools that errors on one but succeeds on another completes normally. Error atoms are captured alongside success atoms.

**Action fails only if** every tool in its set errored, or the LLM session itself threw.

**Partial synthesis.** If some Actions in a turn fail and others succeed, the turn still produces a response from successful atoms. A footer atom captures the failure count (e.g., "1 of 3 sub-agents couldn't complete"). No apology, no offer to retry.

**No auto-retry.** The user re-asks in a new turn. The graph is intact; the new Intent can reference prior context via `.recalls` or `.refines`.

```swift
struct ErrorAtom: Codable, Sendable {
    let actionID: UUID
    let toolName: String?      // nil if session-level
    let kind: ErrorKind
    let message: String
    let timestamp: Date
}

enum ErrorKind: String, Codable, Sendable {
    case networkError
    case unsafeContent
    case timeout
    case noResults
    case unknown
}
```

## What Dissolves

| Today | After |
|---|---|
| `ConductorOrchestrator` monolithic turn runner | Thin shell: fires intent session, runs dispatcher, fires synthesis if needed |
| `AgentPurpose` enum with hand-written `agentDescription` / `narrationPrefix` | Deleted. `ToolAffordance` carries capability; persona is emergent |
| `TaskGraph` ephemeral | Replaced by `WorkingMemoryGraph`, persistent across turns |
| `SubAgent` with hand-rolled per-purpose prompts | One generic `Agent` primitive |
| `chunked(into: 2)` tool splitting | `deterministicSearch` with a context-aware cap |
| `IntentExtractionTool` (no-op) | Typed `parseIntent` / `updateIntent` producing `LanguageIntentQuery` |
| Sub-agent push-context via system prompt | Sub-agent pull-context via memory verbs |
| Narration stream wired to `TaskGraph` | UI subscribes to `GraphProxy`, which subscribes to `AsyncStream<ChangeKind>` |

## Retained

- All existing domain tools (`WikipediaSearchTool`, `PubMedSearchTool`, `ArXivSearchTool`, `SemanticScholarSearchTool`, `OpenAlexSearchTool`, `CrossRefSearchTool`, `WebReaderTool`, `BuildAutomatorWorkflowTool`). They gain a `ToolAffordance` and drop `purpose`.
- `WebReaderService` — unchanged.
- `ChatManager` — surface unchanged; per-chat persistence extended with an optional `GraphSnapshot`.
- `StitchedResponse` concept — retained for deterministic answer shapes as a graph projection, not a separate assembly step.

## Constraints

- **Swift 6 strict concurrency.** `WorkingMemoryGraph` is an actor. All writers cross the actor boundary. All reads return `Sendable` projections.
- **On-device only.** The graph never leaves the device. No analytics, no telemetry. See `CLAUDE.md` for the privacy bar.
- **Context window is 4,096 tokens per call.** System prompt + tool definitions + user input + tool trace + model output must all fit. Every projection enforces a bound. Every tool/verb registration is justified. If a call doesn't need a verb, it doesn't get the verb.
- **SwiftUI + `@Observable`.** The graph exposes an `@Observable` façade (`GraphProxy`) so views observe without touching the actor directly.
- **No legacy Combine, no UIKit/AppKit.**

## Resolved Decisions

The 2026-04-11 draft listed ten open questions. Each is now resolved:

1. **Memory verb surface.** Four verbs: `getContext`, `getActions(status:)`, `append(slot:, atom:)`, `findRelated(keyword:)`.
2. **Subject data structure.** Two-tier `SubjectStack`, `active` cap 8, `archived` cap 20 with LRU eviction. Each entry carries `relatesTo: UUID?`.
3. **Affordance vocabulary.** Typed `@Generable` enums in `Conductor/Models/Vocabulary.swift`. Growth is a code change.
4. **Observer dispatch.** Static source-order cascade inside the graph actor. No dynamic registry, no priority sort.
5. **Persistence format.** Full `GraphSnapshot` per chat on turn boundaries. No diff log. Schema version check fails closed: empty graph, messages preserved.
6. **Budget accounting.** Static per-verb caps in `ProjectionBudget`. `characterCount / 4` heuristic. Truncation emits a sentinel.
7. **Clarification UX.** Templated deterministic text in a normal chat bubble. No dedicated UI component, no LLM call.
8. **Intent diff semantics.** None. `LanguageIntentQuery` is monomorphic; each turn appends to the Intent stack. Diffs are computed over the stack top when needed.
9. **Sub-agent failure policy.** Fail-fast per Action, partial synthesis over successful atoms, user-driven retry. Typed `ErrorAtom` with `ErrorKind` enum.
10. **Verb-level filtering.** The same `deterministicSearch` that picks domain tools picks memory verbs. Nothing is always-on.

## Glossary

- **Stateless Typed Inference** — the governing pattern: every LLM call is `(instructions, input, tools) → @Generable`. Sessions are disposable. Includes the user-facing chat. Documented in `CLAUDE.md` → LLM Usage.
- **Working Memory Graph** — the persistent, in-memory, slot-structured store of everything Conductor knows about the current chat.
- **Intent slot** — stack of `LanguageIntentQuery` values, newest first.
- **LanguageIntentQuery** — the `@Generable` output of the intent session. Monomorphic.
- **Subject** — what is under discussion. Lives in `SubjectStack` with `active` and `archived` tiers.
- **Action** — a concrete goal the system has taken on. Has verbs, tools, status, and atoms.
- **Atom** — the smallest unit of output written into the graph.
- **Current outcome** — the running, append-only list of atoms.
- **Affordance** — structured metadata describing what a tool can do, expressed in the shared vocabulary.
- **Deterministic search** — the pure function from `LanguageIntentQuery` to a matched `Tool` set. Used for both verbs and domain tools. No LLM.
- **Observer** — a private method on the graph actor that reacts to a write. Pure function of graph state.
- **Projection** — any bounded, LLM-safe view derived from the graph.
- **MemoryVerb** — protocol marker for graph read/write primitives. Four verbs in v1.
- **AgentTool** — protocol marker for domain work tools. Each declares a `ToolAffordance`.
- **Generic Agent** — the one sub-agent primitive. Takes a goal, verbs, tools, and a graph handle.
- **composeResponse** — the third LLM touchpoint. Prose synthesis via RAG when `answerShape` requires it.
- **GraphProxy** — `@MainActor @Observable` bridge between the graph actor and SwiftUI.
- **ChangeKind** — coarse four-case enum emitted on the graph's `AsyncStream` for UI notification. No payload.
- **GraphSnapshot** — `Codable` struct persisted on turn boundaries.
- **ProjectionBudget** — enum of static token caps per verb/projection.
- **ErrorAtom / ErrorKind** — typed error representation written into the graph on sub-agent failures.

## Prior Art

This design supersedes the architecture in `docs/superpowers/specs/2026-04-09-multi-agent-orchestration-design.md`. That design introduced purpose-tagged tools, a task graph, and stateless sub-agents — all correct moves — but it kept the graph ephemeral, tools hand-bucketed, and context push-based. This document inverts all three.
