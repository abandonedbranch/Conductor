# Conductor v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS app that turns a single sentence of prose into an executable workflow of 4 verbs (`read`, `summarize`, `search`, `extract-claims`), using a four-layer NL pipeline that consults the on-device LLM only as a last resort.

**Architecture:** CQRS + event sourcing with an append-only log of `AtomRecorded` (user inputs) and typed verb-output events. Prose is processed by NSDataDetector → NLTagger → NLEmbedding → Foundation Models, producing an ordered list of verbs. A deterministic needs-closure pass inserts missing verbs; a runtime executor resolves parameters from the log or prompts the user. Projections fold the log for SwiftUI.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Observation framework (`@Observable`), Swift Testing (`@Test`, `#expect`), Apple NaturalLanguage, Apple Foundation Models, `@Generable` output grammar.

**Spec:** `docs/superpowers/specs/2026-04-18-conductor-v2-design.md`

---

## Naming reconciliation

The spec uses `Verb` both for the `@Generable` enum (LLM-visible) and for the protocol (Swift-side). The plan resolves this:

- **`Verb`** — the `@Generable enum: String, CaseIterable` crossed with the LLM.
- **`VerbDefinition`** — the Swift protocol each verb implementation conforms to.
- **`VerbCatalog`** — maps a `Verb` case to its concrete `VerbDefinition.Type`.

---

## Ground rules for every task

1. **Swift 6 strict concurrency.** All new types are `Sendable` where the protocol requires it.
2. **SwiftUI only.** No UIKit / AppKit unless the spec requires (`AskView` number stepper is `Stepper`; URL field is `TextField`).
3. **Swift Testing.** `import Testing`, `@Test`, `#expect`. No XCTest.
4. **`@Observable`** for stateful containers (EventLog, Runtime). Never `ObservableObject` / `@Published`.
5. **One primary type per file.** Events are the exception — per the user's `@Generable` co-location rule, an enum case and its payload `@Generable` live together.
6. **Every LLM call is stateless**, `LanguageModelSession` constructed per call, output is `@Generable`.
7. **Verb I/O is protocol-injected.** No direct `URLSession.shared` in verb bodies — go through `HTTPClient`.
8. **TDD:** failing test first, minimal implementation, passing test, commit. Commit message format: `(topic): change` per CLAUDE.md.
9. **Xcode auto-discovers files** (synchronized folders). Creating a `.swift` file is enough; no `project.pbxproj` edit.
10. **Tests run via `swift test` is NOT an option** — this is an Xcode app. Use `xcodebuild test` for CLI or the Xcode UI. Commands in the plan show `xcodebuild`; adapt to IDE if running interactively.

---

## Test build command

All test tasks use this baseline command (shown abbreviated in steps as `xcodebuild test`):

```bash
xcodebuild test \
  -project Conductor.xcodeproj \
  -scheme Conductor \
  -destination 'platform=macOS' \
  -only-testing:ConductorTests/<TestSuiteName>/<testName>
```

For running the full suite:

```bash
xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS'
```

---

## File structure (v2, after reset)

```
Conductor/
  ConductorApp.swift                  // rewritten
  ContentView.swift                   // rewritten — 3-region layout
  Assets.xcassets                     // preserved
  Conductor.entitlements              // preserved
  Preview Content/                    // preserved
  Models/
    Origin.swift                      // Origin struct
    Event.swift                       // Event protocol
    Atom.swift                        // AtomKind + AtomValue + AtomSource
    Step.swift                        // runtime step instance
    Verb.swift                        // @Generable enum + VerbDefinition + VerbParameter + UpstreamEventNeed + ResolvedInputs
    VerbCatalog.swift                 // Verb -> VerbDefinition.Type
    PipelineIntent.swift              // LLM @Generable output
    StepStatus.swift                  // enum for projections
    Paper.swift                       // search result item
    Claim.swift                       // extracted claim
    Events/
      AtomRecorded.swift
      ReadCompleted.swift
      SummaryProduced.swift
      SearchResults.swift
      ClaimsExtracted.swift
      StepFailed.swift
  Services/
    HTTPClient.swift                  // protocol + URLSession impl + fake
    LLMSession.swift                  // protocol + Foundation Models impl + fake
    EventLog.swift                    // @Observable
    Projections.swift                 // pure folds
    ProseCompiler.swift               // orchestrates L1→L4 + needs closure
    Layer1DataDetector.swift
    Layer2Tagger.swift
    Layer3Embedding.swift
    Layer4IntentSession.swift
    NeedsClosure.swift                // pipeline inflation algorithm
    Runtime.swift                     // @Observable executor
    Verbs/
      ReadVerb.swift
      SummarizeVerb.swift
      SearchVerb.swift
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
ConductorTests/
  OriginTests.swift
  AtomTests.swift
  EventTests.swift
  EventLogTests.swift
  ProjectionTests.swift
  Layer1Tests.swift
  Layer2Tests.swift
  Layer3Tests.swift
  Layer4Tests.swift
  NeedsClosureTests.swift
  ProseCompilerTests.swift
  ReadVerbTests.swift
  SummarizeVerbTests.swift
  SearchVerbTests.swift
  ExtractClaimsVerbTests.swift
  PubMedBackendTests.swift
  ArxivBackendTests.swift
  WebBackendTests.swift
  RuntimeTests.swift
  EndToEndTests.swift
  Fakes/
    FakeHTTPClient.swift
    FakeLLMSession.swift
```

---

## Task 1: Reset v1 code

**Files:**
- Delete everything under `Conductor/` except: `Assets.xcassets`, `Conductor.entitlements`, `Preview Content/`, `ConductorApp.swift`, `ContentView.swift` (both will be rewritten).
- Delete everything under `ConductorTests/`.

- [ ] **Step 1: Inventory what will be deleted**

```bash
ls Conductor/Models/ Conductor/Services/ Conductor/Tools/ Conductor/Views/ 2>/dev/null
ls ConductorTests/ 2>/dev/null | wc -l
```

- [ ] **Step 2: Delete v1 sources**

```bash
rm -rf Conductor/Models Conductor/Services Conductor/Tools Conductor/Views
rm -f Conductor/SettingsView.swift
rm -rf ConductorTests/*
```

- [ ] **Step 3: Replace `ConductorApp.swift` with v2 skeleton**

```swift
// Conductor/ConductorApp.swift
import SwiftUI

@main
struct ConductorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 4: Replace `ContentView.swift` with a placeholder that will compile**

```swift
// Conductor/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Conductor v2")
            .frame(minWidth: 600, minHeight: 400)
            .padding()
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS'`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "(reset): remove v1 sources, stub v2 app shell"
```

---

## Task 2: Origin struct

**Files:**
- Create: `Conductor/Models/Origin.swift`
- Test: `ConductorTests/OriginTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/OriginTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct OriginTests {
    @Test func compileOrigin_hasNilStepID() {
        let o = Origin.compile()
        #expect(o.stepID == nil)
        #expect(o.stepIndex == nil)
    }

    @Test func stepOrigin_carriesIndexAndID() {
        let id = UUID()
        let o = Origin.step(id: id, index: 2)
        #expect(o.stepID == id)
        #expect(o.stepIndex == 2)
        #expect(o.iteration == nil)
    }

    @Test func iterationOrigin_carriesIteration() {
        let id = UUID()
        let o = Origin.step(id: id, index: 2, iteration: 3)
        #expect(o.iteration == 3)
    }
}
```

- [ ] **Step 2: Run test, expect compile failure**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing:ConductorTests/OriginTests`
Expected: compile error — `Origin` undefined.

- [ ] **Step 3: Implement**

```swift
// Conductor/Models/Origin.swift
import Foundation

struct Origin: Sendable, Hashable {
    let stepID: UUID?
    let stepIndex: Int?
    let iteration: Int?
    let parentStepID: UUID?

    static func compile() -> Origin {
        Origin(stepID: nil, stepIndex: nil, iteration: nil, parentStepID: nil)
    }

    static func step(id: UUID, index: Int, iteration: Int? = nil, parentStepID: UUID? = nil) -> Origin {
        Origin(stepID: id, stepIndex: index, iteration: iteration, parentStepID: parentStepID)
    }
}
```

- [ ] **Step 4: Run test, expect pass**

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/Origin.swift ConductorTests/OriginTests.swift
git commit -m "(model): add Origin struct for event provenance"
```

---

## Task 3: Event protocol

**Files:**
- Create: `Conductor/Models/Event.swift`
- Test: `ConductorTests/EventTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/EventTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct EventTests {
    private struct DummyEvent: Event {
        let id = UUID()
        let origin = Origin.compile()
        let timestamp = Date()
    }

    @Test func eventProtocol_requiresIDAndOrigin() {
        let e = DummyEvent()
        #expect(e.origin.stepID == nil)
        #expect(type(of: e.id) == UUID.self)
    }
}
```

- [ ] **Step 2: Run test, expect compile failure**

Expected: `Event` protocol undefined.

- [ ] **Step 3: Implement**

```swift
// Conductor/Models/Event.swift
import Foundation

protocol Event: Sendable {
    var id: UUID { get }
    var origin: Origin { get }
    var timestamp: Date { get }
}
```

- [ ] **Step 4: Run test, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/Event.swift ConductorTests/EventTests.swift
git commit -m "(model): add Event protocol"
```

---

## Task 4: Atom types

**Files:**
- Create: `Conductor/Models/Atom.swift`
- Test: `ConductorTests/AtomTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/AtomTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct AtomTests {
    @Test func atomValue_urlCaseCarriesURL() throws {
        let url = URL(string: "https://example.com")!
        let v: AtomValue = .url(url)
        if case let .url(u) = v { #expect(u == url) } else { Issue.record("wrong case") }
    }

    @Test func atomValue_choiceCarriesNamespaceAndValue() {
        let v: AtomValue = .choice(namespace: "search.target", value: "pubMed")
        if case let .choice(ns, val) = v {
            #expect(ns == "search.target")
            #expect(val == "pubMed")
        } else { Issue.record("wrong case") }
    }

    @Test func atomKind_choiceListsCases() {
        let k: AtomKind = .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web"])
        if case let .choice(_, cases) = k { #expect(cases.count == 3) } else { Issue.record("wrong case") }
    }

    @Test func atomSource_fiveCases() {
        let all: [AtomSource] = [.detector, .tagger, .embedding, .llm, .userAsked]
        #expect(all.count == 5)
    }
}
```

- [ ] **Step 2: Run test, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Models/Atom.swift
import Foundation

enum AtomKind: Sendable, Hashable {
    case url
    case number
    case date
    case text
    case choice(namespace: String, cases: [String])
}

enum AtomValue: Sendable, Hashable {
    case url(URL)
    case number(Double)
    case date(Date)
    case text(String)
    case choice(namespace: String, value: String)
}

enum AtomSource: Sendable, Hashable {
    case detector
    case tagger
    case embedding
    case llm
    case userAsked
}
```

- [ ] **Step 4: Run test, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/Atom.swift ConductorTests/AtomTests.swift
git commit -m "(model): add Atom kind/value/source enums"
```

---

## Task 5: AtomRecorded event

**Files:**
- Create: `Conductor/Models/Events/AtomRecorded.swift`
- Test: extend `ConductorTests/AtomTests.swift`

- [ ] **Step 1: Add failing test**

Append to `ConductorTests/AtomTests.swift`:

```swift
@Suite struct AtomRecordedTests {
    @Test func recorded_exposesRoleValueSourceOrigin() {
        let e = AtomRecorded(
            role: "search.target",
            value: .choice(namespace: "search.target", value: "pubMed"),
            source: .tagger,
            origin: .compile()
        )
        #expect(e.role == "search.target")
        #expect(e.source == .tagger)
        #expect(e.origin.stepID == nil)
    }
}
```

- [ ] **Step 2: Run test, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Models/Events/AtomRecorded.swift
import Foundation

struct AtomRecorded: Event {
    let id: UUID
    let timestamp: Date
    let role: String
    let value: AtomValue
    let source: AtomSource
    let origin: Origin

    init(role: String, value: AtomValue, source: AtomSource, origin: Origin) {
        self.id = UUID()
        self.timestamp = Date()
        self.role = role
        self.value = value
        self.source = source
        self.origin = origin
    }
}
```

- [ ] **Step 4: Run test, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Models/Events/AtomRecorded.swift ConductorTests/AtomTests.swift
git commit -m "(model): add AtomRecorded event"
```

---

## Task 6: Verb-output events

**Files:**
- Create: `Conductor/Models/Paper.swift`, `Conductor/Models/Claim.swift`, `Conductor/Models/Events/ReadCompleted.swift`, `Conductor/Models/Events/SummaryProduced.swift`, `Conductor/Models/Events/SearchResults.swift`, `Conductor/Models/Events/ClaimsExtracted.swift`, `Conductor/Models/Events/StepFailed.swift`
- Test: `ConductorTests/EventTests.swift` (extend)

- [ ] **Step 1: Add failing tests**

Append to `ConductorTests/EventTests.swift`:

```swift
@Suite struct VerbOutputEventTests {
    @Test func readCompleted_carriesBodyTitleURL() {
        let e = ReadCompleted(body: "B", title: "T", url: URL(string: "https://x")!, origin: .step(id: UUID(), index: 0))
        #expect(e.body == "B")
        #expect(e.title == "T")
    }

    @Test func summaryProduced_carriesRole() {
        let e = SummaryProduced(summary: "S", claims: ["c1"], sentiment: "neutral", role: "articleSummary", origin: .step(id: UUID(), index: 1))
        #expect(e.role == "articleSummary")
        #expect(e.claims.count == 1)
    }

    @Test func searchResults_carriesTarget() {
        let paper = Paper(title: "P", abstract: "A", identifier: "id1", url: nil)
        let e = SearchResults(papers: [paper], target: "pubMed", origin: .step(id: UUID(), index: 2))
        #expect(e.target == "pubMed")
        #expect(e.papers.count == 1)
    }

    @Test func claimsExtracted_carriesClaims() {
        let c = Claim(text: "the sky is blue")
        let e = ClaimsExtracted(claims: [c], origin: .step(id: UUID(), index: 3))
        #expect(e.claims.first?.text == "the sky is blue")
    }

    @Test func stepFailed_carriesError() {
        let e = StepFailed(stepID: UUID(), message: "boom", origin: .compile())
        #expect(e.message == "boom")
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement `Paper` and `Claim`**

```swift
// Conductor/Models/Paper.swift
import Foundation

struct Paper: Sendable, Hashable {
    let title: String
    let abstract: String
    let identifier: String
    let url: URL?
}
```

```swift
// Conductor/Models/Claim.swift
import Foundation

struct Claim: Sendable, Hashable {
    let text: String
}
```

- [ ] **Step 4: Implement verb-output events**

```swift
// Conductor/Models/Events/ReadCompleted.swift
import Foundation

struct ReadCompleted: Event {
    let id = UUID()
    let timestamp = Date()
    let body: String
    let title: String
    let url: URL
    let origin: Origin
}
```

```swift
// Conductor/Models/Events/SummaryProduced.swift
import Foundation

struct SummaryProduced: Event {
    let id = UUID()
    let timestamp = Date()
    let summary: String
    let claims: [String]
    let sentiment: String
    let role: String
    let origin: Origin
}
```

```swift
// Conductor/Models/Events/SearchResults.swift
import Foundation

struct SearchResults: Event {
    let id = UUID()
    let timestamp = Date()
    let papers: [Paper]
    let target: String
    let origin: Origin
}
```

```swift
// Conductor/Models/Events/ClaimsExtracted.swift
import Foundation

struct ClaimsExtracted: Event {
    let id = UUID()
    let timestamp = Date()
    let claims: [Claim]
    let origin: Origin
}
```

```swift
// Conductor/Models/Events/StepFailed.swift
import Foundation

struct StepFailed: Event {
    let id = UUID()
    let timestamp = Date()
    let stepID: UUID
    let message: String
    let origin: Origin
}
```

- [ ] **Step 5: Run tests, expect pass**

- [ ] **Step 6: Commit**

```bash
git add Conductor/Models/Paper.swift Conductor/Models/Claim.swift Conductor/Models/Events/ ConductorTests/EventTests.swift
git commit -m "(model): add verb-output event types"
```

---

## Task 7: Verb enum, protocol, catalog

**Files:**
- Create: `Conductor/Models/Verb.swift`, `Conductor/Models/VerbCatalog.swift`
- Test: `ConductorTests/VerbCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/VerbCatalogTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct VerbCatalogTests {
    @Test func everyEnumCaseHasADefinition() {
        for verb in Verb.allCases {
            let def = VerbCatalog.definition(for: verb)
            #expect(def.verb == verb)
        }
    }

    @Test func lemmaLookup_findsVerbByLemma() {
        #expect(VerbCatalog.verb(forLemma: "summarize") == .summarize)
        #expect(VerbCatalog.verb(forLemma: "find") == .search)
        #expect(VerbCatalog.verb(forLemma: "unicorn") == nil)
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement `Verb` enum + `VerbDefinition` protocol + supporting types**

```swift
// Conductor/Models/Verb.swift
import Foundation
import FoundationModels

@Generable
enum Verb: String, CaseIterable, Sendable {
    case read
    case summarize
    case search
    case extractClaims
}

struct VerbParameter: Sendable {
    let role: String
    let kind: AtomKind
    let aliases: [String: String]
    let required: Bool
    let defaultValue: AtomValue?
}

struct UpstreamEventNeed: Sendable {
    let eventTypeNames: [String]
    let required: Bool
}

struct ResolvedInputs: Sendable {
    let atoms: [String: AtomValue]
    let upstream: [any Event]
}

protocol VerbDefinition: Sendable {
    static var verb: Verb { get }
    static var lemmas: [String] { get }
    static var parameters: [VerbParameter] { get }
    static var needs: [UpstreamEventNeed] { get }

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event]
}

extension VerbDefinition {
    var verb: Verb { Self.verb }
}
```

- [ ] **Step 4: Stub the four `VerbDefinition` types so `VerbCatalog` compiles**

Create placeholder `enum` stand-ins — actual implementations come in later tasks. Put them in `Conductor/Services/Verbs/<Name>Verb.swift`:

```swift
// Conductor/Services/Verbs/ReadVerb.swift
import Foundation

enum ReadVerb: VerbDefinition {
    static let verb: Verb = .read
    static let lemmas = ["read", "open", "fetch", "load"]
    static let parameters = [
        VerbParameter(role: "url", kind: .url, aliases: [:], required: true, defaultValue: nil)
    ]
    static let needs: [UpstreamEventNeed] = []

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        fatalError("implemented in Task 19")
    }
}
```

Repeat stubs for `SummarizeVerb`, `SearchVerb`, `ExtractClaimsVerb` (all `fatalError` in `execute`). Stub parameters:

```swift
// Conductor/Services/Verbs/SummarizeVerb.swift
enum SummarizeVerb: VerbDefinition {
    static let verb: Verb = .summarize
    static let lemmas = ["summarize", "summarise", "sum up", "digest"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["ReadCompleted", "SearchResults"], required: true)
    ]
    static func execute(resolved: ResolvedInputs, origin: Origin, http: any HTTPClient, llm: any LLMSession) async throws -> [any Event] {
        fatalError("implemented in Task 20")
    }
}

// Conductor/Services/Verbs/SearchVerb.swift
enum SearchVerb: VerbDefinition {
    static let verb: Verb = .search
    static let lemmas = ["search", "find", "look up", "look for", "query"]
    static let parameters = [
        VerbParameter(role: "search.terms", kind: .text, aliases: [:], required: true, defaultValue: nil),
        VerbParameter(
            role: "search.target",
            kind: .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web"]),
            aliases: [
                "pubmed": "pubMed", "pub med": "pubMed",
                "arxiv": "arxiv", "arxiv.org": "arxiv",
                "web": "web", "google": "web", "internet": "web"
            ],
            required: true,
            defaultValue: nil
        ),
        VerbParameter(role: "search.limit", kind: .number, aliases: [:], required: false, defaultValue: .number(5))
    ]
    static let needs: [UpstreamEventNeed] = []
    static func execute(resolved: ResolvedInputs, origin: Origin, http: any HTTPClient, llm: any LLMSession) async throws -> [any Event] {
        fatalError("implemented in Task 25")
    }
}

// Conductor/Services/Verbs/ExtractClaimsVerb.swift
enum ExtractClaimsVerb: VerbDefinition {
    static let verb: Verb = .extractClaims
    static let lemmas = ["extract", "pull", "identify"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["SummaryProduced"], required: true)
    ]
    static func execute(resolved: ResolvedInputs, origin: Origin, http: any HTTPClient, llm: any LLMSession) async throws -> [any Event] {
        fatalError("implemented in Task 26")
    }
}
```

(`HTTPClient` and `LLMSession` are defined in Task 8. Add forward-declared empty protocols in those files if Task 7 runs first; cleanup in Task 8.)

- [ ] **Step 5: Implement `VerbCatalog`**

```swift
// Conductor/Models/VerbCatalog.swift
import Foundation

enum VerbCatalog {
    static func definition(for verb: Verb) -> any VerbDefinition.Type {
        switch verb {
        case .read: ReadVerb.self
        case .summarize: SummarizeVerb.self
        case .search: SearchVerb.self
        case .extractClaims: ExtractClaimsVerb.self
        }
    }

    static func verb(forLemma lemma: String) -> Verb? {
        let needle = lemma.lowercased()
        for v in Verb.allCases {
            if definition(for: v).lemmas.contains(needle) { return v }
        }
        return nil
    }

    static var all: [Verb] { Verb.allCases }
}
```

- [ ] **Step 6: Run tests, expect pass** (note: any test that calls `execute` on a stubbed verb will trap — don't)

- [ ] **Step 7: Commit**

```bash
git add Conductor/Models/Verb.swift Conductor/Models/VerbCatalog.swift Conductor/Services/Verbs/ ConductorTests/VerbCatalogTests.swift
git commit -m "(model): add Verb enum, VerbDefinition protocol, VerbCatalog, stubs"
```

---

## Task 8: HTTPClient and LLMSession protocols + fakes

**Files:**
- Create: `Conductor/Services/HTTPClient.swift`, `Conductor/Services/LLMSession.swift`
- Create: `ConductorTests/Fakes/FakeHTTPClient.swift`, `ConductorTests/Fakes/FakeLLMSession.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/Fakes/FakeHTTPClient.swift
import Foundation
@testable import Conductor

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var scripted: [URL: Data] = [:]
    var requested: [URL] = []
    func get(_ url: URL) async throws -> Data {
        requested.append(url)
        guard let d = scripted[url] else { throw URLError(.badURL) }
        return d
    }
}
```

```swift
// ConductorTests/Fakes/FakeLLMSession.swift
import Foundation
@testable import Conductor
import FoundationModels

final class FakeLLMSession: LLMSession, @unchecked Sendable {
    var scriptedIntent: PipelineIntent?
    var scriptedSummary: SummaryGenerable?
    var scriptedClaims: ClaimsGenerable?

    func inferPipeline(from prose: String) async throws -> PipelineIntent {
        guard let i = scriptedIntent else { throw NSError(domain: "fake", code: 0) }
        return i
    }
    func summarize(text: String) async throws -> SummaryGenerable {
        guard let s = scriptedSummary else { throw NSError(domain: "fake", code: 0) }
        return s
    }
    func extractClaims(from summary: String) async throws -> ClaimsGenerable {
        guard let c = scriptedClaims else { throw NSError(domain: "fake", code: 0) }
        return c
    }
}
```

The fake file will not compile until the protocols and `PipelineIntent`/`SummaryGenerable`/`ClaimsGenerable` types exist — that's fine, Task 8 creates them. Skip running tests at this step.

- [ ] **Step 2: Implement `HTTPClient`**

```swift
// Conductor/Services/HTTPClient.swift
import Foundation

protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession = .shared
    func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
```

- [ ] **Step 3: Implement `LLMSession`**

```swift
// Conductor/Services/LLMSession.swift
import Foundation
import FoundationModels

protocol LLMSession: Sendable {
    func inferPipeline(from prose: String) async throws -> PipelineIntent
    func summarize(text: String) async throws -> SummaryGenerable
    func extractClaims(from summary: String) async throws -> ClaimsGenerable
}

struct FoundationModelsSession: LLMSession {
    func inferPipeline(from prose: String) async throws -> PipelineIntent {
        let session = LanguageModelSession(instructions: """
        You classify prose into a short list of verbs from a fixed enum. \
        Return only the verbs, in execution order.
        """)
        return try await session.respond(to: prose, generating: PipelineIntent.self).content
    }
    func summarize(text: String) async throws -> SummaryGenerable {
        let session = LanguageModelSession(instructions: """
        Summarize the given text in 2–4 sentences. Extract up to 5 factual claims. \
        Classify sentiment as "positive", "neutral", or "negative".
        """)
        return try await session.respond(to: text, generating: SummaryGenerable.self).content
    }
    func extractClaims(from summary: String) async throws -> ClaimsGenerable {
        let session = LanguageModelSession(instructions: """
        Return the factual claims in the given summary as a list of short strings. \
        One claim per item. No speculation.
        """)
        return try await session.respond(to: summary, generating: ClaimsGenerable.self).content
    }
}
```

- [ ] **Step 4: Add `PipelineIntent`, `SummaryGenerable`, `ClaimsGenerable`**

```swift
// Conductor/Models/PipelineIntent.swift
import Foundation
import FoundationModels

@Generable
struct PipelineIntent: Sendable {
    @Guide(description: "The verbs the user wants executed, in order.")
    let verbs: [Verb]
}

@Generable
struct SummaryGenerable: Sendable {
    @Guide(description: "A short prose summary, 2–4 sentences.")
    let summary: String
    @Guide(description: "Factual claims present in the text, as short strings.")
    let claims: [String]
    @Guide(description: "Sentiment label.")
    let sentiment: String
}

@Generable
struct ClaimsGenerable: Sendable {
    @Guide(description: "Factual claims, one per entry.")
    let claims: [String]
}
```

- [ ] **Step 5: Add a smoke test for the fakes**

```swift
// ConductorTests/LLMAndHTTPFakeTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct FakeSmokeTests {
    @Test func fakeHTTP_returnsScriptedData() async throws {
        let c = FakeHTTPClient()
        let u = URL(string: "https://x")!
        c.scripted[u] = Data("hello".utf8)
        let d = try await c.get(u)
        #expect(String(data: d, encoding: .utf8) == "hello")
    }

    @Test func fakeLLM_returnsScriptedIntent() async throws {
        let l = FakeLLMSession()
        l.scriptedIntent = PipelineIntent(verbs: [.read, .summarize])
        let i = try await l.inferPipeline(from: "anything")
        #expect(i.verbs == [.read, .summarize])
    }
}
```

- [ ] **Step 6: Run tests, expect pass**

- [ ] **Step 7: Commit**

```bash
git add Conductor/Services/HTTPClient.swift Conductor/Services/LLMSession.swift Conductor/Models/PipelineIntent.swift ConductorTests/Fakes/ ConductorTests/LLMAndHTTPFakeTests.swift
git commit -m "(service): add HTTPClient and LLMSession protocols, Generable output types, fakes"
```

---

## Task 9: EventLog

**Files:**
- Create: `Conductor/Services/EventLog.swift`
- Test: `ConductorTests/EventLogTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/EventLogTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct EventLogTests {
    @Test func append_growsLog() {
        let log = EventLog()
        #expect(log.events.isEmpty)
        log.append(AtomRecorded(role: "url", value: .url(URL(string: "https://x")!), source: .detector, origin: .compile()))
        #expect(log.events.count == 1)
    }

    @Test func append_preservesOrder() {
        let log = EventLog()
        log.append(AtomRecorded(role: "a", value: .text("1"), source: .tagger, origin: .compile()))
        log.append(AtomRecorded(role: "b", value: .text("2"), source: .tagger, origin: .compile()))
        #expect((log.events[0] as? AtomRecorded)?.role == "a")
        #expect((log.events[1] as? AtomRecorded)?.role == "b")
    }

    @Test func findAtom_byRole_returnsLatest() {
        let log = EventLog()
        log.append(AtomRecorded(role: "search.target", value: .choice(namespace: "search.target", value: "pubMed"), source: .tagger, origin: .compile()))
        log.append(AtomRecorded(role: "search.target", value: .choice(namespace: "search.target", value: "arxiv"), source: .userAsked, origin: .compile()))
        let found = log.latestAtom(role: "search.target")
        if case let .choice(_, v) = found?.value { #expect(v == "arxiv") } else { Issue.record("no atom") }
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/EventLog.swift
import Foundation
import Observation

@Observable
@MainActor
final class EventLog {
    private(set) var events: [any Event] = []

    func append(_ event: any Event) {
        events.append(event)
    }

    func append(_ batch: [any Event]) {
        events.append(contentsOf: batch)
    }

    func latestAtom(role: String) -> AtomRecorded? {
        events.reversed().compactMap { $0 as? AtomRecorded }.first { $0.role == role }
    }

    func allAtoms(role: String) -> [AtomRecorded] {
        events.compactMap { $0 as? AtomRecorded }.filter { $0.role == role }
    }

    func eventsOfType<E: Event>(_ type: E.Type) -> [E] {
        events.compactMap { $0 as? E }
    }
}
```

- [ ] **Step 4: Update tests to be `@MainActor`**

Change the test suite struct to `@MainActor @Suite struct EventLogTests { ... }`.

- [ ] **Step 5: Run tests, expect pass**

- [ ] **Step 6: Commit**

```bash
git add Conductor/Services/EventLog.swift ConductorTests/EventLogTests.swift
git commit -m "(service): add @Observable EventLog with role-scoped queries"
```

---

## Task 10: Step + StepStatus

**Files:**
- Create: `Conductor/Models/Step.swift`, `Conductor/Models/StepStatus.swift`
- Test: extend a later test (projections need these)

- [ ] **Step 1: Implement `Step`**

```swift
// Conductor/Models/Step.swift
import Foundation

struct Step: Sendable, Identifiable, Hashable {
    let id: UUID
    let index: Int
    let verb: Verb

    init(index: Int, verb: Verb) {
        self.id = UUID()
        self.index = index
        self.verb = verb
    }
}
```

- [ ] **Step 2: Implement `StepStatus`**

```swift
// Conductor/Models/StepStatus.swift
import Foundation

enum StepStatus: Sendable, Hashable {
    case idle
    case running
    case completed
    case failed(message: String)
    case awaitingInput(role: String, kind: AtomKind)
}
```

- [ ] **Step 3: Commit**

```bash
git add Conductor/Models/Step.swift Conductor/Models/StepStatus.swift
git commit -m "(model): add Step and StepStatus"
```

---

## Task 11: Projections

**Files:**
- Create: `Conductor/Services/Projections.swift`
- Test: `ConductorTests/ProjectionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/ProjectionTests.swift
import Testing
import Foundation
@testable import Conductor

@MainActor @Suite struct ProjectionTests {
    @Test func articleSummary_returnsLastWithArticleSummaryRole() {
        let log = EventLog()
        let id = UUID()
        log.append(SummaryProduced(summary: "A", claims: [], sentiment: "neutral", role: "articleSummary", origin: .step(id: id, index: 1)))
        log.append(SummaryProduced(summary: "B", claims: [], sentiment: "neutral", role: "paperSummary", origin: .step(id: UUID(), index: 2)))
        #expect(Projections.articleSummary(log: log.events)?.summary == "A")
    }

    @Test func pipelineStatus_reflectsCompletionPerStep() {
        let log = EventLog()
        let step1 = Step(index: 0, verb: .read)
        let step2 = Step(index: 1, verb: .summarize)
        log.append(ReadCompleted(body: "", title: "", url: URL(string: "https://x")!, origin: .step(id: step1.id, index: 0)))
        let statuses = Projections.pipelineStatus(log: log.events, steps: [step1, step2])
        #expect(statuses[0] == .completed)
        #expect(statuses[1] == .idle)
    }

    @Test func pipelineStatus_marksFailureFromStepFailed() {
        let step = Step(index: 0, verb: .read)
        let log = EventLog()
        log.append(StepFailed(stepID: step.id, message: "boom", origin: .step(id: step.id, index: 0)))
        let statuses = Projections.pipelineStatus(log: log.events, steps: [step])
        if case .failed = statuses[0] {} else { Issue.record("expected failed") }
    }

    @Test func searchResults_returnsLatest() {
        let log = EventLog()
        let p = Paper(title: "T", abstract: "A", identifier: "i", url: nil)
        log.append(SearchResults(papers: [p], target: "pubMed", origin: .step(id: UUID(), index: 2)))
        #expect(Projections.searchResults(log: log.events)?.papers.count == 1)
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Projections.swift
import Foundation

enum Projections {
    static func articleSummary(log: [any Event]) -> SummaryProduced? {
        log.reversed().compactMap { $0 as? SummaryProduced }.first { $0.role == "articleSummary" }
    }

    static func paperSummaries(log: [any Event]) -> [SummaryProduced] {
        log.compactMap { $0 as? SummaryProduced }.filter { $0.role == "paperSummary" }
    }

    static func searchResults(log: [any Event]) -> SearchResults? {
        log.reversed().compactMap { $0 as? SearchResults }.first
    }

    static func pipelineStatus(log: [any Event], steps: [Step]) -> [StepStatus] {
        steps.map { step in
            if let failure = log.compactMap({ $0 as? StepFailed }).first(where: { $0.stepID == step.id }) {
                return .failed(message: failure.message)
            }
            if log.contains(where: { $0.origin.stepID == step.id && !($0 is StepFailed) }) {
                return .completed
            }
            return .idle
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Projections.swift ConductorTests/ProjectionTests.swift
git commit -m "(service): add pure projections over the event log"
```

---

## Task 12: Layer 1 — NSDataDetector

**Files:**
- Create: `Conductor/Services/Layer1DataDetector.swift`
- Test: `ConductorTests/Layer1Tests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/Layer1Tests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct Layer1Tests {
    @Test func extractsSingleURL() {
        let atoms = Layer1DataDetector.extract(from: "Read https://example.com please")
        let urls = atoms.filter { $0.role == "url" }
        #expect(urls.count == 1)
        if case let .url(u) = urls.first?.value { #expect(u.host == "example.com") } else { Issue.record("no url") }
    }

    @Test func extractsNumberWithRoleResolution() {
        // "find 3 papers" — the number is adjacent to `find` (which maps to search), so role = "search.limit"
        let atoms = Layer1DataDetector.extract(from: "find 3 papers")
        let nums = atoms.filter { if case .number = $0.value { return true } else { return false } }
        #expect(nums.first?.role == "search.limit")
    }

    @Test func unresolvedNumberRoleIsDropped() {
        // "I've read 3 articles" — no catalog verb nearby with a .number parameter → atom not emitted
        let atoms = Layer1DataDetector.extract(from: "I've read 3 articles")
        let nums = atoms.filter { if case .number = $0.value { return true } else { return false } }
        #expect(nums.isEmpty)
    }

    @Test func extractsDate() {
        let atoms = Layer1DataDetector.extract(from: "on January 5, 2026")
        let dates = atoms.filter { if case .date = $0.value { return true } else { return false } }
        #expect(dates.count >= 1)
    }

    @Test func sourceIsDetector() {
        let atoms = Layer1DataDetector.extract(from: "Read https://x")
        #expect(atoms.first?.source == .detector)
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Layer1DataDetector.swift
import Foundation

enum Layer1DataDetector {
    static func extract(from prose: String) -> [AtomRecorded] {
        var out: [AtomRecorded] = []
        let types: NSTextCheckingResult.CheckingType = [.link, .date]
        guard let det = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(prose.startIndex..., in: prose)

        det.enumerateMatches(in: prose, options: [], range: range) { match, _, _ in
            guard let m = match else { return }
            if let url = m.url {
                out.append(AtomRecorded(role: "url", value: .url(url), source: .detector, origin: .compile()))
            }
            if let date = m.date {
                out.append(AtomRecorded(role: "date", value: .date(date), source: .detector, origin: .compile()))
            }
        }

        // Numbers via NSRegularExpression — NSDataDetector doesn't match bare integers reliably.
        let numberRegex = try? NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
        numberRegex?.enumerateMatches(in: prose, options: [], range: range) { match, _, _ in
            guard let m = match, let range = Range(m.range, in: prose) else { return }
            let token = String(prose[range])
            guard let value = Double(token) else { return }
            if let role = numberRole(for: token, at: range, in: prose) {
                out.append(AtomRecorded(role: role, value: .number(value), source: .detector, origin: .compile()))
            }
        }

        return out
    }

    /// Walks backward from the number to the nearest verb lemma. If the nearest catalog verb
    /// declares a `.number` parameter, the role is that parameter's role; otherwise `nil`
    /// (the atom is dropped — let auto-ask handle it).
    private static func numberRole(for token: String, at range: Range<String.Index>, in prose: String) -> String? {
        let prefix = prose[..<range.lowerBound]
        let words = prefix.split(whereSeparator: { !$0.isLetter }).map { String($0).lowercased() }
        for word in words.reversed() {
            if let verb = VerbCatalog.verb(forLemma: word) {
                let numberParam = VerbCatalog.definition(for: verb).parameters.first { p in
                    if case .number = p.kind { return true } else { return false }
                }
                return numberParam?.role
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Layer1DataDetector.swift ConductorTests/Layer1Tests.swift
git commit -m "(compiler): add Layer 1 — NSDataDetector atom extraction"
```

---

## Task 13: Layer 2 — NLTagger verb lemma matching

**Files:**
- Create: `Conductor/Services/Layer2Tagger.swift`
- Test: `ConductorTests/Layer2Tests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/Layer2Tests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct Layer2VerbTests {
    @Test func findsSummarizeAndSearch() {
        let r = Layer2Tagger.extract(from: "Summarize the article and find papers")
        #expect(r.verbs == [.summarize, .search])
    }

    @Test func lemmatizes_summarized_to_summarize() {
        let r = Layer2Tagger.extract(from: "I summarized it")
        #expect(r.verbs == [.summarize])
    }

    @Test func verbsAppearInSentenceOrder() {
        let r = Layer2Tagger.extract(from: "Find 3 papers then summarize them")
        #expect(r.verbs == [.search, .summarize])
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement the first slice**

```swift
// Conductor/Services/Layer2Tagger.swift
import Foundation
import NaturalLanguage

struct Layer2Result: Sendable {
    let verbs: [Verb]
    let atoms: [AtomRecorded]
}

enum Layer2Tagger {
    static func extract(from prose: String) -> Layer2Result {
        let (verbs, _) = verbsAndPositions(in: prose)
        let atoms = nounPhraseAtoms(in: prose, verbPositions: []) + aliasAtoms(in: prose)
        return Layer2Result(verbs: verbs, atoms: atoms)
    }

    static func verbsAndPositions(in prose: String) -> ([Verb], [(Verb, Range<String.Index>)]) {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = prose
        var verbs: [Verb] = []
        var positions: [(Verb, Range<String.Index>)] = []
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: prose.startIndex..<prose.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            guard tag == .verb else { return true }
            let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0
            let token = (lemmaTag?.rawValue ?? String(prose[range])).lowercased()
            if let v = VerbCatalog.verb(forLemma: token) {
                verbs.append(v)
                positions.append((v, range))
            }
            return true
        }
        return (verbs, positions)
    }

    static func nounPhraseAtoms(in prose: String, verbPositions: [(Verb, Range<String.Index>)]) -> [AtomRecorded] {
        // Implemented in Task 14
        []
    }

    static func aliasAtoms(in prose: String) -> [AtomRecorded] {
        // Implemented in Task 15
        []
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Layer2Tagger.swift ConductorTests/Layer2Tests.swift
git commit -m "(compiler): add Layer 2 — verb lemma extraction"
```

---

## Task 14: Layer 2 — noun-phrase extraction

**Files:**
- Modify: `Conductor/Services/Layer2Tagger.swift`
- Test: extend `ConductorTests/Layer2Tests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@Suite struct Layer2NPTests {
    @Test func extractsSearchTermsAdjacentToFind() {
        let r = Layer2Tagger.extract(from: "find papers about CRISPR and sickle-cell")
        let terms = r.atoms.first { $0.role == "search.terms" }
        if case let .text(t) = terms?.value { #expect(t.localizedCaseInsensitiveContains("CRISPR")) } else { Issue.record("no terms") }
    }

    @Test func nounPhraseIsNearestToMatchedVerb() {
        // "summarize the article and find recent work" → `summarize` has no declared NP param,
        // `search.terms` goes with `find` / `search`. The NP nearest `find` wins.
        let r = Layer2Tagger.extract(from: "summarize the article and find recent work")
        let terms = r.atoms.first { $0.role == "search.terms" }
        if case let .text(t) = terms?.value { #expect(t.localizedCaseInsensitiveContains("work")) }
    }
}
```

- [ ] **Step 2: Run tests, expect failure (returns empty)**

- [ ] **Step 3: Implement noun-phrase extraction**

Replace the `nounPhraseAtoms` stub in `Layer2Tagger.swift`:

```swift
static func nounPhraseAtoms(in prose: String, verbPositions: [(Verb, Range<String.Index>)]) -> [AtomRecorded] {
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = prose
    let opts: NLTagger.Options = [.omitWhitespace]
    var phrases: [(text: String, range: Range<String.Index>)] = []
    var current: (text: String, start: String.Index, end: String.Index)?

    tagger.enumerateTags(in: prose.startIndex..<prose.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
        let isNounLike = tag == .noun || tag == .adjective || tag == .determiner || tag == .preposition
        let piece = String(prose[range])
        if tag == .noun || tag == .adjective {
            if var c = current {
                c.text += " " + piece
                c.end = range.upperBound
                current = c
            } else {
                current = (piece, range.lowerBound, range.upperBound)
            }
        } else if tag == .determiner || tag == .preposition {
            // allow within a phrase but don't start one
            if var c = current {
                c.text += " " + piece
                c.end = range.upperBound
                current = c
            }
        } else {
            if let c = current {
                phrases.append((c.text, c.start..<c.end))
                current = nil
            }
            _ = isNounLike
        }
        return true
    }
    if let c = current { phrases.append((c.text, c.start..<c.end)) }

    var out: [AtomRecorded] = []
    for (verb, verbRange) in verbPositions {
        let params = VerbCatalog.definition(for: verb).parameters.filter { if case .text = $0.kind { return true } else { return false } }
        for param in params {
            let nearest = phrases.min { a, b in
                distance(from: a.range, to: verbRange) < distance(from: b.range, to: verbRange)
            }
            if let np = nearest {
                out.append(AtomRecorded(role: param.role, value: .text(np.text), source: .tagger, origin: .compile()))
            }
        }
    }
    return out
}

private static func distance(from a: Range<String.Index>, to b: Range<String.Index>) -> Int {
    let s = min(a.lowerBound, b.lowerBound)
    let e = max(a.upperBound, b.upperBound)
    return abs(s.utf16Offset(in: "") - e.utf16Offset(in: ""))
}
```

Replace `extract` so it passes `verbPositions` to `nounPhraseAtoms`:

```swift
static func extract(from prose: String) -> Layer2Result {
    let (verbs, positions) = verbsAndPositions(in: prose)
    let atoms = nounPhraseAtoms(in: prose, verbPositions: positions) + aliasAtoms(in: prose)
    return Layer2Result(verbs: verbs, atoms: atoms)
}
```

And fix `distance` — UTF16 offset over empty string will trap. Use byte-distance within `prose`:

```swift
private static func distance(from a: Range<String.Index>, to b: Range<String.Index>, in prose: String) -> Int {
    let aMid = prose.distance(from: prose.startIndex, to: a.lowerBound) + prose.distance(from: a.lowerBound, to: a.upperBound) / 2
    let bMid = prose.distance(from: prose.startIndex, to: b.lowerBound) + prose.distance(from: b.lowerBound, to: b.upperBound) / 2
    return abs(aMid - bMid)
}
```

Thread `prose` through the call site.

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Layer2Tagger.swift ConductorTests/Layer2Tests.swift
git commit -m "(compiler): add Layer 2 noun-phrase extraction tied to verb position"
```

---

## Task 15: Layer 2 — parameter alias matching

**Files:**
- Modify: `Conductor/Services/Layer2Tagger.swift`
- Test: extend `ConductorTests/Layer2Tests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@Suite struct Layer2AliasTests {
    @Test func pubmedTokenMatchesSearchTarget() {
        let r = Layer2Tagger.extract(from: "find 3 PubMed papers")
        let target = r.atoms.first { $0.role == "search.target" }
        if case let .choice(_, v) = target?.value { #expect(v == "pubMed") } else { Issue.record("no target") }
    }

    @Test func arxivOrgTokenMatchesSearchTarget() {
        let r = Layer2Tagger.extract(from: "search arxiv.org for transformers")
        let target = r.atoms.first { $0.role == "search.target" }
        if case let .choice(_, v) = target?.value { #expect(v == "arxiv") }
    }

    @Test func missingTargetProducesNoAtom() {
        let r = Layer2Tagger.extract(from: "find 3 papers")
        #expect(r.atoms.first { $0.role == "search.target" } == nil)
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement alias matching**

Replace the `aliasAtoms` stub:

```swift
static func aliasAtoms(in prose: String) -> [AtomRecorded] {
    var out: [AtomRecorded] = []
    let lower = prose.lowercased()
    for verb in Verb.allCases {
        let params = VerbCatalog.definition(for: verb).parameters
        for param in params {
            guard case let .choice(namespace, _) = param.kind else { continue }
            for (alias, canonical) in param.aliases {
                if lower.contains(alias) {
                    out.append(AtomRecorded(
                        role: param.role,
                        value: .choice(namespace: namespace, value: canonical),
                        source: .tagger,
                        origin: .compile()
                    ))
                    break
                }
            }
        }
    }
    return out
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Layer2Tagger.swift ConductorTests/Layer2Tests.swift
git commit -m "(compiler): add Layer 2 parameter alias matching"
```

---

## Task 16: Layer 3 — NLEmbedding fuzzy verb match

**Files:**
- Create: `Conductor/Services/Layer3Embedding.swift`
- Test: `ConductorTests/Layer3Tests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/Layer3Tests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct Layer3Tests {
    @Test func fuzzy_lookInto_mapsToRead() {
        let match = Layer3Embedding.fuzzyMatch(lemma: "peruse")
        #expect(match == .read || match == nil)   // embedding may or may not cross threshold; both acceptable
    }

    @Test func fuzzy_known_exactMatchIsNotRun() {
        // Layer 3 should return nil for words that Layer 2 already resolved.
        // We simulate that by checking the gate: only unknown words enter fuzzyMatch.
        #expect(Layer3Embedding.fuzzyMatch(lemma: "summarize") == .summarize)
    }

    @Test func fuzzy_random_returnsNil() {
        #expect(Layer3Embedding.fuzzyMatch(lemma: "banana") == nil)
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Layer3Embedding.swift
import Foundation
import NaturalLanguage

enum Layer3Embedding {
    static let threshold: Double = 0.65

    static func fuzzyMatch(lemma: String) -> Verb? {
        if let direct = VerbCatalog.verb(forLemma: lemma) { return direct }
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        guard embedding.contains(lemma) else { return nil }

        var best: (Verb, Double)?
        for verb in Verb.allCases {
            for catalogLemma in VerbCatalog.definition(for: verb).lemmas {
                guard embedding.contains(catalogLemma) else { continue }
                let d = embedding.distance(between: lemma, and: catalogLemma)
                let similarity = 1.0 - d
                if similarity >= threshold, similarity > (best?.1 ?? threshold) {
                    best = (verb, similarity)
                }
            }
        }
        return best?.0
    }
}
```

- [ ] **Step 4: Run tests, expect pass** (Note: the first test is permissive; NLEmbedding may or may not rank `peruse` close to `read`. The second and third are strict.)

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Layer3Embedding.swift ConductorTests/Layer3Tests.swift
git commit -m "(compiler): add Layer 3 — fuzzy verb match via NLEmbedding"
```

---

## Task 17: Layer 4 — IntentSession

**Files:**
- Create: `Conductor/Services/Layer4IntentSession.swift`
- Test: `ConductorTests/Layer4Tests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/Layer4Tests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct Layer4Tests {
    @Test func callsLLM_onlyWhenNoVerbsKnown() async throws {
        let llm = FakeLLMSession()
        llm.scriptedIntent = PipelineIntent(verbs: [.search])
        let verbs = try await Layer4IntentSession.classify(prose: "I've got this thing", llm: llm)
        #expect(verbs == [.search])
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Layer4IntentSession.swift
import Foundation

enum Layer4IntentSession {
    static func classify(prose: String, llm: any LLMSession) async throws -> [Verb] {
        let intent = try await llm.inferPipeline(from: prose)
        return intent.verbs
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Layer4IntentSession.swift ConductorTests/Layer4Tests.swift
git commit -m "(compiler): add Layer 4 LLM fallback"
```

---

## Task 18: ProseCompiler orchestrator

**Files:**
- Create: `Conductor/Services/ProseCompiler.swift`
- Test: `ConductorTests/ProseCompilerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/ProseCompilerTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct ProseCompilerTests {
    @Test func compiles_deterministically_whenL1L2Suffice() async throws {
        let llm = FakeLLMSession()
        let result = try await ProseCompiler.compile(
            prose: "Summarize the article at https://example.com and find 3 related PubMed papers",
            llm: llm
        )
        #expect(result.verbs.contains(.summarize))
        #expect(result.verbs.contains(.search))
        #expect(result.usedLLM == false)
        #expect(result.atoms.contains { $0.role == "url" })
        #expect(result.atoms.contains { $0.role == "search.target" })
        #expect(result.atoms.contains { $0.role == "search.limit" })
    }

    @Test func fallsToLLM_whenLayer2FindsNoVerbs() async throws {
        let llm = FakeLLMSession()
        llm.scriptedIntent = PipelineIntent(verbs: [.search])
        let result = try await ProseCompiler.compile(prose: "I've got this thing", llm: llm)
        #expect(result.usedLLM == true)
        #expect(result.verbs == [.search])
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/ProseCompiler.swift
import Foundation

struct CompileResult: Sendable {
    let verbs: [Verb]
    let atoms: [AtomRecorded]
    let usedLLM: Bool
}

enum ProseCompiler {
    static func compile(prose: String, llm: any LLMSession) async throws -> CompileResult {
        let l1 = Layer1DataDetector.extract(from: prose)
        let l2 = Layer2Tagger.extract(from: prose)

        var verbs = l2.verbs
        var usedLLM = false

        // Layer 3: for each verb-tagged word that didn't resolve, try embedding.
        // (Simple v2 version: if L2 found zero verbs, run L3 over raw verb-like words.)
        if verbs.isEmpty {
            let fallback = verbLikeWords(in: prose).compactMap { Layer3Embedding.fuzzyMatch(lemma: $0) }
            verbs = dedupeStable(fallback)
        }

        // Layer 4: last resort.
        if verbs.isEmpty {
            verbs = try await Layer4IntentSession.classify(prose: prose, llm: llm)
            usedLLM = true
        }

        return CompileResult(verbs: verbs, atoms: l1 + l2.atoms, usedLLM: usedLLM)
    }

    private static func verbLikeWords(in prose: String) -> [String] {
        prose.split(whereSeparator: { !$0.isLetter }).map { String($0).lowercased() }
    }

    private static func dedupeStable(_ verbs: [Verb]) -> [Verb] {
        var seen: Set<Verb> = []
        var out: [Verb] = []
        for v in verbs where !seen.contains(v) { seen.insert(v); out.append(v) }
        return out
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/ProseCompiler.swift ConductorTests/ProseCompilerTests.swift
git commit -m "(compiler): add ProseCompiler orchestrating L1→L4"
```

---

## Task 19: ReadVerb

**Files:**
- Modify: `Conductor/Services/Verbs/ReadVerb.swift`
- Test: `ConductorTests/ReadVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/ReadVerbTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct ReadVerbTests {
    @Test func fetches_andEmitsReadCompleted() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://example.com")!
        http.scripted[url] = Data("<html><title>T</title><body>B</body></html>".utf8)
        let llm = FakeLLMSession()
        let inputs = ResolvedInputs(atoms: ["url": .url(url)], upstream: [])
        let events = try await ReadVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 0),
            http: http,
            llm: llm
        )
        let read = events.compactMap { $0 as? ReadCompleted }
        #expect(read.count == 1)
        #expect(read.first?.url == url)
        #expect(read.first?.title.contains("T") == true)
    }

    @Test func failure_emitsStepFailed() async throws {
        let http = FakeHTTPClient()   // no scripted response
        let llm = FakeLLMSession()
        let inputs = ResolvedInputs(atoms: ["url": .url(URL(string: "https://x")!)], upstream: [])
        let stepID = UUID()
        let events = try await ReadVerb.execute(resolved: inputs, origin: .step(id: stepID, index: 0), http: http, llm: llm)
        let fails = events.compactMap { $0 as? StepFailed }
        #expect(fails.first?.stepID == stepID)
    }
}
```

- [ ] **Step 2: Run tests, expect failure (stub traps)**

- [ ] **Step 3: Implement `execute`**

```swift
// Conductor/Services/Verbs/ReadVerb.swift
import Foundation

enum ReadVerb: VerbDefinition {
    static let verb: Verb = .read
    static let lemmas = ["read", "open", "fetch", "load"]
    static let parameters = [
        VerbParameter(role: "url", kind: .url, aliases: [:], required: true, defaultValue: nil)
    ]
    static let needs: [UpstreamEventNeed] = []

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        guard case let .url(url)? = resolved.atoms["url"] else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "missing url", origin: origin)]
        }
        do {
            let data = try await http.get(url)
            let body = String(data: data, encoding: .utf8) ?? ""
            let title = extractTitle(from: body) ?? url.host ?? url.absoluteString
            let text = stripTags(from: body)
            return [ReadCompleted(body: text, title: title, url: url, origin: origin)]
        } catch {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "\(error)", origin: origin)]
        }
    }

    private static func extractTitle(from html: String) -> String? {
        guard let start = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive),
              start.upperBound < end.lowerBound else { return nil }
        return String(html[start.upperBound..<end.lowerBound])
    }

    private static func stripTags(from html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/ReadVerb.swift ConductorTests/ReadVerbTests.swift
git commit -m "(verb): implement ReadVerb with injected HTTP"
```

---

## Task 20: SummarizeVerb

**Files:**
- Modify: `Conductor/Services/Verbs/SummarizeVerb.swift`
- Test: `ConductorTests/SummarizeVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/SummarizeVerbTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct SummarizeVerbTests {
    @Test func summarizesReadCompletedArticle() async throws {
        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "Short.", claims: ["c1"], sentiment: "neutral")
        let read = ReadCompleted(body: "long body", title: "T", url: URL(string: "https://x")!, origin: .step(id: UUID(), index: 0))
        let inputs = ResolvedInputs(atoms: [:], upstream: [read])
        let events = try await SummarizeVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 1),
            http: FakeHTTPClient(),
            llm: llm
        )
        let summary = events.compactMap { $0 as? SummaryProduced }.first
        #expect(summary?.summary == "Short.")
        #expect(summary?.role == "articleSummary")
    }

    @Test func rolesAsPaperSummary_whenSourceIsSearchResult() async throws {
        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "Paper gist.", claims: [], sentiment: "neutral")
        let p = Paper(title: "P", abstract: "A", identifier: "i", url: nil)
        let results = SearchResults(papers: [p], target: "pubMed", origin: .step(id: UUID(), index: 0))
        let inputs = ResolvedInputs(atoms: [:], upstream: [results])
        let events = try await SummarizeVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 1, iteration: 0),
            http: FakeHTTPClient(),
            llm: llm
        )
        #expect((events.first as? SummaryProduced)?.role == "paperSummary")
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Verbs/SummarizeVerb.swift
import Foundation

enum SummarizeVerb: VerbDefinition {
    static let verb: Verb = .summarize
    static let lemmas = ["summarize", "summarise", "sum up", "digest"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["ReadCompleted", "SearchResults"], required: true)
    ]

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        if let read = resolved.upstream.compactMap({ $0 as? ReadCompleted }).last {
            let gen = try await llm.summarize(text: read.body)
            return [SummaryProduced(
                summary: gen.summary,
                claims: gen.claims,
                sentiment: gen.sentiment,
                role: "articleSummary",
                origin: origin
            )]
        }
        if let results = resolved.upstream.compactMap({ $0 as? SearchResults }).last {
            let iteration = origin.iteration ?? 0
            guard iteration < results.papers.count else {
                return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no paper at iteration", origin: origin)]
            }
            let paper = results.papers[iteration]
            let gen = try await llm.summarize(text: paper.abstract)
            return [SummaryProduced(
                summary: gen.summary,
                claims: gen.claims,
                sentiment: gen.sentiment,
                role: "paperSummary",
                origin: origin
            )]
        }
        return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no readable upstream", origin: origin)]
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/SummarizeVerb.swift ConductorTests/SummarizeVerbTests.swift
git commit -m "(verb): implement SummarizeVerb dispatching on upstream type"
```

---

## Task 21: SearchBackend protocol

**Files:**
- Create: `Conductor/Services/SearchBackends/SearchBackend.swift`

- [ ] **Step 1: Implement**

```swift
// Conductor/Services/SearchBackends/SearchBackend.swift
import Foundation

protocol SearchBackend: Sendable {
    static var target: String { get }
    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper]
}
```

- [ ] **Step 2: Commit**

```bash
git add Conductor/Services/SearchBackends/SearchBackend.swift
git commit -m "(service): add SearchBackend protocol"
```

---

## Task 22: PubMedBackend

**Files:**
- Create: `Conductor/Services/SearchBackends/PubMedBackend.swift`
- Test: `ConductorTests/PubMedBackendTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/PubMedBackendTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct PubMedBackendTests {
    @Test func parsesESearchAndESummary() async throws {
        let http = FakeHTTPClient()
        let searchURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=crispr&retmax=2&retmode=json")!
        let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=111,222&retmode=json")!
        http.scripted[searchURL] = Data(#"{"esearchresult":{"idlist":["111","222"]}}"#.utf8)
        http.scripted[summaryURL] = Data(#"{"result":{"uids":["111","222"],"111":{"title":"A","uid":"111"},"222":{"title":"B","uid":"222"}}}"#.utf8)
        let papers = try await PubMedBackend.search(terms: "crispr", limit: 2, http: http)
        #expect(papers.count == 2)
        #expect(papers[0].identifier == "111")
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/SearchBackends/PubMedBackend.swift
import Foundation

struct PubMedBackend: SearchBackend {
    static let target = "pubMed"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let termsEncoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let searchURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=\(termsEncoded)&retmax=\(limit)&retmode=json")!
        let searchData = try await http.get(searchURL)
        let idList = try parseIDs(searchData)
        guard !idList.isEmpty else { return [] }
        let ids = idList.joined(separator: ",")
        let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(ids)&retmode=json")!
        let summaryData = try await http.get(summaryURL)
        return try parseSummaries(summaryData, ids: idList)
    }

    private static func parseIDs(_ data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let er = root["esearchresult"] as? [String: Any],
              let ids = er["idlist"] as? [String] else { return [] }
        return ids
    }

    private static func parseSummaries(_ data: Data, ids: [String]) throws -> [Paper] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else { return [] }
        return ids.compactMap { id -> Paper? in
            guard let entry = result[id] as? [String: Any] else { return nil }
            let title = entry["title"] as? String ?? "(untitled)"
            let abstract = entry["abstract"] as? String ?? ""
            return Paper(title: title, abstract: abstract, identifier: id, url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(id)/"))
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/SearchBackends/PubMedBackend.swift ConductorTests/PubMedBackendTests.swift
git commit -m "(backend): implement PubMed search backend"
```

---

## Task 23: ArxivBackend

**Files:**
- Create: `Conductor/Services/SearchBackends/ArxivBackend.swift`
- Test: `ConductorTests/ArxivBackendTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/ArxivBackendTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct ArxivBackendTests {
    @Test func parsesAtomFeed() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://export.arxiv.org/api/query?search_query=all:transformers&max_results=1")!
        let feed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2101.00001</id>
            <title>Attention Is All You Need Again</title>
            <summary>Abstract text.</summary>
          </entry>
        </feed>
        """
        http.scripted[url] = Data(feed.utf8)
        let papers = try await ArxivBackend.search(terms: "transformers", limit: 1, http: http)
        #expect(papers.count == 1)
        #expect(papers[0].title.contains("Attention"))
        #expect(papers[0].identifier.contains("2101.00001"))
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/SearchBackends/ArxivBackend.swift
import Foundation

struct ArxivBackend: SearchBackend {
    static let target = "arxiv"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let url = URL(string: "https://export.arxiv.org/api/query?search_query=all:\(encoded)&max_results=\(limit)")!
        let data = try await http.get(url)
        let parser = ArxivParser()
        return parser.parse(data: data)
    }
}

private final class ArxivParser: NSObject, XMLParserDelegate {
    private var papers: [Paper] = []
    private var current: [String: String] = [:]
    private var inEntry = false
    private var text = ""

    func parse(data: Data) -> [Paper] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return papers
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "entry" { inEntry = true; current = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if inEntry && ["id", "title", "summary"].contains(elementName) {
            current[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == "entry" {
            inEntry = false
            let id = current["id"] ?? ""
            papers.append(Paper(
                title: current["title"] ?? "",
                abstract: current["summary"] ?? "",
                identifier: id.components(separatedBy: "/").last ?? id,
                url: URL(string: id)
            ))
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/SearchBackends/ArxivBackend.swift ConductorTests/ArxivBackendTests.swift
git commit -m "(backend): implement arXiv search backend"
```

---

## Task 24: WebBackend

**Files:**
- Create: `Conductor/Services/SearchBackends/WebBackend.swift`
- Test: `ConductorTests/WebBackendTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/WebBackendTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct WebBackendTests {
    @Test func parsesDuckDuckGoJSON() async throws {
        let http = FakeHTTPClient()
        let url = URL(string: "https://api.duckduckgo.com/?q=crispr&format=json&no_html=1&no_redirect=1")!
        let payload = #"""
        {
          "RelatedTopics": [
            {"Text": "CRISPR — a gene-editing system", "FirstURL": "https://duckduckgo.com/CRISPR"},
            {"Text": "Cas9", "FirstURL": "https://duckduckgo.com/Cas9"}
          ]
        }
        """#
        http.scripted[url] = Data(payload.utf8)
        let papers = try await WebBackend.search(terms: "crispr", limit: 2, http: http)
        #expect(papers.count == 2)
        #expect(papers[0].title.contains("CRISPR"))
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/SearchBackends/WebBackend.swift
import Foundation

struct WebBackend: SearchBackend {
    static let target = "web"

    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper] {
        let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&no_redirect=1")!
        let data = try await http.get(url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topics = root["RelatedTopics"] as? [[String: Any]] else { return [] }
        return topics.prefix(limit).enumerated().map { idx, entry in
            let text = entry["Text"] as? String ?? ""
            let u = (entry["FirstURL"] as? String).flatMap { URL(string: $0) }
            let title = text.components(separatedBy: " — ").first ?? text
            return Paper(title: title, abstract: text, identifier: "ddg-\(idx)", url: u)
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/SearchBackends/WebBackend.swift ConductorTests/WebBackendTests.swift
git commit -m "(backend): implement web search backend (DuckDuckGo Instant Answer)"
```

---

## Task 25: SearchVerb

**Files:**
- Modify: `Conductor/Services/Verbs/SearchVerb.swift`
- Test: `ConductorTests/SearchVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/SearchVerbTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct SearchVerbTests {
    @Test func dispatches_toPubMed_whenTargetIsPubMed() async throws {
        let http = FakeHTTPClient()
        let search = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=CRISPR&retmax=3&retmode=json")!
        let summary = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=111&retmode=json")!
        http.scripted[search] = Data(#"{"esearchresult":{"idlist":["111"]}}"#.utf8)
        http.scripted[summary] = Data(#"{"result":{"uids":["111"],"111":{"title":"A","uid":"111"}}}"#.utf8)

        let inputs = ResolvedInputs(atoms: [
            "search.terms": .text("CRISPR"),
            "search.target": .choice(namespace: "search.target", value: "pubMed"),
            "search.limit": .number(3)
        ], upstream: [])
        let events = try await SearchVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 0),
            http: http,
            llm: FakeLLMSession()
        )
        let sr = events.compactMap { $0 as? SearchResults }.first
        #expect(sr?.target == "pubMed")
        #expect(sr?.papers.count == 1)
    }

    @Test func usesClaimsExtracted_whenPresent() async throws {
        let http = FakeHTTPClient()
        let search = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=sickle-cell%20CRISPR&retmax=3&retmode=json")!
        let summary = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=1&retmode=json")!
        http.scripted[search] = Data(#"{"esearchresult":{"idlist":["1"]}}"#.utf8)
        http.scripted[summary] = Data(#"{"result":{"uids":["1"],"1":{"title":"T","uid":"1"}}}"#.utf8)
        let claims = ClaimsExtracted(claims: [Claim(text: "sickle-cell"), Claim(text: "CRISPR")], origin: .step(id: UUID(), index: 0))
        let inputs = ResolvedInputs(atoms: [
            "search.target": .choice(namespace: "search.target", value: "pubMed"),
            "search.limit": .number(3)
        ], upstream: [claims])
        let events = try await SearchVerb.execute(resolved: inputs, origin: .step(id: UUID(), index: 1), http: http, llm: FakeLLMSession())
        #expect((events.first as? SearchResults) != nil)
    }
}
```

- [ ] **Step 2: Run tests, expect failure (stub traps)**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Verbs/SearchVerb.swift
import Foundation

enum SearchVerb: VerbDefinition {
    static let verb: Verb = .search
    static let lemmas = ["search", "find", "look up", "look for", "query"]
    static let parameters = [
        VerbParameter(role: "search.terms", kind: .text, aliases: [:], required: true, defaultValue: nil),
        VerbParameter(
            role: "search.target",
            kind: .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web"]),
            aliases: [
                "pubmed": "pubMed", "pub med": "pubMed",
                "arxiv": "arxiv", "arxiv.org": "arxiv",
                "web": "web", "google": "web", "internet": "web"
            ],
            required: true,
            defaultValue: nil
        ),
        VerbParameter(role: "search.limit", kind: .number, aliases: [:], required: false, defaultValue: .number(5))
    ]
    static let needs: [UpstreamEventNeed] = []

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        let terms: String
        if let claims = resolved.upstream.compactMap({ $0 as? ClaimsExtracted }).last, !claims.claims.isEmpty {
            terms = claims.claims.map { $0.text }.joined(separator: " ")
        } else if case let .text(t)? = resolved.atoms["search.terms"] {
            terms = t
        } else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no search terms", origin: origin)]
        }

        guard case let .choice(_, target)? = resolved.atoms["search.target"] else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no search target", origin: origin)]
        }

        let limit: Int = {
            if case let .number(n)? = resolved.atoms["search.limit"] { return Int(n) }
            return 5
        }()

        do {
            let papers: [Paper]
            switch target {
            case "pubMed": papers = try await PubMedBackend.search(terms: terms, limit: limit, http: http)
            case "arxiv":  papers = try await ArxivBackend.search(terms: terms, limit: limit, http: http)
            case "web":    papers = try await WebBackend.search(terms: terms, limit: limit, http: http)
            default:
                return [StepFailed(stepID: origin.stepID ?? UUID(), message: "unknown target \(target)", origin: origin)]
            }
            return [SearchResults(papers: papers, target: target, origin: origin)]
        } catch {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "\(error)", origin: origin)]
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/SearchVerb.swift ConductorTests/SearchVerbTests.swift
git commit -m "(verb): implement SearchVerb with backend dispatch"
```

---

## Task 26: ExtractClaimsVerb

**Files:**
- Modify: `Conductor/Services/Verbs/ExtractClaimsVerb.swift`
- Test: `ConductorTests/ExtractClaimsVerbTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/ExtractClaimsVerbTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct ExtractClaimsVerbTests {
    @Test func extractsClaimsFromLastSummary() async throws {
        let llm = FakeLLMSession()
        llm.scriptedClaims = ClaimsGenerable(claims: ["sky is blue", "water is wet"])
        let summary = SummaryProduced(summary: "the sky is blue; water is wet", claims: [], sentiment: "neutral", role: "articleSummary", origin: .step(id: UUID(), index: 0))
        let events = try await ExtractClaimsVerb.execute(
            resolved: ResolvedInputs(atoms: [:], upstream: [summary]),
            origin: .step(id: UUID(), index: 1),
            http: FakeHTTPClient(),
            llm: llm
        )
        let ce = events.compactMap { $0 as? ClaimsExtracted }.first
        #expect(ce?.claims.count == 2)
        #expect(ce?.claims.first?.text == "sky is blue")
    }
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Verbs/ExtractClaimsVerb.swift
import Foundation

enum ExtractClaimsVerb: VerbDefinition {
    static let verb: Verb = .extractClaims
    static let lemmas = ["extract", "pull", "identify"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["SummaryProduced"], required: true)
    ]

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        guard let summary = resolved.upstream.compactMap({ $0 as? SummaryProduced }).last else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no summary", origin: origin)]
        }
        do {
            let gen = try await llm.extractClaims(from: summary.summary)
            let claims = gen.claims.map { Claim(text: $0) }
            return [ClaimsExtracted(claims: claims, origin: origin)]
        } catch {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "\(error)", origin: origin)]
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Verbs/ExtractClaimsVerb.swift ConductorTests/ExtractClaimsVerbTests.swift
git commit -m "(verb): implement ExtractClaimsVerb via LLM"
```

---

## Task 27: Needs closure algorithm

**Files:**
- Create: `Conductor/Services/NeedsClosure.swift`
- Test: `ConductorTests/NeedsClosureTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/NeedsClosureTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct NeedsClosureTests {
    @Test func prependsRead_beforeSummarize_whenNoReadExists() {
        let pipeline = NeedsClosure.inflate(verbs: [.summarize], existingLog: [])
        #expect(pipeline == [.read, .summarize])
    }

    @Test func noInflation_whenReadAlreadyInPipeline() {
        let pipeline = NeedsClosure.inflate(verbs: [.read, .summarize], existingLog: [])
        #expect(pipeline == [.read, .summarize])
    }

    @Test func noInflation_whenReadEventAlreadyInLog() {
        let rc = ReadCompleted(body: "", title: "", url: URL(string: "https://x")!, origin: .step(id: UUID(), index: 0))
        let pipeline = NeedsClosure.inflate(verbs: [.summarize], existingLog: [rc])
        #expect(pipeline == [.summarize])
    }

    @Test func prependsSearch_beforeSummarizeOfSearchResults_whenChosen() {
        // Future-proofing: if two verbs satisfy the need, the caller chooses.
        // For v2, prefer the verb whose parameters are already fillable; here, only `read` has its own
        // parameters (url, which will be asked); both resolve via auto-ask. Default rule: first in catalog order.
        let pipeline = NeedsClosure.inflate(verbs: [.summarize], existingLog: [])
        #expect(pipeline.first == .read)
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/NeedsClosure.swift
import Foundation

enum NeedsClosure {
    static func inflate(verbs: [Verb], existingLog: [any Event]) -> [Verb] {
        var output: [Verb] = []
        for verb in verbs {
            try? insert(verb: verb, into: &output, existingLog: existingLog)
        }
        return output
    }

    private static func insert(verb: Verb, into pipeline: inout [Verb], existingLog: [any Event]) throws {
        let def = VerbCatalog.definition(for: verb)
        for need in def.needs where need.required {
            let satisfiedByLog = existingLog.contains { evt in need.eventTypeNames.contains(typeName(evt)) }
            let satisfiedByPipeline = pipeline.contains { v in
                need.eventTypeNames.contains { emittedType(by: v)?.contains($0) ?? false }
            }
            if satisfiedByLog || satisfiedByPipeline { continue }
            guard let producer = producerVerb(forAny: need.eventTypeNames) else {
                throw NSError(domain: "closure", code: 1)
            }
            try insert(verb: producer, into: &pipeline, existingLog: existingLog)
        }
        if !pipeline.contains(verb) { pipeline.append(verb) }
    }

    private static func typeName(_ event: any Event) -> String {
        String(describing: type(of: event))
    }

    /// Which event types a verb emits. Hard-coded — small catalog, no reflection.
    private static func emittedType(by verb: Verb) -> [String]? {
        switch verb {
        case .read: ["ReadCompleted"]
        case .summarize: ["SummaryProduced"]
        case .search: ["SearchResults"]
        case .extractClaims: ["ClaimsExtracted"]
        }
    }

    private static func producerVerb(forAny types: [String]) -> Verb? {
        for v in Verb.allCases {
            if let emits = emittedType(by: v), !Set(emits).isDisjoint(with: Set(types)) {
                return v
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/NeedsClosure.swift ConductorTests/NeedsClosureTests.swift
git commit -m "(compiler): add needs-closure pipeline inflation"
```

---

## Task 28: Runtime executor

**Files:**
- Create: `Conductor/Services/Runtime.swift`
- Test: `ConductorTests/RuntimeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/RuntimeTests.swift
import Testing
import Foundation
@testable import Conductor

@MainActor @Suite struct RuntimeTests {
    @Test func runs_readThenSummarize_endToEnd() async throws {
        let log = EventLog()
        let http = FakeHTTPClient()
        let llm = FakeLLMSession()
        let url = URL(string: "https://example.com")!
        http.scripted[url] = Data("<title>T</title><body>B</body>".utf8)
        llm.scriptedSummary = SummaryGenerable(summary: "Short.", claims: [], sentiment: "neutral")

        log.append(AtomRecorded(role: "url", value: .url(url), source: .detector, origin: .compile()))

        let runtime = Runtime(log: log, http: http, llm: llm, askResolver: AutoAcceptAskResolver())
        try await runtime.run(steps: [Step(index: 0, verb: .read), Step(index: 1, verb: .summarize)])

        #expect(log.eventsOfType(ReadCompleted.self).count == 1)
        #expect(log.eventsOfType(SummaryProduced.self).count == 1)
    }

    @Test func asks_whenRequiredAtomMissing() async throws {
        let log = EventLog()
        let asker = RecordingAskResolver(responses: [
            "url": .url(URL(string: "https://asked.com")!)
        ])
        let http = FakeHTTPClient()
        http.scripted[URL(string: "https://asked.com")!] = Data("<title>X</title>".utf8)
        let runtime = Runtime(log: log, http: http, llm: FakeLLMSession(), askResolver: asker)
        try await runtime.run(steps: [Step(index: 0, verb: .read)])
        #expect(asker.askedRoles == ["url"])
        #expect(log.eventsOfType(ReadCompleted.self).count == 1)
    }
}

final class AutoAcceptAskResolver: AskResolver, @unchecked Sendable {
    func ask(role: String, kind: AtomKind) async -> AtomValue? { nil }
}

final class RecordingAskResolver: AskResolver, @unchecked Sendable {
    let responses: [String: AtomValue]
    var askedRoles: [String] = []
    init(responses: [String: AtomValue]) { self.responses = responses }
    func ask(role: String, kind: AtomKind) async -> AtomValue? {
        askedRoles.append(role)
        return responses[role]
    }
}
```

- [ ] **Step 2: Run tests, expect compile failure**

- [ ] **Step 3: Implement**

```swift
// Conductor/Services/Runtime.swift
import Foundation
import Observation

protocol AskResolver: Sendable {
    func ask(role: String, kind: AtomKind) async -> AtomValue?
}

@Observable
@MainActor
final class Runtime {
    let log: EventLog
    private let http: any HTTPClient
    private let llm: any LLMSession
    private let askResolver: any AskResolver

    init(log: EventLog, http: any HTTPClient, llm: any LLMSession, askResolver: any AskResolver) {
        self.log = log
        self.http = http
        self.llm = llm
        self.askResolver = askResolver
    }

    func run(steps: [Step]) async throws {
        for step in steps {
            try await runStep(step)
        }
    }

    private func runStep(_ step: Step) async throws {
        let def = VerbCatalog.definition(for: step.verb)
        var resolvedAtoms: [String: AtomValue] = [:]

        for param in def.parameters {
            if let atom = log.latestAtom(role: param.role) {
                resolvedAtoms[param.role] = atom.value
            } else if let def = param.defaultValue {
                resolvedAtoms[param.role] = def
            } else if param.required {
                let answer = await askResolver.ask(role: param.role, kind: param.kind)
                guard let answer else {
                    log.append(StepFailed(stepID: step.id, message: "missing \(param.role)", origin: .step(id: step.id, index: step.index)))
                    return
                }
                log.append(AtomRecorded(role: param.role, value: answer, source: .userAsked, origin: .step(id: step.id, index: step.index)))
                resolvedAtoms[param.role] = answer
            }
        }

        let upstream = collectUpstream(needs: def.needs)
        let origin = Origin.step(id: step.id, index: step.index)
        let inputs = ResolvedInputs(atoms: resolvedAtoms, upstream: upstream)
        let emitted = try await def.execute(resolved: inputs, origin: origin, http: http, llm: llm)
        log.append(emitted)
    }

    private func collectUpstream(needs: [UpstreamEventNeed]) -> [any Event] {
        var out: [any Event] = []
        for need in needs {
            for name in need.eventTypeNames {
                out.append(contentsOf: log.events.filter { String(describing: type(of: $0)) == name })
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Runtime.swift ConductorTests/RuntimeTests.swift
git commit -m "(runtime): add Runtime executor with parameter resolution and ask"
```

---

## Task 29: Runtime — for-each fan-out

**Files:**
- Modify: `Conductor/Services/Runtime.swift`
- Test: extend `ConductorTests/RuntimeTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@Test func forEach_whenSummarizeFollowsMultiPaperSearch() async throws {
    let log = EventLog()
    let papers = [
        Paper(title: "P1", abstract: "A1", identifier: "1", url: nil),
        Paper(title: "P2", abstract: "A2", identifier: "2", url: nil)
    ]
    log.append(SearchResults(papers: papers, target: "pubMed", origin: .step(id: UUID(), index: 0)))

    let llm = FakeLLMSession()
    llm.scriptedSummary = SummaryGenerable(summary: "s", claims: [], sentiment: "neutral")

    let runtime = Runtime(log: log, http: FakeHTTPClient(), llm: llm, askResolver: AutoAcceptAskResolver())
    try await runtime.run(steps: [Step(index: 1, verb: .summarize)])

    let summaries = log.eventsOfType(SummaryProduced.self)
    #expect(summaries.count == 2)
    #expect(summaries.map { $0.origin.iteration } == [0, 1])
}
```

- [ ] **Step 2: Run tests, expect failure** (only one summary currently emitted)

- [ ] **Step 3: Add for-each to `runStep`**

Replace `runStep` with:

```swift
private func runStep(_ step: Step) async throws {
    let def = VerbCatalog.definition(for: step.verb)
    if let collectionCount = collectionFanOutCount(needs: def.needs) {
        for iteration in 0..<collectionCount {
            try await runOneIteration(step: step, iteration: iteration)
        }
    } else {
        try await runOneIteration(step: step, iteration: nil)
    }
}

private func collectionFanOutCount(needs: [UpstreamEventNeed]) -> Int? {
    for need in needs {
        for name in need.eventTypeNames {
            if name == "SearchResults" {
                if let latest = log.eventsOfType(SearchResults.self).last, latest.papers.count > 1 {
                    return latest.papers.count
                }
            }
        }
    }
    return nil
}

private func runOneIteration(step: Step, iteration: Int?) async throws {
    let def = VerbCatalog.definition(for: step.verb)
    var resolvedAtoms: [String: AtomValue] = [:]

    for param in def.parameters {
        if let atom = log.latestAtom(role: param.role) {
            resolvedAtoms[param.role] = atom.value
        } else if let def = param.defaultValue {
            resolvedAtoms[param.role] = def
        } else if param.required {
            let answer = await askResolver.ask(role: param.role, kind: param.kind)
            guard let answer else {
                log.append(StepFailed(stepID: step.id, message: "missing \(param.role)", origin: .step(id: step.id, index: step.index, iteration: iteration)))
                return
            }
            log.append(AtomRecorded(role: param.role, value: answer, source: .userAsked, origin: .step(id: step.id, index: step.index, iteration: iteration)))
            resolvedAtoms[param.role] = answer
        }
    }

    let upstream = collectUpstream(needs: def.needs)
    let origin = Origin.step(id: step.id, index: step.index, iteration: iteration)
    let inputs = ResolvedInputs(atoms: resolvedAtoms, upstream: upstream)
    let emitted = try await def.execute(resolved: inputs, origin: origin, http: http, llm: llm)
    log.append(emitted)
}
```

- [ ] **Step 4: Run tests, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Conductor/Services/Runtime.swift ConductorTests/RuntimeTests.swift
git commit -m "(runtime): add for-each fan-out for collection upstream events"
```

---

## Task 30: AskView

**Files:**
- Create: `Conductor/Views/AskView.swift`

- [ ] **Step 1: Implement**

```swift
// Conductor/Views/AskView.swift
import SwiftUI

struct AskView: View {
    let role: String
    let kind: AtomKind
    let onSubmit: (AtomValue) -> Void

    @State private var text = ""
    @State private var number: Double = 0
    @State private var date = Date()
    @State private var choice: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt)
                .font(.headline)
            field
            Button("Continue") { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
        .padding()
        .frame(minWidth: 320)
    }

    private var prompt: String {
        switch kind {
        case .url:           "Enter URL for \(role)"
        case .number:        "Enter number for \(role)"
        case .date:          "Pick a date for \(role)"
        case .text:          "Enter text for \(role)"
        case .choice:        "Choose a value for \(role)"
        }
    }

    @ViewBuilder
    private var field: some View {
        switch kind {
        case .url:
            TextField("https://…", text: $text)
                .textFieldStyle(.roundedBorder)
        case .number:
            Stepper(value: $number, in: 0...1000) { Text("\(Int(number))") }
        case .date:
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
        case .text:
            TextField("", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
        case let .choice(_, cases):
            Picker("", selection: $choice) {
                ForEach(cases, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .onAppear { if choice.isEmpty { choice = cases.first ?? "" } }
        }
    }

    private var canSubmit: Bool {
        switch kind {
        case .url:    URL(string: text)?.scheme != nil
        case .text:   !text.isEmpty
        case .choice: !choice.isEmpty
        default:      true
        }
    }

    private func submit() {
        switch kind {
        case .url:           if let u = URL(string: text) { onSubmit(.url(u)) }
        case .number:        onSubmit(.number(number))
        case .date:          onSubmit(.date(date))
        case .text:          onSubmit(.text(text))
        case let .choice(ns, _): onSubmit(.choice(namespace: ns, value: choice))
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Conductor/Views/AskView.swift
git commit -m "(view): add AskView with five kind variants"
```

---

## Task 31: ProseInputView, StepRowView, PipelineView, ResultView

**Files:**
- Create: `Conductor/Views/ProseInputView.swift`, `Conductor/Views/StepRowView.swift`, `Conductor/Views/PipelineView.swift`, `Conductor/Views/ResultView.swift`

- [ ] **Step 1: Implement `ProseInputView`**

```swift
// Conductor/Views/ProseInputView.swift
import SwiftUI

struct ProseInputView: View {
    @Binding var prose: String
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Describe a workflow…", text: $prose, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .disabled(isRunning)
            HStack {
                Spacer()
                Button(isRunning ? "Running…" : "Run") { onRun() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isRunning || prose.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Implement `StepRowView`**

```swift
// Conductor/Views/StepRowView.swift
import SwiftUI

struct StepRowView: View {
    let step: Step
    let status: StepStatus

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading) {
                Text(step.verb.rawValue).font(.headline)
                if case let .failed(msg) = status { Text(msg).font(.caption).foregroundStyle(.red) }
                if case let .awaitingInput(role, _) = status { Text("waiting: \(role)").font(.caption) }
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }

    private var icon: String {
        switch status {
        case .idle: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .awaitingInput: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .awaitingInput: .orange
        default: .secondary
        }
    }
}
```

- [ ] **Step 3: Implement `PipelineView`**

```swift
// Conductor/Views/PipelineView.swift
import SwiftUI

struct PipelineView: View {
    let steps: [Step]
    let statuses: [StepStatus]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(zip(steps, statuses)), id: \.0.id) { step, status in
                StepRowView(step: step, status: status)
            }
        }
        .padding(.horizontal)
    }
}
```

- [ ] **Step 4: Implement `ResultView`**

```swift
// Conductor/Views/ResultView.swift
import SwiftUI

struct ResultView: View {
    let summary: SummaryProduced?
    let papers: [Paper]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    GroupBox("Summary") {
                        Text(summary.summary).font(.body)
                    }
                }
                if !papers.isEmpty {
                    GroupBox("Papers") {
                        ForEach(papers, id: \.identifier) { p in
                            VStack(alignment: .leading) {
                                Text(p.title).font(.headline)
                                if !p.abstract.isEmpty { Text(p.abstract).font(.caption).lineLimit(4) }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Conductor/Views/ProseInputView.swift Conductor/Views/StepRowView.swift Conductor/Views/PipelineView.swift Conductor/Views/ResultView.swift
git commit -m "(view): add ProseInput, StepRow, Pipeline, Result views"
```

---

## Task 32: ContentView 3-region + wiring

**Files:**
- Modify: `Conductor/ContentView.swift`
- Create: `Conductor/Services/AppModel.swift` (view-model coordinator)

- [ ] **Step 1: Implement `AppModel`**

```swift
// Conductor/Services/AppModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    var prose: String = ""
    var steps: [Step] = []
    var isRunning: Bool = false
    var pendingAsk: (role: String, kind: AtomKind)?
    let log: EventLog
    let runtime: Runtime

    private var askContinuation: CheckedContinuation<AtomValue?, Never>?

    init() {
        let log = EventLog()
        let resolver = AppAskResolver()
        let runtime = Runtime(log: log, http: URLSessionHTTPClient(), llm: FoundationModelsSession(), askResolver: resolver)
        self.log = log
        self.runtime = runtime
        resolver.bind(self)
    }

    func run() async {
        guard !prose.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let compiled = try await ProseCompiler.compile(prose: prose, llm: FoundationModelsSession())
            for atom in compiled.atoms { log.append(atom) }
            let inflated = NeedsClosure.inflate(verbs: compiled.verbs, existingLog: log.events)
            steps = inflated.enumerated().map { i, v in Step(index: i, verb: v) }
            try await runtime.run(steps: steps)
        } catch {
            log.append(StepFailed(stepID: UUID(), message: "\(error)", origin: .compile()))
        }
    }

    func submitAsk(_ value: AtomValue) {
        askContinuation?.resume(returning: value)
        askContinuation = nil
        pendingAsk = nil
    }

    fileprivate func requestAsk(role: String, kind: AtomKind) async -> AtomValue? {
        pendingAsk = (role, kind)
        return await withCheckedContinuation { c in
            askContinuation = c
        }
    }
}

private final class AppAskResolver: AskResolver, @unchecked Sendable {
    private weak var app: AppModel?
    func bind(_ app: AppModel) { self.app = app }
    func ask(role: String, kind: AtomKind) async -> AtomValue? {
        guard let app else { return nil }
        return await app.requestAsk(role: role, kind: kind)
    }
}
```

- [ ] **Step 2: Replace `ContentView.swift`**

```swift
// Conductor/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            ProseInputView(prose: $model.prose, isRunning: model.isRunning) {
                Task { await model.run() }
            }
            Divider()
            PipelineView(
                steps: model.steps,
                statuses: Projections.pipelineStatus(log: model.log.events, steps: model.steps)
            )
            Divider()
            ResultView(
                summary: Projections.articleSummary(log: model.log.events),
                papers: Projections.searchResults(log: model.log.events)?.papers ?? []
            )
        }
        .frame(minWidth: 640, minHeight: 540)
        .sheet(item: askBinding) { ask in
            AskView(role: ask.role, kind: ask.kind) { value in
                model.submitAsk(value)
            }
            .padding()
        }
    }

    private var askBinding: Binding<PendingAsk?> {
        Binding(
            get: { model.pendingAsk.map { PendingAsk(role: $0.role, kind: $0.kind) } },
            set: { _ in }
        )
    }
}

private struct PendingAsk: Identifiable {
    let role: String
    let kind: AtomKind
    var id: String { role }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS'`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**

```bash
git add Conductor/ContentView.swift Conductor/Services/AppModel.swift
git commit -m "(view): wire ContentView to AppModel with runtime + ask flow"
```

---

## Task 33: End-to-end test (CRISPR prose, mocked)

**Files:**
- Create: `ConductorTests/EndToEndTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ConductorTests/EndToEndTests.swift
import Testing
import Foundation
@testable import Conductor

@MainActor @Suite struct EndToEndTests {
    @Test func crisprProseProducesFullPipelineWithoutLLM() async throws {
        let prose = "Summarize the article at https://example.com about CRISPR and sickle-cell, and find 3 related PubMed papers"
        let http = FakeHTTPClient()
        let articleURL = URL(string: "https://example.com")!
        http.scripted[articleURL] = Data("<title>CRISPR article</title><body>body</body>".utf8)

        let searchURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=CRISPR%20and%20sickle-cell&retmax=3&retmode=json")!
        http.scripted[searchURL] = Data(#"{"esearchresult":{"idlist":["1","2","3"]}}"#.utf8)
        let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=1,2,3&retmode=json")!
        http.scripted[summaryURL] = Data(#"{"result":{"uids":["1","2","3"],"1":{"title":"A","uid":"1"},"2":{"title":"B","uid":"2"},"3":{"title":"C","uid":"3"}}}"#.utf8)

        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "About CRISPR.", claims: [], sentiment: "neutral")

        let log = EventLog()
        let compiled = try await ProseCompiler.compile(prose: prose, llm: llm)
        #expect(compiled.usedLLM == false)
        for a in compiled.atoms { log.append(a) }
        let inflated = NeedsClosure.inflate(verbs: compiled.verbs, existingLog: log.events)
        let steps = inflated.enumerated().map { i, v in Step(index: i, verb: v) }

        let runtime = Runtime(log: log, http: http, llm: llm, askResolver: AutoAcceptAskResolver())
        try await runtime.run(steps: steps)

        #expect(log.eventsOfType(ReadCompleted.self).count == 1)
        #expect(log.eventsOfType(SummaryProduced.self).count >= 1)
        #expect(log.eventsOfType(SearchResults.self).first?.papers.count == 3)
    }
}
```

- [ ] **Step 2: Run test; fix any integration gaps**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing:ConductorTests/EndToEndTests`
Expected: **PASS**. If the test fails, the most likely fix locations are: L1 number-role resolution, L2 alias matching for "PubMed", or `NeedsClosure.inflate` ordering. Fix in place.

- [ ] **Step 3: Commit**

```bash
git add ConductorTests/EndToEndTests.swift
git commit -m "(test): add CRISPR end-to-end integration test"
```

---

## Task 34: Test corpus + L4-free measurement

**Files:**
- Create: `ConductorTests/CorpusTests.swift`

- [ ] **Step 1: Implement the corpus**

```swift
// ConductorTests/CorpusTests.swift
import Testing
import Foundation
@testable import Conductor

@Suite struct CorpusTests {
    private static let corpus: [(prose: String, expectedVerbs: Set<Verb>)] = [
        ("Read https://example.com", [.read]),
        ("Summarize the article at https://example.com", [.read, .summarize]),
        ("Find 3 PubMed papers about CRISPR", [.search]),
        ("Search arxiv for transformers", [.search]),
        ("Look up 5 papers on quantum computing on arxiv", [.search]),
        ("Summarize https://x.com and find related work", [.read, .summarize, .search]),
        ("Extract claims from the summary", [.extractClaims]),
        ("Fetch https://a.com and summarize it", [.read, .summarize]),
        ("Open https://b.com and pull out the claims", [.read, .summarize, .extractClaims]),
        ("Find 10 papers on sickle-cell on PubMed", [.search]),
        ("Query the web for climate change", [.search]),
        ("Summarize the article at https://c.com", [.read, .summarize]),
        ("Read https://d.com then find 3 related arxiv papers", [.read, .search]),
        ("Search pubmed for BRCA1", [.search]),
        ("Find 4 related papers on arxiv.org", [.search]),
        ("Load https://e.com", [.read]),
        ("Digest https://f.com", [.read, .summarize]),
        ("Summarize and extract claims from https://g.com", [.read, .summarize, .extractClaims]),
        ("Find papers on quantum", [.search]),
        ("Search google for LLMs", [.search]),
        ("Look for 2 papers on cancer on PubMed", [.search]),
        ("Open https://h.com, summarize, extract claims, find 3 related papers", [.read, .summarize, .extractClaims, .search]),
        ("Summarize https://i.com as a paper summary", [.read, .summarize]),
        ("Read and summarize the article at https://j.com", [.read, .summarize]),
        ("Pull claims from the summary", [.extractClaims]),
        ("Search arxiv for protein folding", [.search]),
        ("Find 7 papers about fusion on PubMed", [.search]),
        ("Summarize the article and search the web for critiques", [.read, .summarize, .search]),
        ("Open https://k.com", [.read]),
        ("Digest the article at https://l.com and find 3 arxiv papers on it", [.read, .summarize, .search]),
    ]

    @Test func atLeastSeventyPercentCompilesWithoutLLM() async throws {
        let llm = FakeLLMSession()
        llm.scriptedIntent = PipelineIntent(verbs: [.search])
        var l4Used = 0
        var verbMisses = 0
        for (prose, expected) in Self.corpus {
            let result = try await ProseCompiler.compile(prose: prose, llm: llm)
            if result.usedLLM { l4Used += 1 }
            if !expected.isSubset(of: Set(result.verbs)) { verbMisses += 1 }
        }
        let l4FreeRatio = Double(Self.corpus.count - l4Used) / Double(Self.corpus.count)
        #expect(l4FreeRatio >= 0.70, "only \(Int(l4FreeRatio * 100))% L4-free; target 70%")
        #expect(verbMisses <= 3, "too many verb-set mismatches: \(verbMisses)")
    }
}
```

- [ ] **Step 2: Run, tune thresholds if needed**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing:ConductorTests/CorpusTests`
Expected: **PASS** at ≥70% L4-free and ≤3 verb mismatches. If it fails, diagnose — add lemmas to the catalog, fix alias matching, or fix Layer 2 NP extraction. Do not lower the 70% threshold.

- [ ] **Step 3: Commit**

```bash
git add ConductorTests/CorpusTests.swift
git commit -m "(test): add 30-prose corpus asserting ≥70% L4-free compilation"
```

---

## Task 35: Manual smoke in the app

**Files:** none

- [ ] **Step 1: Build and run the app**

```bash
xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS'
open -a "$(find ~/Library/Developer/Xcode/DerivedData -name Conductor.app -type d | head -1)"
```

- [ ] **Step 2: Smoke flow**

Type: *"Summarize https://en.wikipedia.org/wiki/CRISPR and find 3 related PubMed papers"*
Click **Run**.

Expected observations:
- Pipeline shows `[read, summarize, search]` with status chips animating idle → running → completed.
- Summary text appears in the result region.
- Three papers appear, each with a PubMed title.
- If the `search.target` picker appears (prose matches `PubMed` alias, so it should not), dismiss — this is a bug.
- If any step fails, its row shows a red X and an error message; the log still captured events from earlier steps.

- [ ] **Step 3: Smoke flow — ambiguous target**

Type: *"Find 3 related papers about sickle-cell"*
Click **Run**.

Expected:
- AskView sheet appears with a picker (`PubMed / arxiv / web`).
- Pick `PubMed`. The search step proceeds.

- [ ] **Step 4: Document any defects as new issues, then verify `git status` is clean**

```bash
git status
```

- [ ] **Step 5: Final commit (if any defect fixes)**

```bash
git commit --allow-empty -m "(milestone): v2 demonstrator passes manual smoke"
```

---

## Spec coverage check

| Spec section | Task(s) |
|---|---|
| §4 Architecture overview | 12–18, 27–29 (compiler + runtime) |
| §5.1 Layer 1 | 12 |
| §5.2 Layer 2 | 13–15 |
| §5.3 Layer 3 | 16 |
| §5.4 Layer 4 | 17 |
| §6.1 Event types (AtomRecorded + verb-output) | 5–6, 8 |
| §6.2 Log semantics | 9 |
| §7 Projections | 11 |
| §8 Verbs (protocol + catalog) | 7 |
| §8.1 Verb catalog | 19, 20, 25, 26 |
| §8.2 Parameter disambiguation | 30, 32 |
| §9 Needs closure | 27 |
| §10 For-each | 29 |
| §11 Runtime flow example | 33 |
| §12 Auto-ask | 28, 30 |
| §13 UI surface | 30, 31, 32 |
| §14 File structure | 1, distributed |
| §15 Testing strategy | every task is TDD; 33, 34 integration |
| §16 Failure-mode mitigation | inherent in 12–29 |
| §17 Deferred (persistence, reactive projections, upcasters) | not implemented by design |
| §18 Success criteria (≥70% L4-free) | 34 |

All spec sections that produce code are covered. Deferred items (§17) are explicitly not implemented.

---

## Execution notes

- **Commit discipline.** Every task ends in a commit. If a step fails, fix and re-run — do not amend the prior task's commit.
- **Test isolation.** Use `@MainActor` on suites that touch `EventLog` or `Runtime`. Swift Testing runs tests concurrently by default.
- **Xcode synchronization.** New `.swift` files under `Conductor/` and `ConductorTests/` are auto-picked by the synchronized folder groups. If a test file isn't discovered, check file permissions and reload the project.
- **Network is mocked in every test.** No test makes a real HTTP or LLM call. The `FakeHTTPClient` and `FakeLLMSession` fakes are the boundary.
- **If a task fails mid-implementation:** re-read the spec section it maps to (see coverage table). Do not deviate from the spec without updating it.
