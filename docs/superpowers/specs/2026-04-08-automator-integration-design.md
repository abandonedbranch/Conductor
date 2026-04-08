# Automator Workflow Builder — Design Spec

## Overview

Add an Automator integration to Conductor so the on-device FoundationModels agent can translate natural language requests into macOS Automator workflows. The model discovers available actions via a search tool, assembles workflows via a build tool, and presents a preview card the user can save as a `.workflow` file. Conductor never executes workflows — the user runs them in Automator.

## Architecture

### Two-Tool System

Two FoundationModels tools work together:

1. **`searchAutomatorActions`** — Discovery tool. Queries a lazily-built index of all `.action` bundles in `/System/Library/Automator/`. Returns matching actions with metadata and parameter defaults.

2. **`buildAutomatorWorkflow`** — Construction tool. Takes an ordered list of action bundle paths and parameter overrides. Assembles an `AMWorkflow`, writes it to a temp file, returns a structured description that the UI renders as a preview card.

### Flow

```
User: "Resize all images in my Downloads folder to 800px"
  ↓
Model calls searchAutomatorActions(query: "finder items ask")
Model calls searchAutomatorActions(query: "scale resize images")
  ↓
Model receives matching actions with parameters
  ↓
Model calls buildAutomatorWorkflow(
  title: "Resize Download Images",
  steps: [
    { bundle: ".../Ask for Finder Items.action", parameters: {...} },
    { bundle: ".../Scale Images.action", parameters: { scaleFactor: "800" } }
  ]
)
  ↓
UI renders workflow preview card with Save / Regenerate buttons
  ↓
User taps Save → NSSavePanel → .workflow file on disk
User opens .workflow in Automator to review and run
```

## Action Index

### `AutomatorActionIndex` (actor)

Lazily initialized on first tool call. Scans `/System/Library/Automator/` and reads each `.action` bundle's `Info.plist`.

Extracted fields per action:
- **Bundle URL** — full path to the `.action` bundle (used by the build tool to load it)
- **Name** — `AMName` key
- **Category** — `AMCategory` key
- **Keywords** — `AMKeywords` array
- **Description** — `AMDescription.AMDSummary`
- **Input types** — `AMAccepts.Types` (UTI array, e.g., `com.apple.cocoa.path`)
- **Input container** — `AMAccepts.Container` ("List" or "Single")
- **Output types** — `AMProvides.Types`
- **Output container** — `AMProvides.Container`
- **Default parameters** — `AMDefaultParameters` dictionary (keys and default values)

All fields stored as an `AutomatorActionInfo` struct.

### Search

Case-insensitive substring matching across name, keywords, category, and description. Optional UTI filter on input types. Returns up to 5 results by default.

## Tool Specifications

### 1. SearchAutomatorActionsTool

- **Badge:** gray, `gear.badge`, "Automator"
- **macOS-only:** `#if os(macOS)`

**Arguments:**
- `searchQuery: String` — keywords to match
- `inputType: String?` — optional UTI filter (e.g., `public.image`)
- `maxResults: Int?` — defaults to 5

**Behavior:**
1. Triggers lazy index build on first call
2. Matches query against indexed fields
3. If `inputType` provided, filters to actions whose `AMAccepts.Types` includes it
4. Returns formatted string with action details

**Output format:**
```
Automator actions matching "{query}":

1. {Name} ({Category})
   Description: {summary}
   Accepts: {input UTIs} ({container})
   Provides: {output UTIs} ({container})
   Parameters: {key=defaultValue, ...}
   Bundle: {/System/Library/Automator/Name.action}

2. ...
```

### 2. BuildAutomatorWorkflowTool

- **Badge:** gray, `gear.badge`, "Automator"
- **macOS-only:** `#if os(macOS)`

**Arguments:**
- `workflowTitle: String` — descriptive name for the workflow
- `steps: [WorkflowStep]` — ordered array, each with:
  - `actionBundlePath: String` — path to the `.action` bundle
  - `parameters: [String: String]?` — parameter overrides as string values. The tool coerces each value to match the type of the corresponding key in `AMDefaultParameters`: strings pass through, numeric strings become `NSNumber`, "true"/"false" become booleans. Unknown keys are set as strings.

**Behavior:**
1. Creates `AMWorkflow()`
2. For each step:
   - Loads action via `AMAction(contentsOfURL:error:)`
   - Casts to `AMBundleAction`, merges parameters into `parameters` dictionary
   - Adds to workflow via `workflow.addAction(action)`
3. Writes to temp directory via `workflow.writeToURL(_:error:)`
4. Registers workflow preview metadata for the UI
5. Returns formatted description

**Output format:**
```
Workflow: "{title}"

Steps:
1. {Action Name} ({key parameters}) → [{output type}]
2. {Action Name} ({key parameters}) → [{output type}]
3. ...

Workflow ready. Use the Save button to export as a .workflow file.
```

## UI: Workflow Preview Card

### WorkflowPreview

Stored on `Message` alongside existing `toolsUsed` and `sources` fields:

```swift
struct WorkflowPreview: Codable, Hashable {
    let title: String
    let steps: [WorkflowStepPreview]
    let tempFileURL: URL
}

struct WorkflowStepPreview: Codable, Hashable {
    let actionName: String
    let parameterSummary: String
    let outputType: String
}
```

### Card Rendering

Within `MessageBubbleView`, when a message has a non-nil `workflowPreview`:
- Rounded card with subtle border, visually distinct from message text
- Workflow title as header
- Numbered step list, each showing action name and key parameters
- Arrow/chevron between steps with data type label (e.g., "Images →")
- Bottom bar with **Save** and **Regenerate** buttons

### Save Flow

1. User taps Save
2. `NSSavePanel` opens with suggested filename `{title}.workflow`
3. On approval, app copies from `tempFileURL` to user-chosen location
4. Card updates with confirmation ("Saved to {path}")

### Stale File Handling

`tempFileURL` becomes invalid after app restart. Save button is disabled if file no longer exists. The card still renders the step list for reference.

### Regenerate

Same as existing message regenerate — removes the response, compacts session, re-sends the user prompt.

## Session Registration

In `ChatDetailView.init`, Automator tools are conditionally registered:

```swift
#if os(macOS)
tools.append(contentsOf: [
    SearchAutomatorActionsTool(tracker: tracker),
    BuildAutomatorWorkflowTool(tracker: tracker),
])
#endif
```

Tool descriptions are rich enough for the framework's automatic `includesSchemaInInstructions` injection. No manual system instruction additions needed.

## Entitlements

Upgrade one existing entitlement:
- `com.apple.security.files.user-selected.read-only` → `com.apple.security.files.user-selected.read-write`

No other entitlement changes. No Apple Events entitlement needed — Conductor builds workflows but never executes them or controls other apps.

## File Structure

```
Conductor/
  Tools/
    Automator/
      AutomatorActionIndex.swift         (actor: lazy scan, index, search)
      AutomatorActionInfo.swift          (struct: action metadata)
      SearchAutomatorActionsTool.swift   (FoundationModels Tool)
      BuildAutomatorWorkflowTool.swift   (FoundationModels Tool)
      WorkflowPreview.swift              (struct: UI preview model)
  ContentView.swift                      (extend MessageBubbleView for workflow cards)
```

## Error Handling

All tools catch errors internally and return descriptive strings:
- Index scan failure: "Could not scan Automator actions. Automator may not be available on this system."
- Action load failure: "Could not load action '{name}'. Skipping this step." (build continues with remaining steps)
- No search results: "No Automator actions found matching '{query}'. Try different keywords."
- Workflow write failure: "Could not save workflow to temporary location."
- Save panel / file copy failure: handled in UI with an alert

## Testing

- **AutomatorActionIndex tests:** Parse mock `Info.plist` dictionaries, verify field extraction
- **Search tests:** Matching logic with keyword, category, and UTI filters
- **WorkflowPreview tests:** Codable round-trip, step serialization
- **Integration:** Cannot easily unit test `AMWorkflow` assembly (requires framework at runtime), but all logic up to that boundary is testable

## Platform

- macOS 14+ (Automator.framework availability)
- macOS 26+ (FoundationModels requirement)
- Effective minimum: macOS 26
- All Automator code behind `#if os(macOS)`
- iOS/iPadOS: tools do not register, card type never appears

## Privacy

The search tool reads bundle metadata from `/System/Library/Automator/` — no user data accessed. The build tool writes to the app's sandbox temp directory. The user explicitly chooses where to save via `NSSavePanel`. No network requests.
