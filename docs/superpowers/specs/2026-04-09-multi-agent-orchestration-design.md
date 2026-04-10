# Multi-Agent Orchestration Design

## Summary

Transform Conductor from a single-session tool gateway into a multi-agent orchestration system. The Conductor becomes a pure planner/synthesizer that decomposes user intent into a task graph, dispatches purpose-driven sub-agents with focused tool sets, and deterministically stitches results into a response. The on-device LLM is used only for natural language → structured intent translation. Everything else is deterministic.

## Problem

The current architecture routes all user requests through a single `LanguageModelSession` with all tools loaded. This creates two scaling problems:

1. **Context exhaustion** — complex queries overwhelm the on-device model's limited context window because the session carries all tool definitions, conversation history, and tool outputs.
2. **Tool bloat** — every new tool added to the gateway increases baseline context consumption, even when most tools are irrelevant to the current query.

## Architecture

### Core Principle

The LLM is a thin translation layer — natural language in, structured intent out. Two LLM touchpoints exist in the entire pipeline:

1. **Conductor** extracts intent from the user's message (one call).
2. **Each sub-agent** translates its goal into tool call arguments (one call per agent).

Everything between and after is code, not inference.

### Pipeline

```
User message
  → Conductor extracts intent (LLM)
  → Deterministic decomposition into task graph
  → Sub-agents dispatched per graph node
  → Each sub-agent calls tools, writes to its graph node
  → Sub-agent reads upstream nodes for context, evaluates completion
  → Conductor detects all nodes resolved
  → Deterministic stitch of graph into response
  → Response presented to user
```

### Architecture Diagram

```
BEFORE:
  User → LanguageModelSession (4 tools) → Gateway → Registry → Tool

AFTER:
  User → Conductor (1 LLM call) → TaskGraph → SubAgents (2 tools each) → Graph → Stitch
```

## Components

### AgentPurpose

Each tool declares a single purpose. Purpose drives tool grouping, sub-agent dispatch, and dependency ordering.

```swift
enum AgentPurpose: String, Codable {
    case overview    // Wikipedia — lay of the land
    case research    // PubMed, arXiv, SemanticScholar, OpenAlex, CrossRef
    case web         // WebReader — free-form page extraction
    case build       // Automator workflows
}
```

**Single-responsibility**: each tool has exactly one purpose. Wikipedia is `.overview` (contextual starting point), not `.research` (authoritative sources). This distinction drives phased execution — `.overview` agents run first so `.research` agents benefit from their findings.

### AgentTool Protocol

Extends the Foundation Models `Tool` protocol with purpose and display metadata.

```swift
protocol AgentTool: Tool {
    var purpose: AgentPurpose { get }
    var friendlyName: String { get }
}
```

All existing tools (PubMedSearchTool, ArXivSearchTool, WikipediaSearchTool, SemanticScholarSearchTool, OpenAlexSearchTool, CrossRefSearchTool, WebReaderTool, BuildAutomatorWorkflowTool) conform to `AgentTool` by adding `purpose` and `friendlyName` properties.

### ExtractedIntent

The `@Generable` type produced by the Conductor's single LLM call.

```swift
@Generable
struct ExtractedIntent {
    let purposes: [PurposeTask]

    @Generable
    struct PurposeTask {
        let purpose: String
        let goal: String
        let completionCriteria: String
        let dependsOn: [Int]  // indices into this array
    }
}
```

The LLM produces a list of purpose-tagged tasks with dependency edges. Example for "Research CRISPR and build a summary workflow":

```
purposes: [
  PurposeTask(purpose: "overview", goal: "understand CRISPR gene therapy landscape",
              completionCriteria: "until you can summarize key approaches", dependsOn: []),
  PurposeTask(purpose: "research", goal: "find peer-reviewed CRISPR therapy studies",
              completionCriteria: "until you have 3+ cited sources", dependsOn: [0]),
  PurposeTask(purpose: "build", goal: "create workflow that emails weekly CRISPR summary",
              completionCriteria: "until workflow file is generated", dependsOn: [1]),
]
```

### TaskGraph

The unified plan, shared context, and completion tracker. An actor that serves as the single coordination mechanism.

```swift
actor TaskGraph {
    private var nodes: [UUID: TaskNode] = [:]

    struct TaskNode {
        let id: UUID
        let purpose: AgentPurpose
        let goal: String
        let completionCriteria: String
        let tools: [any AgentTool]
        let dependsOn: Set<UUID>

        var entries: [LogEntry] = []
        var status: TaskStatus = .pending
    }

    enum TaskStatus {
        case pending, running, completed, failed
    }

    // Sub-agent writes to its own node
    func append(_ entry: LogEntry, to taskID: UUID)

    // Sub-agent reads upstream dependencies' results
    func upstreamResults(for taskID: UUID) -> [LogEntry]

    // Conductor checks which nodes are ready to dispatch
    func readyToDispatch() -> [TaskNode]

    // Conductor checks if all nodes are terminal
    var isFullyResolved: Bool

    // Narration: appends a status message and publishes via AsyncStream
    // UI observes `narrationStream` to display grouped status cells
    func narrate(_ taskID: UUID, _ message: String)
    var narrationStream: AsyncStream<NarrationEvent> { get }

    // Deterministic stitch: walk graph in topological order
    func stitch() -> StitchedResponse
}
```

Key design decisions:

- **The graph IS the shared context.** There is no separate log. Sub-agents write entries into their own node; they read upstream nodes' entries for prior context.
- **Completion is deterministic.** The Conductor knows exactly how many tasks it dispatched and checks whether every node has a terminal status.
- **Dependencies are per-instance, not per-purpose.** The LLM's intent extraction determines which tasks depend on which, not the purpose enum. This allows "build me a file renamer" (no dependencies) and "build a summary of this research" (depends on research) to coexist.

### LogEntry

The atomic unit written by sub-agents into their graph node.

```swift
@Generable
struct LogEntry: Identifiable {
    let id: UUID
    let taskID: UUID
    let purpose: AgentPurpose
    let toolName: String
    let content: String
    let sourceURL: String?
    let timestamp: Date
}
```

### SubAgent

A short-lived, focused worker. Owns a `LanguageModelSession` with at most 2 tools.

```swift
actor SubAgent {
    let task: TaskGraph.TaskNode
    let graph: TaskGraph
    private let session: LanguageModelSession

    init(task: TaskGraph.TaskNode, graph: TaskGraph) {
        self.task = task
        self.graph = graph
        self.session = LanguageModelSession(
            instructions: """
            You are \(task.purpose.agentDescription).
            Your goal: \(task.goal)
            You have these tools: \(task.tools.map(\.friendlyName).joined(separator: ", "))
            Keep working until: \(task.completionCriteria)
            """,
            tools: task.tools
        )
    }

    func run() async {
        await graph.updateStatus(task.id, to: .running)
        await graph.narrate(task.id,
            "\(task.purpose.narrationPrefix) (\(task.tools.map(\.friendlyName).joined(separator: ", ")))")

        let upstream = await graph.upstreamResults(for: task.id)
        let prompt = buildPrompt(upstream: upstream)

        do {
            let response = try await session.streamResponse(to: prompt)
            let entry = LogEntry(
                id: UUID(), taskID: task.id, purpose: task.purpose,
                toolName: task.tools.first?.friendlyName ?? "",
                content: response.content, sourceURL: nil, timestamp: .now
            )
            await graph.append(entry, to: task.id)
            await graph.updateStatus(task.id, to: .completed)
        } catch {
            let errorEntry = LogEntry(
                id: UUID(), taskID: task.id, purpose: task.purpose,
                toolName: "error", content: error.localizedDescription,
                sourceURL: nil, timestamp: .now
            )
            await graph.append(errorEntry, to: task.id)
            await graph.updateStatus(task.id, to: .failed)
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

Key properties:

- **At most 2 tools** per sub-agent to keep context small.
- **Upstream-aware** — reads prior nodes' results, never the full graph.
- **Self-terminating** — completion criteria is in the prompt; the LLM decides when it has answered.
- **Errors don't cascade** — a failed node writes an error entry; the Conductor decides what to do.

### Conductor

The outermost layer. Uses `LanguageModelSession` for exactly one thing: extracting intent.

```swift
@Observable
final class Conductor {
    private let toolbox: [any AgentTool]
    private let intentSession: LanguageModelSession
    private(set) var activeGraph: TaskGraph?

    init(toolbox: [any AgentTool]) {
        self.toolbox = toolbox
        self.intentSession = LanguageModelSession(
            instructions: """
            Extract the user's intent as a structured plan.
            Identify what purposes are needed and how they depend on each other.
            Do not perform any tasks yourself.
            """,
            tools: [IntentExtractionTool()]
        )
    }

    func handle(userMessage: String) async -> Message {
        // 1. Extract intent (LLM)
        let intent = try await intentSession.respond(to: userMessage)

        // 2. Build graph (deterministic)
        let graph = buildGraph(from: intent)
        activeGraph = graph

        // 3. Dispatch (deterministic loop)
        await execute(graph)

        // 4. Stitch (deterministic)
        let response = await graph.stitch()

        // 5. Return message with graph for drilldown
        return Message(content: response.formatted, isUser: false, taskGraph: graph)
    }

    func buildGraph(from intent: ExtractedIntent) -> TaskGraph {
        let graph = TaskGraph()
        // Maps each intent index to ALL node UUIDs spawned for that purpose-task.
        // Downstream tasks depend on all nodes from their upstream purpose-task.
        var idMap: [Int: [UUID]] = [:]

        for (index, purposeTask) in intent.purposes.enumerated() {
            let purpose = AgentPurpose(rawValue: purposeTask.purpose)!
            let tools = toolbox.filter { $0.purpose == purpose }
            let chunks = tools.chunked(into: 2)
            var nodeIDs: [UUID] = []

            // Upstream dependencies: all node UUIDs from all dependent intent indices
            let dependencies = Set(purposeTask.dependsOn.flatMap { idMap[$0] ?? [] })

            for chunk in chunks {
                let id = UUID()
                nodeIDs.append(id)
                graph.addNode(TaskGraph.TaskNode(
                    id: id, purpose: purpose, goal: purposeTask.goal,
                    completionCriteria: purposeTask.completionCriteria,
                    tools: Array(chunk), dependsOn: dependencies
                ))
            }
            idMap[index] = nodeIDs
        }
        return graph
    }

    func execute(_ graph: TaskGraph) async {
        while !graph.isFullyResolved {
            let ready = await graph.readyToDispatch()
            await withTaskGroup(of: Void.self) { group in
                for task in ready {
                    group.addTask {
                        let agent = SubAgent(task: task, graph: graph)
                        await agent.run()
                    }
                }
            }
        }
    }
}
```

### StitchedResponse

Deterministic assembly of graph results. No LLM call.

```swift
struct StitchedResponse {
    let sections: [ResponseSection]

    struct ResponseSection {
        let heading: String
        let content: String
        let sources: [ToolSource]
    }

    var formatted: String {
        sections.map { section in
            """
            ## \(section.heading)

            \(section.content)
            """
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

## Tool-to-Purpose Mapping

| Tool | Purpose | Friendly Name |
|------|---------|---------------|
| WikipediaSearchTool | `.overview` | Wikipedia |
| PubMedSearchTool | `.research` | PubMed |
| ArXivSearchTool | `.research` | arXiv |
| SemanticScholarSearchTool | `.research` | Semantic Scholar |
| OpenAlexSearchTool | `.research` | OpenAlex |
| CrossRefSearchTool | `.research` | CrossRef |
| WebReaderTool | `.web` | Web |
| BuildAutomatorWorkflowTool | `.build` | Automator |

## Sub-Agent Dispatch Rules

- Tools are grouped by purpose from the toolbox.
- Each sub-agent receives at most **2 tools**.
- If a purpose has more than 2 tools, multiple sub-agents are spawned (e.g., 6 research tools → 3 research sub-agents).
- All sub-agents for the same purpose share the same goal and completion criteria.
- Sub-agents for a purpose launch in parallel once all upstream dependencies are resolved.

## UI

### Narration

Sub-agent status messages stream into the chat as lightweight, non-interactive cells. They are display-only — never fed back into the Conductor's context.

Messages are **grouped by purpose** with a colored left border:
- `.overview` — orange
- `.research` — blue
- `.web` — purple
- `.build` — gray

Each group shows:
- Purpose label (uppercase)
- Status lines as agents start and complete: "Searching PubMed and arXiv for..." → "Found 3 relevant papers."

### Stitched Response

The final assembled document appears as a normal message bubble with sections matching the graph's topological order. Sources are listed per section.

### Info Drilldown

An **(i) button** on the stitched response opens a **sheet overlay** showing:
- Each graph node with its purpose, agent label, tool names, timing, and status
- Full raw results per node (tool output, source URLs)
- Task graph visualization showing dependency flow
- Summary stats (total time, tool call count, source count)

### Badge System

The current `ToolBadge` system is removed. Purpose-grouped narration replaces badges as the user-facing feedback mechanism.

## What Changes

### Removed
- `CapabilityRegistry` — fuzzy keyword scoring replaced by deterministic purpose matching
- `ActionTool` / `LibraryTool` / `ManualTool` — gateway tools replaced by Conductor dispatch. `ManualTool`'s "what can you do?" functionality moves to the Conductor itself — it can answer capability questions directly from the toolbox's purpose taxonomy without dispatching sub-agents.
- `ToolBadge` / `BadgedTool` — replaced by purpose-grouped narration
- Main session tool array — Conductor gets only `IntentExtractionTool`
- `ActionResolver` / `LibraryRouter` — routing logic replaced by purpose-based grouping

### Retained (adapted)
- All existing tool implementations — gain `purpose` and `friendlyName`, conform to `AgentTool`
- `WebReaderService` / `WebReaderState` / `WebReaderError` — unchanged
- `ChatManager` persistence — unchanged
- `Message` model — gains optional `TaskGraph` for info drilldown

### New
- `Conductor` — orchestrator model (`@Observable`)
- `TaskGraph` — actor, unified plan + shared context + completion tracker
- `SubAgent` — actor, lightweight worker with `LanguageModelSession` + tools
- `AgentPurpose` — enum, purpose taxonomy
- `AgentTool` — protocol extending `Tool`
- `ExtractedIntent` — `@Generable`, LLM output for intent extraction
- `LogEntry` — `@Generable`, structured entry for graph nodes
- `StitchedResponse` — deterministic document assembly
- `IntentExtractionTool` — the Conductor's single tool
- `TaskGraphSheet` — SwiftUI sheet for info drilldown
- Narration view components — purpose-grouped status cells

## User Journeys

### Simple query: "What is CRISPR?"
```
Intent: [overview]
Graph: overview (Wikipedia, no dependencies)
Sub-agents: 1 agent, 1 tool
Narration: "Looking up CRISPR on Wikipedia..."
Response: Single overview section
```

### Research query: "What are the latest CRISPR therapies?"
```
Intent: [overview, research]
Graph: overview → research (3 agents: 1 overview + 2 research)
Sub-agents: 3 agents, 6 tools total
Narration: Overview group → Research group
Response: Overview + Research Findings sections
```

### Research + build: "Research CRISPR and build a summary workflow"
```
Intent: [overview, research, build]
Graph: overview → research → build
Sub-agents: 4 agents (1 overview + 2 research + 1 build)
Narration: Overview → Research → Build groups
Response: Overview + Research Findings + Workflow sections
```

### Simple build: "Build me a file renamer"
```
Intent: [build]
Graph: build (no dependencies)
Sub-agents: 1 agent, 1 tool
Narration: "Building Automator workflow..."
Response: Workflow section only
```

### Web lookup: "Read this article and summarize it"
```
Intent: [web]
Graph: web (no dependencies)
Sub-agents: 1 agent, 1 tool
Narration: "Reading webpage..."
Response: Web content summary
```

## Constraints

- **On-device only.** No external AI providers unless free, keyless, and tool-call capable.
- **Swift 6 strict concurrency.** All actors and sendable types must compile under `SWIFT_STRICT_CONCURRENCY=complete`.
- **At most 2 tools per sub-agent** to stay within context limits.
- **Deterministic pipeline** except for intent extraction and sub-agent tool argument translation.
- **No analytics or telemetry.** All processing on-device.
