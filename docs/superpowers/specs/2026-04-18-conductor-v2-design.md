# Conductor v2 — Prose-to-Pipeline Design

**Status:** Approved
**Date:** 2026-04-18
**Platform:** macOS 14+ (iOS deferred)
**Scope:** Minimal demonstrator — prove the prose→pipeline pattern works

---

## 1. Problem Statement

Conductor v1 treated the on-device Foundation Model as the primary integrator: the LLM was asked to emit a fully wired `CellProgram` (cells, inputs, outputs, links, ask insertions). Testing showed this is unreliable at the 4k-token, on-device scale. Observed failure modes:

- **Missing ask cells** — LLM forgets to insert the prompt for a required URL.
- **Cycles** — LLM emits `A → B → A` structures.
- **Wrong wiring** — LLM links `read.body` to a parameter expecting a number.
- **Hallucinated fields** — LLM invents cell kinds, parameter names, or URLs.
- **Content-safety trips** — user keywords routed through the LLM trigger Apple's safety classifier and silently fail.

The root cause is scope: we asked the LLM to do structural graph synthesis. Foundation Models on-device is not reliably good at that.

## 2. Reframing

Conductor is a **natural language workflow creator** — prose in, executable pipeline out. It is not an agentic chatbot. The LLM is one narrow translator inside a larger deterministic system, not the brain.

The design rule: **the LLM is consulted last, on the smallest possible question, and its output is the narrowest possible grammar.**

## 3. Goals

**In scope for v2:**

- Accept a single natural-language sentence/paragraph from the user.
- Produce an ordered pipeline of verbs.
- Execute the pipeline, asking the user for any atom the pipeline needs that wasn't extracted from prose.
- Surface every step's status and result in SwiftUI.
- Prove the pattern works end-to-end on 4–5 demonstrator verbs.

**Explicitly out of scope for v2:**

- Workflow save/reload/replay (event log supports it structurally; UI does not expose it).
- Live/reactive projections (v2 folds on demand).
- Event schema versioning / upcasters.
- iOS/iPadOS polish (shared code works; surface is macOS-first).
- Editing a compiled pipeline in-place (re-prose and re-run for v2).
- Multi-turn conversation / chat history.
- More than ~5 verbs.

## 4. Architecture Overview

Four layers, in order of consultation:

```
User prose
    ↓
L1: NSDataDetector      →  URLs, numbers, dates (deterministic)
    ↓
L2: NLTagger            →  Verb lemmas, noun phrases (deterministic)
    ↓
L3: NLEmbedding         →  Fuzzy verb match (deterministic, on-device)
    ↓
L4: Foundation Models   →  Last-resort verb classification (enum only)
    ↓
Pipeline (ordered [Verb])
    ↓
Runtime  ──────────────►  Event Log (append-only)
    ↓                         ↑
Verb dispatch            Projections (folds)
    ↓                         ↓
Role-tagged queries  ────►  SwiftUI
    ↓
Auto-ask if unresolved
```

The LLM only runs at Layer 4, only on verbs that Layers 1–3 could not classify, and only outputs a `@Generable` list of enum cases. It never sees URLs, numbers, or user-provided query text.

## 5. Prose Processing (Layers 1–4)

### 5.1 Layer 1 — NSDataDetector

Apple-maintained, deterministic, on-device, microsecond-scale. Extracts:

- URLs → emits `AtomRecorded(role: "url", value: .url(u), source: .detector)`.
- Numbers → emits `AtomRecorded(role: <resolved-role>, value: .number(n), source: .detector)`. Role is resolved from immediate context — "find 3 papers" → role `"search.limit"`; "for 2 minutes" → role `"duration"` — using each verb's declared parameter roles.
- Dates → emits `AtomRecorded(role: <resolved-role>, value: .date(d), source: .detector)`.

### 5.2 Layer 2 — NLTagger

POS tagging + lemmatization + noun-phrase chunking. Apple-maintained, deterministic. Extracts:

- **Verb lemmas.** Each verb in the prose is lemmatized ("summarize", "summarized", "summarizing" → `summarize`) and matched against the verb catalog's lemma index. `find`, `look up`, and `search` all lemmatize to the `search` catalog entry.
- **Noun phrases.** Remaining NP spans (after removing detected URLs/numbers) are assigned to parameters by proximity. Each catalog verb declares which of its parameters accept free-text NPs (e.g. `search.terms`); the NP nearest in sentence order to the matched verb gets the declared role. Emits `AtomRecorded(role: <verb>.<param>, value: .text(np), source: .tagger)`.
- **Parameter aliases.** Each parameter declaration includes an alias dictionary (e.g. `search.target` accepts `"PubMed"`, `"pub med"`, `"arXiv"`, `"arxiv.org"`, `"web"`, `"google"`). Tokens and proper-noun spans are matched against every declared alias dictionary; hits emit `AtomRecorded(role: <verb>.<param>, value: .choice(namespace:, value:), source: .tagger)`.

### 5.3 Layer 3 — NLEmbedding

Static 300-dim word embeddings, on-device. Runs **only** when Layer 2 found a verb-position lemma that didn't match the catalog. Computes cosine similarity between the unknown verb and each catalog verb's representative lemma. If the best match exceeds a threshold (initial: 0.65), dispatches that verb.

Example: `"look into this paper"` → Layer 2 lemmatizes `look` with no match → Layer 3 computes `cosine("look into", "read") = 0.71` → dispatches `read`.

### 5.4 Layer 4 — Foundation Models

Runs only when Layers 1–3 cannot produce a verb list. Input: the original prose. Output:

```swift
@Generable
struct PipelineIntent {
    @Guide(description: "The verbs the user wants executed, in order.")
    let verbs: [Verb]
}

@Generable
enum Verb: String, CaseIterable {
    case read, summarize, search, extractClaims
}
```

The grammar forbids hallucinating unknown verbs. The LLM sees only the prose text — never parameters, never user data from prior events. Session is stateless (per CLAUDE.md rules).

## 6. Event Log

Append-only, in-memory, single source of truth.

### 6.1 Event types

```swift
protocol Event: Sendable {
    var id: UUID { get }
    var origin: Origin { get }
    var timestamp: Date { get }
}

struct Origin: Sendable {
    let stepID: UUID?         // nil when emitted during compile (L1–L4, needs-closure)
    let stepIndex: Int?
    let iteration: Int?       // for-each index, nil outside a loop
    let parentStepID: UUID?   // for nested for-each
}
```

Two event families:

**Atom events** — one generic type carrying user-provided / prose-extracted values.

```swift
enum AtomKind: Sendable, Hashable {
    case url, number, date, text
    case choice(namespace: String, cases: [String])  // enum-typed
}

enum AtomValue: Sendable, Hashable {
    case url(URL)
    case number(Double)
    case date(Date)
    case text(String)
    case choice(namespace: String, value: String)   // e.g. ("search.target", "pubMed")
}

enum AtomSource: Sendable {
    case detector   // L1
    case tagger     // L2
    case embedding  // L3
    case llm        // L4
    case userAsked  // runtime auto-ask
}

struct AtomRecorded: Event {
    let role: String           // e.g. "url", "search.target", "search.terms"
    let value: AtomValue
    let source: AtomSource
    let origin: Origin
}
```

**Verb-output events** — typed per verb, one case per distinct result shape.

- `ReadCompleted(body:, title:, url:)`
- `SummaryProduced(summary:, claims:, sentiment:, role:)`
- `SearchResults(papers:, target:)`
- `ClaimsExtracted(claims:)`
- `StepFailed(stepID:, error:)`

Adding a new verb with novel parameters adds zero event types. Only verbs whose output shape is structurally new (a table, a chart image, a user selection) introduce a new verb-output event. Input-side extensibility is free.

### 6.2 Log semantics

- **Append-only.** No mutation, no deletion, no compaction in v2.
- **Total order.** Events are ordered by append time.
- **Origin-tagged.** Every event knows which step produced it and which for-each iteration (if any) it belongs to.

## 7. Projections

Projections are pure functions over the log. v2 folds on demand — no memoization, no incremental updates.

```swift
func articleSummary(log: [Event]) -> SummaryProduced? {
    log.reversed().first {
        ($0 as? SummaryProduced)?.role == "articleSummary"
    } as? SummaryProduced
}

func pipelineStatus(log: [Event], plan: [Step]) -> [StepStatus] {
    plan.map { step in
        if log.contains(where: { $0.origin.stepID == step.id && $0 is StepFailed }) {
            return .failed
        } else if log.contains(where: { $0.origin.stepID == step.id }) {
            return .completed
        } else {
            return .idle
        }
    }
}
```

Projections are the read model. SwiftUI binds directly to functions over an `@Observable` log container.

## 8. Verbs

A verb is a declarative record: lemmas, parameter schemas, upstream-event needs, and a command handler.

```swift
protocol Verb: Sendable {
    static var name: String { get }
    static var lemmas: [String] { get }               // L2 match
    static var parameters: [VerbParameter] { get }    // atom-backed inputs
    static var needs: [UpstreamEventNeed] { get }     // prior verb outputs

    static func execute(
        resolved: ResolvedInputs,
        log: [Event]
    ) async throws -> [Event]
}

struct VerbParameter: Sendable {
    let role: String                  // namespaced: "search.target"
    let kind: AtomKind                // drives ask UI + alias matching
    let aliases: [String: String]     // token → canonical value (for .choice)
    let required: Bool
}

struct UpstreamEventNeed: Sendable {
    let eventTypes: [String]          // any of these event-type names satisfies
    let required: Bool
}

struct ResolvedInputs: Sendable {
    let atoms: [String: AtomValue]    // keyed by role
    let upstream: [Event]             // resolved prior-verb events
}
```

At dispatch, the runtime:
1. Resolves each `VerbParameter` by role against the `AtomRecorded` events in the log.
2. Resolves each `UpstreamEventNeed` against prior verb-output events.
3. If a required parameter is unresolved → auto-ask (UI variant chosen from the parameter's `AtomKind`).
4. If a required upstream event is missing → needs closure (§9) inserts a verb that produces it.

### 8.1 Verb catalog (v2 demonstrator)

1. **`read`**
   - parameters: `url` (`kind: .url`, required).
   - needs: none.
   - emits: `ReadCompleted`.

2. **`summarize`**
   - parameters: none.
   - needs: any of `[ReadCompleted, SearchResults]`, required.
   - emits: `SummaryProduced` with a role tag derived from the input source.

3. **`search`**
   - parameters:
     - `search.terms` (`kind: .text`, required; L2 fills from an adjacent NP).
     - `search.target` (`kind: .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web"])`, required; aliases cover "PubMed"/"pub med"/"arXiv"/"arxiv.org"/"web"/"google").
     - `search.limit` (`kind: .number`, optional; defaults to 5).
   - needs: none required; optionally satisfied by `ClaimsExtracted` (if present, supersedes `search.terms`).
   - emits: `SearchResults(papers:, target:)`.
   - backends are pluggable; v2 ships PubMed, arXiv, and a generic web search.

4. **`extract-claims`**
   - parameters: none.
   - needs: `SummaryProduced`, required.
   - emits: `ClaimsExtracted`.

`extract-claims` is the only verb that uses the LLM for its body (a narrow `@Generable` struct). All other verbs are pure I/O + deterministic parsing.

### 8.2 Parameter disambiguation

When a required parameter cannot be resolved from prose (no detector hit, no alias match, no prior event), the runtime asks the user before executing that step. The ask UI is chosen by `AtomKind`: `.url` → text field with URL validation; `.number` → stepper; `.date` → date picker; `.text` → text field; `.choice` → picker listing the declared cases. The LLM is never consulted to resolve parameter ambiguity — the user is the tiebreaker.

Extensibility: a new verb declares its parameters and is done. No new events, no new UI code, no new L1/L2 code.

## 9. Needs Closure

After Layers 1–4 produce a verb list, the compiler runs a deterministic closure pass:

```
for each verb V in the pipeline, in order:
  for each required UpstreamEventNeed N in V.needs:
    if the pipeline so far + the current log satisfies N:
      continue
    else if some catalog verb W emits an event matching N:
      insert W immediately before V
      recurse on W's needs and parameters
    else:
      fail — not satisfiable
  for each required VerbParameter P in V.parameters:
    if the log contains an AtomRecorded with role == P.role:
      continue
    else:
      mark P as "ask" — the runtime will prompt the user
```

This is why `summarize` alone in the prose yields a `[read, summarize]` pipeline: `summarize` needs a `ReadCompleted`-shaped event, and `read` is the catalog verb that produces it. If two verbs could satisfy a need, the compiler picks the one whose own needs and parameters are already satisfied; if still tied, it asks the user which source to use.

The LLM is not involved in closure. Closure is a graph search over the static catalog.

## 10. Control Flow

v2 has exactly one control construct: **for-each**.

When a verb's input is a collection (e.g., the papers from `SearchResults`) and the next step declares it needs a single element (e.g., `summarize` wants one body), the runtime wraps the next step in a for-each and emits events with `Origin.iteration` set. Multiple iterations' events coexist in the log without collision.

The LLM does not emit for-each. The runtime inserts it deterministically based on cardinality mismatch between an emitted collection event and the next step's need.

## 11. Runtime Flow (Worked Example)

User prose: *"Summarize the article at https://example.com about CRISPR and sickle-cell, and find 3 related PubMed papers."*

1. **L1** extracts URL `https://example.com` (role: `url`) and number `3` (role: `search.limit`, resolved because `find` → `search` is the nearest verb and `search.limit` is a declared `.number` parameter). Appends two `AtomRecorded` events.
2. **L2** finds verb lemmas `summarize`, `find` → catalog matches `summarize`, `search`. Extracts NP "CRISPR and sickle-cell" adjacent to `find` → appends `AtomRecorded(role: "search.terms", .text(...))`. The token "PubMed" matches `search.target`'s alias dictionary → appends `AtomRecorded(role: "search.target", .choice("search.target", "pubMed"))`.
3. **L3, L4** skipped.
4. L4 verb list: `[summarize, search]`. Needs closure (§9) prepends `read` because `summarize` needs a `ReadCompleted` and `read` is the catalog verb that emits one. Final pipeline: `[read, summarize, search]`.
5. Step 1 (`read`): resolves `url` atom from log → fetches → appends `ReadCompleted`.
6. Step 2 (`summarize`): resolves `ReadCompleted` → calls summarization → appends `SummaryProduced(role: "articleSummary")`.
7. Step 3 (`search`): resolves `search.terms`, `search.limit`, `search.target = .pubMed` from log → queries PubMed → appends `SearchResults(papers:, target: .pubMed)`.

Projections read by SwiftUI:
- `articleSummary()` → the summary from step 2.
- `searchResults()` → the 3 papers from step 3, tagged with their source.
- `pipelineStatus()` → `[done, done, done]`.

The LLM was not invoked.

**Variant (target ambiguous):** if the prose had been *"…and find 3 related papers"*, L2 would produce no `AtomRecorded` for role `search.target`. At step 3, the runtime would pause and show a picker (driven by the parameter's `.choice` kind): *"Where should I search?"* with options `PubMed`, `arXiv`, `Web`. The user's pick is appended as `AtomRecorded(role: "search.target", .choice(...), source: .userAsked)`, and the step proceeds.

## 12. Auto-Ask

When a required `VerbParameter` cannot be resolved from the log, the runtime pauses and renders an ask UI. The UI variant is chosen by the parameter's `AtomKind`:

- `.url` → text field with URL validation.
- `.number` → number stepper.
- `.date` → date picker.
- `.text` → text field.
- `.choice(namespace:, cases:)` → picker listing the declared cases.

On submission, the runtime appends `AtomRecorded(role:, value:, source: .userAsked)` and resumes.

Ask insertion is a runtime behavior, not an LLM output. The LLM cannot forget to insert an ask, and it is never consulted to guess a missing parameter — the user is always the tiebreaker.

## 13. UI Surface (macOS, minimal)

One window, three regions:

1. **Prose input** (top) — single text field, "Run" button.
2. **Pipeline view** (middle) — ordered list of steps with status chips (idle / running / done / failed). Each step is tappable; tapping reveals the events it produced and the atoms it consumed.
3. **Result view** (bottom) — renders the output projections (summary text, paper list).

No chat history, no side panels, no workflow library. Every user action shows state per the CLAUDE.md UX rule.

## 14. File Structure

```
Conductor/
  ConductorApp.swift
  ContentView.swift                   // 3-region layout
  Models/
    Event.swift                       // protocol + Origin
    Atom.swift                        // AtomKind + AtomValue + AtomSource enums
    Events/
      AtomRecorded.swift              // generic user-input event
      ReadCompleted.swift
      SummaryProduced.swift
      SearchResults.swift
      ClaimsExtracted.swift
      StepFailed.swift
    Verb.swift                        // protocol + VerbParameter + UpstreamEventNeed
    Step.swift                        // runtime step instance
    PipelineIntent.swift              // LLM @Generable output
  Services/
    ProseCompiler.swift               // orchestrates L1→L4
    Layer1DataDetector.swift
    Layer2Tagger.swift
    Layer3Embedding.swift
    Layer4IntentSession.swift         // Foundation Models, stateless
    Runtime.swift                     // executes pipeline over log
    EventLog.swift                    // @Observable container
    Projections.swift                 // folds
    Verbs/
      ReadVerb.swift
      SummarizeVerb.swift
      SearchVerb.swift                // dispatches to a backend based on target
      ExtractClaimsVerb.swift
    SearchBackends/
      SearchBackend.swift             // protocol
      PubMedBackend.swift
      ArxivBackend.swift
      WebBackend.swift
  Views/
    ProseInputView.swift
    PipelineView.swift
    StepRowView.swift
    ResultView.swift
    AskView.swift
```

Per the memory rule: each event case and its `@Generable` payload share a file.

## 15. Testing Strategy

Swift Testing (`import Testing`, `@Test`, `#expect`).

- **L1–L3 are unit-tested offline.** No LLM, no network. Input prose, expected events. Tens of cases each.
- **L4 has contract tests.** The `@Generable` output shape is verified; the actual model call is mocked by a fake `LanguageModelSession` that returns pre-seeded enum lists.
- **Verbs are pure from `(log, resolved) → [Event]`.** Each verb gets a suite that feeds a synthetic log and checks emitted events. Network I/O in `read` and each `search` backend is behind a protocol and mocked.
- **Runtime gets integration tests.** End-to-end prose → final log, asserting the log contains the expected events in order. No real LLM, no real network.
- **Projections are trivially unit-testable** — pure functions.

## 16. How This Sidesteps v1 Failure Modes

| v1 failure | v2 prevention |
|---|---|
| Cycles in pipeline | LLM doesn't emit wiring. Pipeline is a list. |
| Missing ask cell | Runtime auto-asks on unresolved required query. |
| Wrong wiring | Role-tagged queries; deterministic resolution. |
| Hallucinated cell kinds / fields | Verb is an enum; grammar forbids unknown values. |
| Hallucinated URLs / numbers | Extracted by NSDataDetector before LLM runs. |
| Content-safety filter trips | LLM prompt contains no user keywords in the common case. |
| Context window pressure | LLM input is a short clause; output is an enum list. |
| Multiple summarize collisions | Append-only log + role-tagged origins preserve all results. |

## 17. What We Are Explicitly Deferring

- **Workflow persistence.** Event log is in-memory. When the window closes, state is gone. Re-run from prose to reproduce.
- **Live/reactive projections.** O(n) per read is fine for < 100-event sessions.
- **Event versioning.** If a payload shape changes, old sessions (in-memory only) are unaffected.
- **Pipeline editing.** No drag-to-reorder, no inline parameter tweak. Edit the prose and re-run.
- **iOS surface polish.** Shared code compiles on iOS; UI is tuned for macOS only.
- **Catalog growth.** 5 verbs is enough to prove the pattern. Catalog expansion is post-v2.

## 18. Success Criteria

v2 succeeds if, on macOS, a user can:

1. Type a sentence describing a 2–3 step research task.
2. See the pipeline compiled deterministically (no LLM call in the common case).
3. Be asked for any missing input (URL, number, search terms).
4. See each step execute with visible status.
5. See the final result (summary text, paper list).

…and if, across a test corpus of ~30 prose inputs, the ratio of LLM-free compilation to LLM-assisted compilation is high enough to demonstrate the four-layer pattern's value. Target: ≥ 70% of corpus compiles without Layer 4.
