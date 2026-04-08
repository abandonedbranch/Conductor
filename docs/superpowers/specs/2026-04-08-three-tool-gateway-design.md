# Three-Tool Gateway Architecture

**Date:** 2026-04-08
**Status:** Draft
**Problem:** The on-device model hallucinates tool calls (especially Automator) and burns context window on tool descriptions and catalogs that may never be used.

## Problem Statement

The current architecture passes all tools (6 search backends + Automator) directly to `LanguageModelSession` at init. The model decides when and whether to call them based on descriptions and system prompt instructions alone. This causes two recurring defects:

1. **Hallucination.** The model sees `buildAutomatorWorkflow` in its tool list and fires it whenever the user mentions "Automator" in any context — including simple questions like "What Automator tools do you have?" It invents action names and generates workflows unprompted.

2. **Context exhaustion.** Tool descriptions, the Automator action catalog, and the secondary planning session consume context rapidly on the on-device model's limited window. Conversations hit compaction early.

Both defects share a root cause: the model is the router. It decides which tools to call with no structural guardrails.

## Design

Replace direct tool access with a **three-tool gateway**. The model session always receives exactly three tools. All other functionality is registered as **capabilities** in a `CapabilityRegistry` that these tools query against.

### The Three Tools

| Session Name | Swift Type | Purpose |
|---|---|---|
| `action` | `ActionTool` | Execute a capability on behalf of the user |
| `library` | `LibraryTool` | Search for information across registered knowledge backends |
| `manual` | `ManualTool` | Look up structured documentation about Conductor itself |

### Tool Behavior

#### `action` (ActionTool)

**Session name:** `action`
**Arguments:** `userMessage: String`

The model calls this when the user wants to **do** something — build a workflow, convert a file, run a shortcut.

Behavior:
1. Score `userMessage` against `CapabilityRegistry.search()` using fuzzy keyword matching.
2. **Zero matches:** Return `"No program exists to fulfill this request."`
3. **One match:** Build a `CapabilityRequest` (original message + extracted goal + optional parameters), call `capability.execute(request)`, return the result string.
4. **Multiple matches:** Throw `VagueIntentError`. The model sees the error type and responds naturally (e.g., "Multiple integrations exist. Please specify."). Matched capability names never enter the transcript.

#### `library` (LibraryTool)

**Session name:** `library`
**Arguments:** `query: String`, `domain: String?`

The model calls this when the user wants to **know** something — look up a paper, find a fact, research a topic.

Behavior:
1. If `domain` is provided (e.g., `"biomedical"`, `"physics"`), route directly to the matching search backend.
2. If no domain, score the query against registered search capabilities and pick the best-scoring backend.
3. Execute the search. Return synthesized results.

This replaces six individual search tools with one interface. The model never chooses between PubMed and arXiv — the tool does.

#### `manual` (ManualTool)

**Session name:** `manual`
**Arguments:** `page: String?`

The model calls this when it needs to answer questions about what Conductor is or can do.

Behavior:
1. If `page` is provided, return that page's content from `ManualPage`.
2. If no `page`, return the index — one-line summary per available page.

`ManualPage` is a Swift enum with static, authored content. Not generated, not queried from the registry — written documentation that ships with the app.

```swift
enum ManualPage: String, CaseIterable {
    case search
    case automator
    case overview

    var summary: String { ... }  // one line, for the index
    var content: String { ... }  // full page
}
```

### CapabilityRegistry

A service that owns all capability metadata and handles fuzzy matching. Lives in `Conductor/Services/`.

```swift
actor CapabilityRegistry {
    private var capabilities: [Capability] = []

    func register(_ capability: Capability)
    func search(query: String, maxResults: Int) -> [ScoredCapability]
}
```

Each `Capability`:
```swift
struct Capability: Sendable {
    let id: String                                    // e.g. "automator.build"
    let name: String                                  // e.g. "Build Automator Workflow"
    let description: String                           // one line
    let keywords: [String]                            // ["automator", "workflow", "automate", "macro"]
    let execute: @Sendable (CapabilityRequest) async -> String
}
```

`CapabilityRequest` — structured input from the resolver:
```swift
struct CapabilityRequest: Sendable {
    let userMessage: String       // original message, for context
    let extractedGoal: String     // distilled intent: "rename files"
    let parameters: [String: String]?
}
```

**Scoring** reuses the weighted keyword approach from `AutomatorActionIndex`:
- Name token match: 3 points
- Keyword match: 2 points
- Description match: 1 point
- Partial/substring matches score lower than exact

### VagueIntentError

```swift
struct VagueIntentError: Error {
    let matchCount: Int
}
```

Thrown by `ActionTool` when multiple capabilities match. Contains only the count — no names, no descriptions. The model sees the error type and responds tersely. The matched capability names never enter the session transcript.

### System Prompt

The system prompt changes to reflect the three-tool model. It no longer lists individual tools or Automator-specific instructions. Core directives:

- Use `action` when the user wants something done.
- Use `library` when the user wants to know something.
- Use `manual` when asked about Conductor's capabilities.
- Respond tersely. Do not elaborate unless asked.
- If a tool throws an error, explain the situation in one sentence.

### Session Initialization

```swift
let registry = CapabilityRegistry()
// Register all capabilities at launch
registry.register(automatorCapability)
registry.register(pubmedCapability)
registry.register(wikipediaCapability)
// ... etc.

let tools: [any Tool] = [
    ActionTool(registry: registry, tracker: tracker),
    LibraryTool(registry: registry, tracker: tracker),
    ManualTool(tracker: tracker),
]

let session = LanguageModelSession(tools: tools, instructions: instructions)
```

## What Changes

| Current | New |
|---|---|
| 7 tools passed to session | 3 tools passed to session |
| Model chooses between PubMed, arXiv, Wikipedia, etc. | `LibraryTool` routes internally |
| Model decides when to call `buildAutomatorWorkflow` | `ActionTool` gates access via registry scoring |
| Automator action catalog in tool description context | Catalog only loaded when `ActionTool` executes the automator capability |
| "What can you do?" answered from model knowledge (hallucination risk) | `ManualTool` returns authored documentation |
| Verbose disambiguation from model | `VagueIntentError` triggers terse model response |
| System prompt includes per-tool instructions | System prompt is tool-agnostic, capability-agnostic |

## What Stays the Same

- Individual tool implementations (PubMed, arXiv, Automator builder, etc.) are unchanged internally. They become capability execute closures instead of direct session tools.
- `ToolUsageTracker`, `ToolBadge`, `ToolSource`, `WorkflowPreview` — all unchanged.
- The secondary `LanguageModelSession` inside `BuildAutomatorWorkflowTool` for workflow planning — unchanged.
- Chat persistence, message display, streaming — unchanged.

## File Layout

```
Conductor/
  Services/
    CapabilityRegistry.swift       # Registry + Capability + CapabilityRequest + ScoredCapability
  Tools/
    ActionTool.swift               # action tool + VagueIntentError
    LibraryTool.swift              # library tool + domain routing
    ManualTool.swift               # manual tool + ManualPage enum
    ToolSupport.swift              # unchanged (BadgedTool, ToolUsageTracker, etc.)
    PubMedSearchTool.swift         # unchanged, called by LibraryTool
    WikipediaSearchTool.swift      # unchanged, called by LibraryTool
    ArXivSearchTool.swift          # unchanged, called by LibraryTool
    SemanticScholarSearchTool.swift # unchanged, called by LibraryTool
    OpenAlexSearchTool.swift       # unchanged, called by LibraryTool
    CrossRefSearchTool.swift       # unchanged, called by LibraryTool
    Automator/
      BuildAutomatorWorkflowTool.swift  # unchanged, called by ActionTool
      AutomatorActionIndex.swift        # unchanged
      AutomatorActionInfo.swift         # unchanged
      WorkflowPreview.swift             # unchanged
```

## Testing Strategy

- **CapabilityRegistry:** Unit tests for scoring — exact match, partial match, zero match, multiple match thresholds.
- **ActionTool:** Test zero/one/multiple match paths. Verify `VagueIntentError` is thrown (not a result string) on ambiguous input.
- **LibraryTool:** Test domain routing. Test fallback scoring when no domain specified.
- **ManualTool:** Test page lookup and index generation.
- **Integration:** Verify that asking "What Automator tools do you have?" hits `manual`, not `action`. Verify that "Build me a workflow" hits `action` and routes to Automator capability.

All tests use Swift Testing (`@Test`, `#expect`).

## Future Considerations

- **Extract `ActionTool` logic into a standalone `IntentResolver` service** if the three-tool approach proves the concept but the model still struggles with choosing between `action` and `library`.
- **Add more `ManualPage` entries** as capabilities grow.
- **Capability-specific argument schemas** if `CapabilityRequest` proves too generic for some capabilities.
