# Automator Workflow Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the on-device model translate natural language into macOS Automator `.workflow` files via a two-tool system (search + build) with a preview card UI.

**Architecture:** A lazily-built `AutomatorActionIndex` actor scans `/System/Library/Automator/` for `.action` bundle metadata. `SearchAutomatorActionsTool` queries the index. `BuildAutomatorWorkflowTool` assembles an `AMWorkflow` and writes it to a temp file. The UI renders a `WorkflowPreview` card with Save/Regenerate buttons. All Automator code is macOS-only behind `#if os(macOS)`.

**Tech Stack:** Swift 6, FoundationModels, Automator.framework (`AMWorkflow`, `AMAction`, `AMBundleAction`), SwiftUI, Swift Testing

---

## File Structure

```
Conductor/
  Tools/
    Automator/
      AutomatorActionInfo.swift          (struct: indexed action metadata)
      AutomatorActionIndex.swift         (actor: lazy scan, index, search)
      SearchAutomatorActionsTool.swift   (FoundationModels BadgedTool)
      BuildAutomatorWorkflowTool.swift   (FoundationModels BadgedTool)
      WorkflowPreview.swift              (structs: preview model for UI)
  Tools/
    ToolSupport.swift                    (modify: add workflowPreview to ToolUsageTracker)
  ContentView.swift                      (modify: Message gets workflowPreview, UI renders card, tool registration, entitlements)

ConductorTests/
  AutomatorActionIndexTests.swift        (plist parsing, search matching)
  WorkflowPreviewTests.swift             (Codable round-trip)
```

---

### Task 1: AutomatorActionInfo struct

**Files:**
- Create: `Conductor/Tools/Automator/AutomatorActionInfo.swift`
- Test: `ConductorTests/AutomatorActionIndexTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ConductorTests/AutomatorActionIndexTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("AutomatorActionIndex Tests")
struct AutomatorActionIndexTests {

    @Test("Parses Info.plist dictionary into AutomatorActionInfo")
    func parsesInfoPlist() throws {
        let plist: [String: Any] = [
            "AMName": "Scale Images",
            "AMCategory": "AMCategoryPhotos",
            "AMKeywords": ["resize", "scale", "images", "photos"],
            "AMDescription": ["AMDSummary": "Scales images to a specific size."],
            "AMAccepts": [
                "Types": ["public.image"],
                "Container": "List",
            ],
            "AMProvides": [
                "Types": ["public.image"],
                "Container": "List",
            ],
            "AMDefaultParameters": [
                "scaleFactor": 0.5,
                "scaleType": 0,
            ],
        ]

        let bundleURL = URL(fileURLWithPath: "/System/Library/Automator/Scale Images.action")
        let info = AutomatorActionInfo(bundleURL: bundleURL, plist: plist)

        #expect(info.name == "Scale Images")
        #expect(info.category == "AMCategoryPhotos")
        #expect(info.keywords == ["resize", "scale", "images", "photos"])
        #expect(info.descriptionSummary == "Scales images to a specific size.")
        #expect(info.inputTypes == ["public.image"])
        #expect(info.inputContainer == "List")
        #expect(info.outputTypes == ["public.image"])
        #expect(info.outputContainer == "List")
        #expect(info.defaultParameters["scaleFactor"] == "0.5")
        #expect(info.defaultParameters["scaleType"] == "0")
        #expect(info.bundleURL == bundleURL)
    }

    @Test("Handles missing optional plist keys gracefully")
    func handlesMissingKeys() throws {
        let plist: [String: Any] = [
            "AMName": "Some Action",
        ]
        let bundleURL = URL(fileURLWithPath: "/System/Library/Automator/Some Action.action")
        let info = AutomatorActionInfo(bundleURL: bundleURL, plist: plist)

        #expect(info.name == "Some Action")
        #expect(info.category == "")
        #expect(info.keywords.isEmpty)
        #expect(info.descriptionSummary == "")
        #expect(info.inputTypes.isEmpty)
        #expect(info.outputTypes.isEmpty)
        #expect(info.defaultParameters.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests/AutomatorActionIndexTests -quiet 2>&1 | tail -10`

Expected: FAIL — `AutomatorActionInfo` not defined.

- [ ] **Step 3: Implement AutomatorActionInfo**

Create `Conductor/Tools/Automator/AutomatorActionInfo.swift`:

```swift
import Foundation

struct AutomatorActionInfo: Sendable {
    let bundleURL: URL
    let name: String
    let category: String
    let keywords: [String]
    let descriptionSummary: String
    let inputTypes: [String]
    let inputContainer: String
    let outputTypes: [String]
    let outputContainer: String
    let defaultParameters: [String: String]

    init(bundleURL: URL, plist: [String: Any]) {
        self.bundleURL = bundleURL
        name = plist["AMName"] as? String ?? ""
        category = plist["AMCategory"] as? String ?? ""
        keywords = plist["AMKeywords"] as? [String] ?? []

        let descDict = plist["AMDescription"] as? [String: Any]
        descriptionSummary = descDict?["AMDSummary"] as? String ?? ""

        let accepts = plist["AMAccepts"] as? [String: Any]
        inputTypes = accepts?["Types"] as? [String] ?? []
        inputContainer = accepts?["Container"] as? String ?? ""

        let provides = plist["AMProvides"] as? [String: Any]
        outputTypes = provides?["Types"] as? [String] ?? []
        outputContainer = provides?["Container"] as? String ?? ""

        let params = plist["AMDefaultParameters"] as? [String: Any] ?? [:]
        var stringParams: [String: String] = [:]
        for (key, value) in params {
            stringParams[key] = "\(value)"
        }
        defaultParameters = stringParams
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests/AutomatorActionIndexTests -quiet 2>&1 | tail -10`

Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/Automator/AutomatorActionInfo.swift ConductorTests/AutomatorActionIndexTests.swift
git commit -m "(automator): add AutomatorActionInfo struct with plist parsing"
```

---

### Task 2: AutomatorActionIndex actor with search

**Files:**
- Create: `Conductor/Tools/Automator/AutomatorActionIndex.swift`
- Modify: `ConductorTests/AutomatorActionIndexTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `ConductorTests/AutomatorActionIndexTests.swift`:

```swift
    // MARK: - Search

    @Test("Matches actions by name substring")
    func searchByName() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: ["AMName": "Scale Images"]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: ["AMName": "Copy Finder Items"]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/c.action"), plist: ["AMName": "Move Finder Items"]),
        ]
        let index = AutomatorActionIndex(preloaded: actions)
        let results = await index.search(query: "scale", inputType: nil, maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].name == "Scale Images")
    }

    @Test("Matches actions by keyword")
    func searchByKeyword() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: [
                "AMName": "Scale Images",
                "AMKeywords": ["resize", "shrink"],
            ]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: ["AMName": "Ask for Text"]),
        ]
        let index = AutomatorActionIndex(preloaded: actions)
        let results = await index.search(query: "resize", inputType: nil, maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].name == "Scale Images")
    }

    @Test("Filters by input UTI type")
    func searchFiltersByInputType() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: [
                "AMName": "Scale Images",
                "AMAccepts": ["Types": ["public.image"], "Container": "List"],
            ]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: [
                "AMName": "Combine PDF Pages",
                "AMAccepts": ["Types": ["com.adobe.pdf"], "Container": "List"],
            ]),
        ]
        let index = AutomatorActionIndex(preloaded: actions)
        let results = await index.search(query: "", inputType: "public.image", maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].name == "Scale Images")
    }

    @Test("Respects maxResults limit")
    func searchRespectsLimit() async {
        let actions = (1...10).map { i in
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/\(i).action"), plist: ["AMName": "Action \(i)"])
        }
        let index = AutomatorActionIndex(preloaded: actions)
        let results = await index.search(query: "action", inputType: nil, maxResults: 3)
        #expect(results.count == 3)
    }

    @Test("Case-insensitive search")
    func searchCaseInsensitive() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: ["AMName": "Scale Images"]),
        ]
        let index = AutomatorActionIndex(preloaded: actions)
        let results = await index.search(query: "SCALE", inputType: nil, maxResults: 5)
        #expect(results.count == 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests/AutomatorActionIndexTests -quiet 2>&1 | tail -10`

Expected: FAIL — `AutomatorActionIndex` not defined.

- [ ] **Step 3: Implement AutomatorActionIndex**

Create `Conductor/Tools/Automator/AutomatorActionIndex.swift`:

```swift
import Foundation

actor AutomatorActionIndex {
    private var actions: [AutomatorActionInfo] = []
    private var isLoaded = false

    init() {}

    /// Test-only initializer with preloaded actions.
    init(preloaded: [AutomatorActionInfo]) {
        actions = preloaded
        isLoaded = true
    }

    func search(query: String, inputType: String?, maxResults: Int) -> [AutomatorActionInfo] {
        if !isLoaded {
            loadIndex()
        }

        let queryLower = query.lowercased()
        var results = actions

        if !queryLower.isEmpty {
            results = results.filter { action in
                action.name.lowercased().contains(queryLower)
                || action.category.lowercased().contains(queryLower)
                || action.descriptionSummary.lowercased().contains(queryLower)
                || action.keywords.contains { $0.lowercased().contains(queryLower) }
            }
        }

        if let inputType {
            results = results.filter { $0.inputTypes.contains(inputType) }
        }

        return Array(results.prefix(maxResults))
    }

    private func loadIndex() {
        let automatorDir = URL(fileURLWithPath: "/System/Library/Automator")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: automatorDir,
            includingPropertiesForKeys: nil
        ) else {
            isLoaded = true
            return
        }

        for bundleURL in contents where bundleURL.pathExtension == "action" {
            let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }
            actions.append(AutomatorActionInfo(bundleURL: bundleURL, plist: plist))
        }

        isLoaded = true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests/AutomatorActionIndexTests -quiet 2>&1 | tail -10`

Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Conductor/Tools/Automator/AutomatorActionIndex.swift ConductorTests/AutomatorActionIndexTests.swift
git commit -m "(automator): add AutomatorActionIndex actor with search"
```

---

### Task 3: SearchAutomatorActionsTool

**Files:**
- Create: `Conductor/Tools/Automator/SearchAutomatorActionsTool.swift`

- [ ] **Step 1: Create the tool**

Create `Conductor/Tools/Automator/SearchAutomatorActionsTool.swift`:

```swift
#if os(macOS)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct SearchAutomatorActionsTool: BadgedTool {
    let name = "searchAutomatorActions"
    let description = "Search for macOS Automator actions by keyword. Use this to discover available actions before building a workflow. Returns action names, descriptions, input/output types, and configurable parameters."
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "gear.badge", tint: .gray, label: "Automator")

    private let index: AutomatorActionIndex

    init(tracker: ToolUsageTracker, index: AutomatorActionIndex) {
        self.tracker = tracker
        self.index = index
    }

    @Generable
    struct Arguments {
        @Guide(description: "Keywords to search for in action names, categories, and descriptions")
        var searchQuery: String

        @Guide(description: "Optional UTI filter to find actions that accept a specific input type (e.g. public.image)")
        var inputType: String?

        @Guide(description: "Maximum number of results to return (default 5)")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(badge)

        let max = arguments.maxResults ?? 5
        let query = arguments.searchQuery
        let results = await index.search(query: query, inputType: arguments.inputType, maxResults: max)

        guard !results.isEmpty else {
            return "No Automator actions found matching \"\(query)\". Try different keywords."
        }

        var lines = ["Automator actions matching \"\(query)\":\n"]
        for (i, action) in results.enumerated() {
            let params = action.defaultParameters.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            let inputDesc = action.inputTypes.isEmpty ? "None" : "\(action.inputTypes.joined(separator: ", ")) (\(action.inputContainer))"
            let outputDesc = action.outputTypes.isEmpty ? "None" : "\(action.outputTypes.joined(separator: ", ")) (\(action.outputContainer))"

            lines.append("""
                \(i + 1). \(action.name) (\(action.category))
                   Description: \(action.descriptionSummary.isEmpty ? "No description" : action.descriptionSummary)
                   Accepts: \(inputDesc)
                   Provides: \(outputDesc)
                   Parameters: \(params.isEmpty ? "None" : params)
                   Bundle: \(action.bundleURL.path)
                """)
        }

        return lines.joined(separator: "\n")
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Clean build (tool not yet registered, but compiles).

- [ ] **Step 3: Commit**

```bash
git add Conductor/Tools/Automator/SearchAutomatorActionsTool.swift
git commit -m "(automator): add SearchAutomatorActionsTool"
```

---

### Task 4: WorkflowPreview types and ToolUsageTracker extension

**Files:**
- Create: `Conductor/Tools/Automator/WorkflowPreview.swift`
- Modify: `Conductor/Tools/ToolSupport.swift`
- Test: `ConductorTests/WorkflowPreviewTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ConductorTests/WorkflowPreviewTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("WorkflowPreview Tests")
struct WorkflowPreviewTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let preview = WorkflowPreview(
            title: "Resize Images",
            steps: [
                WorkflowStepPreview(actionName: "Ask for Finder Items", parameterSummary: "type=files", outputType: "public.file-url"),
                WorkflowStepPreview(actionName: "Scale Images", parameterSummary: "scaleFactor=800", outputType: "public.image"),
            ],
            tempFileURL: URL(fileURLWithPath: "/tmp/workflow.workflow")
        )

        let data = try JSONEncoder().encode(preview)
        let decoded = try JSONDecoder().decode(WorkflowPreview.self, from: data)

        #expect(decoded.title == "Resize Images")
        #expect(decoded.steps.count == 2)
        #expect(decoded.steps[0].actionName == "Ask for Finder Items")
        #expect(decoded.steps[1].parameterSummary == "scaleFactor=800")
        #expect(decoded.tempFileURL.path == "/tmp/workflow.workflow")
    }

    @Test("Empty steps array round-trips")
    func emptySteps() throws {
        let preview = WorkflowPreview(
            title: "Empty Workflow",
            steps: [],
            tempFileURL: URL(fileURLWithPath: "/tmp/empty.workflow")
        )
        let data = try JSONEncoder().encode(preview)
        let decoded = try JSONDecoder().decode(WorkflowPreview.self, from: data)
        #expect(decoded.steps.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests/WorkflowPreviewTests -quiet 2>&1 | tail -10`

Expected: FAIL — `WorkflowPreview` not defined.

- [ ] **Step 3: Create WorkflowPreview.swift**

Create `Conductor/Tools/Automator/WorkflowPreview.swift`:

```swift
import Foundation

struct WorkflowStepPreview: Codable, Hashable {
    let actionName: String
    let parameterSummary: String
    let outputType: String
}

struct WorkflowPreview: Codable, Hashable {
    let title: String
    let steps: [WorkflowStepPreview]
    let tempFileURL: URL
}
```

- [ ] **Step 4: Add workflowPreview to ToolUsageTracker**

In `Conductor/Tools/ToolSupport.swift`, add a workflow preview field to the `ToolUsageTracker` actor. After the existing `sources` property and methods, add:

```swift
    private var workflowPreview: WorkflowPreview?

    func setWorkflowPreview(_ preview: WorkflowPreview) {
        workflowPreview = preview
    }

    func workflowPreviewSnapshot() -> WorkflowPreview? {
        workflowPreview
    }
```

Also update the existing `reset()` method to clear the workflow preview:

```swift
    func reset() {
        badges.removeAll()
        sources.removeAll()
        workflowPreview = nil
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests/WorkflowPreviewTests -quiet 2>&1 | tail -10`

Expected: 2 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Conductor/Tools/Automator/WorkflowPreview.swift Conductor/Tools/ToolSupport.swift ConductorTests/WorkflowPreviewTests.swift
git commit -m "(automator): add WorkflowPreview types and tracker extension"
```

---

### Task 5: BuildAutomatorWorkflowTool

**Files:**
- Create: `Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift`

- [ ] **Step 1: Create the tool**

Create `Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift`:

```swift
#if os(macOS)
import Foundation
import Automator
import FoundationModels

@available(macOS 26.0, *)
struct BuildAutomatorWorkflowTool: BadgedTool {
    let name = "buildAutomatorWorkflow"
    let description = "Build a macOS Automator workflow from a list of actions and parameters. Call searchAutomatorActions first to discover available actions and their parameters. Returns a workflow preview the user can save as a .workflow file."
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "gear.badge", tint: .gray, label: "Automator")

    @Generable
    struct Arguments {
        @Guide(description: "A descriptive title for the workflow")
        var workflowTitle: String

        @Guide(description: "Ordered list of workflow steps")
        var steps: [WorkflowStep]
    }

    @Generable
    struct WorkflowStep {
        @Guide(description: "Full path to the .action bundle (from searchAutomatorActions results)")
        var actionBundlePath: String

        @Guide(description: "Parameter overrides as key=value pairs. Keys must match parameter names from searchAutomatorActions results.")
        var parameters: [String: String]?
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(badge)

        let workflow = AMWorkflow()
        var stepPreviews: [WorkflowStepPreview] = []
        var errors: [String] = []

        for (i, step) in arguments.steps.enumerated() {
            let bundleURL = URL(fileURLWithPath: step.actionBundlePath)

            guard let action = try? AMAction(contentsOf: bundleURL) else {
                errors.append("Step \(i + 1): Could not load action at \(step.actionBundlePath). Skipping.")
                continue
            }

            if let bundleAction = action as? AMBundleAction, let params = step.parameters {
                let existingParams = bundleAction.parameters ?? NSMutableDictionary()
                for (key, value) in params {
                    existingParams[key] = coerceValue(value, existingDefault: existingParams[key])
                }
                bundleAction.parameters = existingParams
            }

            workflow.addAction(action)

            let paramSummary = step.parameters?.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? ""
            let outputType = (action as? AMBundleAction).flatMap { bundleAction in
                (bundleAction.bundle.infoDictionary?["AMProvides"] as? [String: Any])?["Types"] as? [String]
            }?.first ?? "unknown"

            stepPreviews.append(WorkflowStepPreview(
                actionName: action.name ?? "Unknown Action",
                parameterSummary: paramSummary,
                outputType: outputType
            ))
        }

        guard !stepPreviews.isEmpty else {
            return "Could not build workflow: no valid actions loaded.\(errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = arguments.workflowTitle
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let tempURL = tempDir.appendingPathComponent("\(fileName).workflow")

        do {
            try workflow.write(to: tempURL)
        } catch {
            return "Could not save workflow to temporary location: \(error.localizedDescription)"
        }

        let preview = WorkflowPreview(
            title: arguments.workflowTitle,
            steps: stepPreviews,
            tempFileURL: tempURL
        )
        await tracker.setWorkflowPreview(preview)

        var lines = ["Workflow: \"\(arguments.workflowTitle)\"\n\nSteps:"]
        for (i, step) in stepPreviews.enumerated() {
            let params = step.parameterSummary.isEmpty ? "" : " (\(step.parameterSummary))"
            lines.append("\(i + 1). \(step.actionName)\(params) → [\(step.outputType)]")
        }

        if !errors.isEmpty {
            lines.append("\nWarnings:\n" + errors.joined(separator: "\n"))
        }

        lines.append("\nWorkflow ready. Use the Save button to export as a .workflow file.")

        return lines.joined(separator: "\n")
    }

    private func coerceValue(_ stringValue: String, existingDefault: Any?) -> Any {
        switch existingDefault {
        case is Int:
            return Int(stringValue) ?? stringValue
        case is Double:
            return Double(stringValue) ?? stringValue
        case is Float:
            return Float(stringValue) ?? stringValue
        case is Bool:
            return stringValue.lowercased() == "true"
        default:
            if let intVal = Int(stringValue) { return intVal }
            if let doubleVal = Double(stringValue) { return doubleVal }
            if stringValue.lowercased() == "true" || stringValue.lowercased() == "false" {
                return stringValue.lowercased() == "true"
            }
            return stringValue
        }
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Clean build. Note: `AMAction(contentsOf:)` may need `AMAction(contentsOf:error:)` bridging — adjust if the compiler indicates the ObjC initializer signature.

- [ ] **Step 3: Commit**

```bash
git add Conductor/Tools/Automator/BuildAutomatorWorkflowTool.swift
git commit -m "(automator): add BuildAutomatorWorkflowTool"
```

---

### Task 6: Message model + WorkflowPreview card UI

**Files:**
- Modify: `Conductor/ContentView.swift`

- [ ] **Step 1: Add `workflowPreview` to `Message`**

In `Conductor/ContentView.swift`, update the `Message` struct.

Add the property after `sources`:

```swift
    var workflowPreview: WorkflowPreview?
```

Add `workflowPreview` to the `CodingKeys` enum:

```swift
    enum CodingKeys: String, CodingKey {
        case id, content, isUser, timestamp, toolsUsed, sources, workflowPreview
    }
```

Update the `init` to include the new parameter with a default of `nil`:

```swift
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date, toolsUsed: [ToolBadge] = [], sources: [ToolSource] = [], workflowPreview: WorkflowPreview? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.toolsUsed = toolsUsed
        self.sources = sources
        self.workflowPreview = workflowPreview
    }
```

Update the `init(from decoder:)` to decode it:

```swift
        workflowPreview = try container.decodeIfPresent(WorkflowPreview.self, forKey: .workflowPreview)
```

- [ ] **Step 2: Update `streamResponse` to capture workflow preview**

In the `streamResponse` method in `ChatDetailView`, after the `let usedSources = await toolTracker.sourceSnapshot()` line, add:

```swift
            let workflow = await toolTracker.workflowPreviewSnapshot()
```

And update the `Message` construction to include it:

```swift
            let assistantMessage = Message(
                content: streamingContent,
                isUser: false,
                timestamp: Date(),
                toolsUsed: usedTools,
                sources: usedSources,
                workflowPreview: workflow
            )
```

- [ ] **Step 3: Add workflow card to MessageBubbleView**

In `MessageBubbleView`, add an `@State private var savedPath: String?` property after the existing `@State private var showCopied` property.

After the existing `sources` section (the `if !message.sources.isEmpty { ... }` block) and before the `HStack(spacing: 6)` timestamp bar, add the workflow card:

```swift
                #if os(macOS)
                if let preview = message.workflowPreview {
                    WorkflowCardView(preview: preview, savedPath: $savedPath, onRegenerate: onRegenerate)
                }
                #endif
```

Then add the `WorkflowCardView` as a new struct after `MessageBubbleView`:

```swift
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
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Clean build.

- [ ] **Step 5: Commit**

```bash
git add Conductor/ContentView.swift
git commit -m "(automator): add workflow preview card UI and Message integration"
```

---

### Task 7: Register tools and update entitlements

**Files:**
- Modify: `Conductor/ContentView.swift`
- Modify: `Conductor/Conductor.entitlements`

- [ ] **Step 1: Add a shared AutomatorActionIndex and register tools**

In `Conductor/ContentView.swift`, in the `ChatDetailView` struct, add a private static property for the shared index (after the existing `private static let instructions` block):

```swift
    #if os(macOS)
    private static let automatorIndex = AutomatorActionIndex()
    #endif
```

Then update the `init(chat:chatManager:)` method. Change the tool array construction from:

```swift
        let tools: [any Tool] = [
            WikipediaSearchTool(tracker: tracker),
            PubMedSearchTool(tracker: tracker),
            SemanticScholarSearchTool(tracker: tracker),
            ArXivSearchTool(tracker: tracker),
            OpenAlexSearchTool(tracker: tracker),
            CrossRefSearchTool(tracker: tracker),
        ]
```

to:

```swift
        var tools: [any Tool] = [
            WikipediaSearchTool(tracker: tracker),
            PubMedSearchTool(tracker: tracker),
            SemanticScholarSearchTool(tracker: tracker),
            ArXivSearchTool(tracker: tracker),
            OpenAlexSearchTool(tracker: tracker),
            CrossRefSearchTool(tracker: tracker),
        ]
        #if os(macOS)
        tools.append(contentsOf: [
            SearchAutomatorActionsTool(tracker: tracker, index: Self.automatorIndex),
            BuildAutomatorWorkflowTool(tracker: tracker),
        ] as [any Tool])
        #endif
```

- [ ] **Step 2: Update entitlements**

In `Conductor/Conductor.entitlements`, change `read-only` to `read-write`:

Replace:
```xml
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
```

With:
```xml
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
```

- [ ] **Step 3: Build for macOS to verify everything links**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Clean build.

- [ ] **Step 4: Build for iOS to verify platform guards work**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -quiet 2>&1 | tail -5`

Expected: Clean build. Automator code excluded by `#if os(macOS)`.

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -only-testing:ConductorTests -quiet 2>&1 | tail -25`

Expected: All tests pass (existing + new AutomatorActionIndex + WorkflowPreview tests).

- [ ] **Step 6: Commit**

```bash
git add Conductor/ContentView.swift Conductor/Conductor.entitlements
git commit -m "(automator): register tools and upgrade entitlement to read-write"
```

---

### Task 8: Integration smoke test

**Files:** None (manual testing)

- [ ] **Step 1: Build and run on macOS simulator/device**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -quiet 2>&1 | tail -5`

- [ ] **Step 2: Verify action index loads**

In a new chat, type: "What Automator actions are available for working with images?"

Expected: Model calls `searchAutomatorActions`, returns results with action names, parameters, and bundle paths. Gray Automator badge appears on the response.

- [ ] **Step 3: Verify workflow building**

Type: "Build me a workflow that asks the user to select image files, then scales them to 800 pixels"

Expected: Model calls `buildAutomatorWorkflow` with appropriate steps. Response includes a workflow preview card with numbered steps, data flow arrows, and Save/Regenerate buttons.

- [ ] **Step 4: Verify save flow**

Click the Save button on the workflow card.

Expected: `NSSavePanel` appears with suggested `.workflow` filename. After saving, card shows "Saved to {path}" confirmation. The saved `.workflow` file opens in Automator.app when double-clicked.

- [ ] **Step 5: Verify iOS build is unaffected**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,id=EAD8288B-B048-4D23-BE1D-CCD8416E286E' -quiet 2>&1 | tail -5`

Expected: Clean build, no Automator references leak into iOS.
