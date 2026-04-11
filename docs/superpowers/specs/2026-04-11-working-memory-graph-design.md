# Working Memory Graph Architecture

## Summary

Replace the current per-turn `TaskGraph` + hand-written sub-agent prompts with a persistent, in-memory **working memory graph** that acts as the single source of truth for everything Conductor knows about the current conversation. Every interaction with the on-device LLM becomes a stateless function call. The LLM does exactly one thing: translate human language into structured intent (or translate a concrete goal into tool calls). All planning, state, history, subject tracking, and tool selection live in deterministic Swift code that reads from and writes to the graph.

This is a direct response to Apple's on-device model having a hard **4,096 token** context window. The only way to scale capability under that ceiling is to stop storing anything in the LLM's context that can live in system memory instead.

## Problem

The current `ConductorOrchestrator` (`Conductor/Services/ConductorOrchestrator.swift`) has three structural limits:

1. **Context exhaustion by tool count.** Every tool added to the toolbox inflates the baseline context for any agent that might need it. Today the `SubAgent` caps at 2 tools per node via `chunked(into: 2)`, which is a workaround, not a solution. As the toolbox grows, we can't even inject the tool *definitions* without crowding out the prompt itself.
2. **No memory across turns.** `TaskGraph` is created fresh inside `handle(userMessage:)` and dies when the turn ends. A follow-up like *"now do the same for transformers"* re-plans from scratch and the model has no handle on *"that"*, *"those papers"*, or *"the previous query"*.
3. **Purpose is a hard enum, not emergent.** `AgentPurpose` (`overview / research / web / build`) is hand-maintained in three places — the enum, the orchestrator's system prompt, and every tool's `purpose` property. Adding a new capability class means touching all three. Worse, a tool can only live in one bucket, so real cross-cutting tools have no home.

The on-device model's context window is the forcing function. It is **4,096 tokens, total**. That budget covers the system prompt, every registered tool definition, the user's message, the tool-call trace, and the model's own generated output — all of it, inside the same 4K. We cannot assume it will grow. In practice, after the system prompt and a handful of tool definitions, only a few hundred tokens of real working room remain.

## Core Principle

**The LLM is a stateless function from `(projected memory slice, relevant tools)` to `(tool call or message)`.**

- State lives in system memory, not in any `LanguageModelSession`.
- `LanguageModelSession` instances are disposable. They are constructed per call, destroyed after.
- The LLM's *only* job is to understand human language. It does not plan, it does not remember, it does not synthesize free-form. When we need planning, it translates intent. When we need an answer, it translates a narrow goal into tool calls.
- Everything else is deterministic: tool selection, dispatch, reads, writes, observation, diff, persistence.

A compact statement of every LLM call in the system:

```
tools   = [memoryGraph verbs] + deterministicSearch(currentIntent)
prompt  = minimal goal statement
body    = pull state via memoryGraph → act via domain tools → write back via memoryGraph
session = destroyed on return
```

## The Working Memory Graph

The graph is the single source of truth. It persists for the lifetime of a chat. It is large by LLM standards and trivial by computer standards. The LLM only ever sees projections of it via the `memoryGraph` verb tools.

### Top-Level Shape

Four slots, fixed schema:

| Slot | Purpose | Example |
|---|---|---|
| **Intent** | What the user wants, in canonical form. Holds verbs, subjects, expected answer shape, and references to prior context. | `{ verbs: [find, summarize], subjects: [CRISPR], answerShape: overview }` |
| **Actions** | The plan and its execution status. Each action node has a goal, a matched tool set, a status, and its own output atoms. | `[{ id, goal, tools, status, atoms }]` |
| **Subject** | What is under discussion. Holds a small ordered collection — most recent first — so follow-ups can resolve *"it"*, *"those"*, *"the previous"*. | `[CRISPR therapies, base editing]` |
| **Current outcome** | The running, structured synthesis of results so far. Grows atomically by append, not overwrite. | `[atom, atom, atom]` |

The graph is richer than the four slots — those are the top-level entry points. Beneath them live the actual entities: source references, tool call records, timing, error atoms, and whatever else observers need. But *every* projection back into an LLM call is derived from one of these four slots.

### Write Discipline

Like a video game, many systems read from the graph but writes are scoped by role. This is not a dumping ground — it is a disciplined store.

| Writer | May write |
|---|---|
| `parseIntent` / `updateIntent` | `Intent`, `Subject` |
| Tool-search observer | `Actions` (the pending set, derived from Intent) |
| Sub-agents | Their own `Actions` node (status + atoms); append-only to `Current outcome` |
| User | Nothing directly — the user writes through `parseIntent` |

Violating these scopes is a programmer error. Enforced via actor isolation and typed write tokens per slot.

### Live Reads

Sub-agents always see the current state through the `memoryGraph` tool. No frozen snapshots. If a peer sub-agent appended an atom five seconds ago, a reader call after that point sees it. This is what makes the video-game-state metaphor real — without it we're just passing prompt strings with extra steps.

Where context pressure demands it, individual verbs may return a small **window** of the live read (top-N, most-recent, scoped by slot). The window is a projection detail, not a freshness tradeoff.

### Observers

Deterministic observers watch monitored properties and react to mutations. The most important one:

> **When `Intent` changes, recompute the active tool set for the next LLM call.**

This makes the tool pool itself a *derived view* of graph state. It is not computed at dispatch time once; it is the result of whatever the graph most recently believes the user wants. A follow-up turn that refines Intent flows automatically into a new tool pool without any agent explicitly re-planning.

Other observers may watch `Actions` (to detect stuck or failed goals and trigger clarification), `Subject` (to prune stale entries), or `Current outcome` (to surface ready-to-display content to the UI). Observers are pure functions of the graph — they never call the LLM.

## The `memoryGraph` Tool Family

`memoryGraph` is not one tool — it is a small, fixed family of verbs. Every LLM call, conductor or sub-agent, has the whole family by default. Each verb is registered as a separate Foundation Models `Tool` so the LLM sees them as distinct entries in its context.

Proposed initial verbs (exact surface TBD — see Open Questions):

| Verb | Purpose |
|---|---|
| `getIntent()` | Current Intent node, canonical form. |
| `getSubject(depth:)` | Top N entries from the subject stack. |
| `getOutcome(scope:)` | Running synthesis, optionally scoped to a specific action or subject. |
| `getActions(status:)` | Queryable view of pending / running / completed action nodes. |
| `append(slot:, atom:)` | Scoped write into the caller's permitted slots. |
| `findRelated(keyword:)` | Fuzzy lookup across atoms. For when the LLM needs prior context but doesn't know the exact path. |

Design rules for every verb:

- **`@Generable` argument types.** The LLM can't escape the grammar.
- **Stable verb names.** No path strings. The LLM does not navigate a tree; it asks questions.
- **Bounded return size.** Every verb enforces a maximum projection. If a slot is too large, the verb returns a windowed view with an explicit "more available" marker.
- **Contextual filtering of the verb set itself.** Not every call needs every verb. A sub-agent whose only job is a single web fetch does not need `findRelated`. The dispatcher may trim the verb family to what's relevant — the same principle that trims domain tools, applied reflexively to the graph tools.

## parseIntent / updateIntent — The Only Language Pass

The LLM's sole job is translating human language into Intent. Two variants:

- **`parseIntent`** — turn 1 of a new chat. Tools: `[parseIntent]` only. No graph yet. Output: initial Intent + Subject written into a fresh graph.
- **`updateIntent`** — turn N > 1. Tools: `[memoryGraph verbs, updateIntent]`. The LLM reads current Intent via `getIntent`, diffs against the new user message, writes the delta.

Both are `@Generable` — the result is a typed Intent, never prose.

After this pass, the conductor does no more language work for the turn. Everything downstream is deterministic.

## Tool Affordance Model

Each domain tool declares structured affordances. This replaces `AgentPurpose` as the routing primitive.

```swift
struct ToolAffordance {
    let verbs: Set<String>        // e.g. [find, summarize, read, build]
    let subjects: Set<String>     // e.g. [academic, biomedical, news, file]
    let consumes: InputShape      // e.g. .query(String), .url(URL), .description(String)
    let produces: OutputShape     // e.g. .citations, .text, .workflow
    let priority: Int             // tiebreaker for overlapping matches
}

protocol AgentTool: Tool {
    var affordance: ToolAffordance { get }
    var friendlyName: String { get }
}
```

The exact vocabulary is curated, not free text. A small controlled list of verbs and subjects keeps both the LLM's `parseIntent` output and the search predicate aligned. Growing the vocabulary is a deliberate act.

## Deterministic Tool Search

The search is a plain function:

```
deterministicSearch(intent: Intent, toolbox: [AgentTool]) -> [AgentTool]
```

Algorithm (v1):

1. Multi-set intersection of `intent.verbs × tool.affordance.verbs`.
2. Filter by `intent.subjects × tool.affordance.subjects` (any match).
3. Check `intent.answerShape` compatibility with `tool.affordance.produces`.
4. Rank remaining tools by `priority + match density`.
5. Truncate to a context-aware cap (initially ~4 tools per sub-agent).

No LLM. No embeddings. No runtime inference. Embeddings become interesting as a v2 optimization when the affordance vocabulary grows past what simple intersection handles cleanly.

### Zero-Match Fallback

If the search returns nothing, Conductor does not guess. It writes a clarification action into the graph and surfaces it to the user. The next turn's `updateIntent` call sees the clarification request in the graph and integrates the user's response into Intent. **The graph persists across this round-trip** — we are not starting from scratch, we are refining Intent in place.

## The Sub-Agent Primitive

Sub-agents become generic. There is no `OverviewAgent`, `ResearchAgent`, etc. There is one primitive:

```swift
actor Agent {
    let goal: String
    let tools: [any AgentTool]         // [memoryGraph verbs] + matched domain tools
    let graph: WorkingMemoryGraph      // live reference, not a snapshot
    let actionID: UUID                 // the slot it is permitted to write into

    func run() async { ... }
}
```

An agent's system prompt is a narrow goal statement. It does not contain context — the agent pulls context via `memoryGraph` verbs as it needs it. It does not contain a persona — persona is emergent from the tools it got. It does not know about other agents — coordination happens through the graph.

Purpose, in this model, is the result of *"which tools did the search give me?"*, not a declared property of the agent.

## Lifecycle of a Turn

```
1. User message arrives.

2. Conductor picks parseIntent (turn 1) or updateIntent (turn N>1) and fires
   a single stateless LLM call. Only tools in scope: the intent parser + (on
   turn N>1) the memoryGraph read verbs.

3. The call writes to Intent and Subject.

4. The Intent observer fires. It runs deterministicSearch over the toolbox
   and writes pending Action nodes into the graph — one per goal the intent
   decomposed into.

5. The dispatcher reads ready Action nodes from the graph. For each, it
   spawns a generic Agent with tools = [memoryGraph verbs] + matched tools.

6. Agents run in parallel where dependencies allow. Each agent:
     a. Pulls context via memoryGraph.
     b. Calls its domain tools.
     c. Writes atoms back via append(slot:, atom:).
     d. Marks its Action node complete.

7. Observers watching Current outcome surface ready content to the UI. The
   UI is a view of the graph, not a pipeline endpoint.

8. Turn ends. The graph persists. Nothing is thrown away.
```

No step here holds memory in an LLM session. Every LLM call in the pipeline is disposable.

## What Dissolves

Compared to the current codebase:

| Today | After |
|---|---|
| `ConductorOrchestrator` as a monolithic turn runner | A thin shell around `parseIntent` + dispatch |
| `AgentPurpose` enum with hand-written `agentDescription` / `narrationPrefix` | Gone. Tool metadata carries affordances; persona is emergent. |
| `TaskGraph` as a per-turn ephemeral structure | Replaced by `WorkingMemoryGraph`, persistent across turns. |
| `SubAgent` with hand-rolled per-purpose prompts | One generic `Agent` primitive. |
| `chunked(into: 2)` tool splitting | Replaced by affordance search with a context-aware cap. |
| `IntentExtractionTool` (a no-op satisfying the API) | Real `parseIntent` / `updateIntent` with typed output. |
| Sub-agent push-context via system prompt | Sub-agent pull-context via `memoryGraph` verbs. |
| Narration stream wired to `TaskGraph` | UI subscribes directly to graph observers. |

## Retained

- All existing domain tools (`WikipediaSearchTool`, `PubMedSearchTool`, `ArXivSearchTool`, `SemanticScholarSearchTool`, `OpenAlexSearchTool`, `CrossRefSearchTool`, `WebReaderTool`, `BuildAutomatorWorkflowTool`) — they gain a `ToolAffordance` and drop `purpose`.
- `WebReaderService` — unchanged.
- `ChatManager` — unchanged at the surface, but per-chat persistence now also includes a serialized `WorkingMemoryGraph` diff log.
- `StitchedResponse` — retained conceptually but becomes a graph projection, not a standalone assembly step.

## Constraints

- **Swift 6 strict concurrency.** `WorkingMemoryGraph` is an actor. All writers cross the actor boundary. All reads return `Sendable` projections.
- **On-device only.** The graph never leaves the device. No analytics, no telemetry. See `CLAUDE.md` for the privacy bar.
- **Context window is 4,096 tokens, full stop.** System prompt + tool definitions + user input + tool trace + model output must all fit. Every projection enforces a bound. Every tool registration is justified. If a call doesn't need a verb, it doesn't get the verb. Any design decision that grows per-call token cost must justify itself against this ceiling.
- **SwiftUI + `@Observable` for UI.** The graph exposes an `@Observable` façade so views can observe it without touching the actor directly.
- **No legacy Combine, no UIKit/AppKit** (see `CLAUDE.md`).

## Open Questions

These are the decisions we have not made yet. Nothing downstream of these should be treated as final.

1. **Exact `memoryGraph` verb surface.** The six proposed verbs are a starting point. The real surface is whatever is minimum sufficient for an agent to do its job without prose injection.
2. **`Subject` data structure.** Stack? Ordered set? LRU with pinning? Probably a small ordered list with an explicit current pointer, but the details depend on how pivots and parallel subjects behave.
3. **Affordance vocabulary.** Who curates the verb/subject list? How does it grow? Is it versioned with the app bundle?
4. **Observer dispatch order.** When multiple observers react to the same mutation, what determines firing order? Probably priority-sorted; worth confirming.
5. **Graph persistence format.** Full snapshot per chat, append-only diff log, or both? Append-only is tempting for debugging and replay.
6. **Context-window budget accounting.** Who measures token cost per projection? The verb itself, a central budget actor, or a heuristic?
7. **Clarification UX.** When the tool search returns zero matches, how does the UI present the clarification request? Is it a special message type, an inline prompt, or a system card?
8. **Intent diff semantics.** Is `updateIntent` a replacement or a merge? Probably a typed delta, but needs a concrete shape.
9. **Sub-agent failure policy.** When an agent's tools all fail, does the action node re-dispatch with a broader tool pool, or does it surface to the user as a failed action?
10. **Verb-level context filtering.** The doc mentions that even `memoryGraph` verbs may be trimmed per call. What signals drive that trim?

## Glossary

To keep future discussion consistent:

- **Working Memory Graph** — the persistent, in-memory, slot-structured store of everything Conductor knows about the current chat.
- **Intent** — the canonical, `@Generable` expression of what the user wants. Always derived from a human language pass.
- **Subject** — the current conversational noun(s); the anaphoric anchor for follow-ups.
- **Action** — a concrete goal the system has taken on, with matched tools, status, and output atoms.
- **Atom** — the smallest unit of output written into the graph. One tool call produces one atom.
- **Current outcome** — the running synthesis of atoms relevant to the current Intent.
- **Affordance** — structured metadata describing what a tool can do, in a vocabulary shared with Intent.
- **Deterministic tool search** — the pure function from Intent to a matching tool set. No LLM involved.
- **Observer** — a pure function that watches a graph slot and reacts to mutations (typically by writing derived data into another slot).
- **Projection** — any bounded, LLM-safe view derived from the graph.
- **Verb family (`memoryGraph`)** — the fixed, small set of tools every LLM call gets by default to read and write the graph.
- **Generic Agent** — the one sub-agent primitive. Takes a goal and a tool set; pulls its own context.

## Prior Art

This design supersedes the architecture described in `docs/superpowers/specs/2026-04-09-multi-agent-orchestration-design.md`. That design was the right move at the time — it introduced purpose-tagged tools, a task graph, and stateless sub-agents — but it kept the graph ephemeral, tools hand-bucketed, and context push-based. This document inverts all three.
