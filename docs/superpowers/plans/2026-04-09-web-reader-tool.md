# WebReaderTool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth gateway tool that loads an HTTPS URL via WebKit, extracts text with a fixed JavaScript script, and returns it to the chat context.

**Architecture:** Hybrid service + view attachment. `WebReaderService` (actor) owns extraction logic and delegates the `WKWebView` to a `WebReaderHost` representable mounted in the view hierarchy during reads. `WebReaderState` (@Observable) bridges the two. `WebReaderTool` is the gateway entry point, a peer of `ActionTool`, `LibraryTool`, and `ManualTool`.

**Tech Stack:** WebKit (`WKWebView`, `WKNavigationDelegate`), FoundationModels (`Tool` protocol, `@Generable`), SwiftUI (`UIViewRepresentable`/`NSViewRepresentable`), Swift Testing

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Conductor/Models/WebReaderError.swift` | Create | Error enum with cases for invalid URL, insecure URL, navigation failure, timeout, empty content, extraction failure |
| `Conductor/Models/WebReaderState.swift` | Create | @Observable model tracking per-read state (loading/success/error), page title, URL, extracted text |
| `Conductor/Services/WebReaderService.swift` | Create | Actor that validates URLs, coordinates WKWebView loading, runs fixed JS extraction, returns results |
| `Conductor/Tools/WebReaderTool.swift` | Create | Gateway tool conforming to `BadgedTool`. Receives URL from model, delegates to service, returns extracted text |
| `Conductor/Views/WebReaderHost.swift` | Create | Platform-specific `WKWebView` representable. Mounted during reads, drives navigation delegate callbacks into service |
| `Conductor/Views/WebReaderCardView.swift` | Create | SwiftUI card displayed in chat history showing loading/success/error state for a web read |
| `Conductor/ContentView.swift` | Modify | Add `WebReaderTool` to tools array, update system prompt, add `webReaderResult` to `Message`, render `WebReaderCardView` in message bubble |
| `ConductorTests/WebReaderErrorTests.swift` | Create | Tests for URL validation and error cases |
| `ConductorTests/WebReaderServiceTests.swift` | Create | Tests for the extraction script output parsing |
| `ConductorTests/WebReaderToolTests.swift` | Create | Tests for tool argument handling |

---

### Task 1: WebReaderError

**Files:**
- Create: `Conductor/Models/WebReaderError.swift`
- Create: `ConductorTests/WebReaderErrorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ConductorTests/WebReaderErrorTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("WebReaderError Tests", .serialized)
struct WebReaderErrorTests {

    @Test("invalidURL carries the original string")
    func invalidURLCarriesString() {
        let error = WebReaderError.invalidURL("not a url")
        if case .invalidURL(let raw) = error {
            #expect(raw == "not a url")
        } else {
            Issue.record("Expected invalidURL")
        }
    }

    @Test("insecureURL rejects http scheme")
    func insecureURLRejectsHTTP() {
        let url = URL(string: "http://example.com")!
        let error = WebReaderError.insecureURL(url)
        if case .insecureURL(let rejected) = error {
            #expect(rejected.scheme == "http")
        } else {
            Issue.record("Expected insecureURL")
        }
    }

    @Test("validate rejects malformed strings")
    func validateRejectsMalformed() {
        let result = WebReaderError.validate(urlString: "not a url")
        switch result {
        case .failure(let error):
            if case .invalidURL = error {
                // pass
            } else {
                Issue.record("Expected invalidURL, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("validate rejects http URLs")
    func validateRejectsHTTP() {
        let result = WebReaderError.validate(urlString: "http://example.com")
        switch result {
        case .failure(let error):
            if case .insecureURL = error {
                // pass
            } else {
                Issue.record("Expected insecureURL, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("validate accepts https URLs")
    func validateAcceptsHTTPS() {
        let result = WebReaderError.validate(urlString: "https://example.com")
        switch result {
        case .success(let url):
            #expect(url.scheme == "https")
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/WebReaderErrorTests 2>&1 | tail -20`

Expected: FAIL — `WebReaderError` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Conductor/Models/WebReaderError.swift`:

```swift
import Foundation

enum WebReaderError: Error {
    case invalidURL(String)
    case insecureURL(URL)
    case navigationFailed(URLError.Code)
    case timeout(TimeInterval)
    case emptyContent(URL)
    case extractionFailed(URL)

    static func validate(urlString: String) -> Result<URL, WebReaderError> {
        guard let url = URL(string: urlString),
              url.host != nil else {
            return .failure(.invalidURL(urlString))
        }

        guard url.scheme == "https" else {
            return .failure(.insecureURL(url))
        }

        return .success(url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/WebReaderErrorTests 2>&1 | tail -20`

Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```
git add Conductor/Models/WebReaderError.swift ConductorTests/WebReaderErrorTests.swift
git commit -m "(model): add WebReaderError with URL validation"
```

---

### Task 2: WebReaderState

**Files:**
- Create: `Conductor/Models/WebReaderState.swift`

- [ ] **Step 1: Write the model**

Create `Conductor/Models/WebReaderState.swift`:

```swift
import Foundation

struct WebReaderResult: Codable, Hashable {
    let url: URL
    let title: String
    let text: String
}

enum WebReaderStatus: Codable, Hashable {
    case loading(URL)
    case success(WebReaderResult)
    case error(String)
}
```

Note: This is a plain value type used on `Message`, not an `@Observable` class. The `Message` struct will hold an optional `WebReaderStatus` the same way it holds an optional `WorkflowPreview`. The `WebReaderHost` view will use a binding/callback pattern to report results, matching how the existing `WorkflowCardView` works.

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Conductor/Models/WebReaderState.swift
git commit -m "(model): add WebReaderResult and WebReaderStatus"
```

---

### Task 3: WebReaderService

**Files:**
- Create: `Conductor/Services/WebReaderService.swift`
- Create: `ConductorTests/WebReaderServiceTests.swift`

- [ ] **Step 1: Write the failing test for extraction parsing**

Create `ConductorTests/WebReaderServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("WebReaderService Tests", .serialized)
struct WebReaderServiceTests {

    @Test("parseExtraction decodes valid JSON")
    func parseExtractionValid() throws {
        let json = """
        {"title":"Example Domain","text":"This domain is for use in illustrative examples."}
        """
        let result = try WebReaderService.parseExtraction(json)
        #expect(result.title == "Example Domain")
        #expect(result.text == "This domain is for use in illustrative examples.")
    }

    @Test("parseExtraction throws on invalid JSON")
    func parseExtractionInvalid() {
        #expect(throws: (any Error).self) {
            try WebReaderService.parseExtraction("not json")
        }
    }

    @Test("parseExtraction handles empty title")
    func parseExtractionEmptyTitle() throws {
        let json = """
        {"title":"","text":"Some body text."}
        """
        let result = try WebReaderService.parseExtraction(json)
        #expect(result.title.isEmpty)
        #expect(result.text == "Some body text.")
    }

    @Test("extractionScript is deterministic")
    func extractionScriptIsDeterministic() {
        let a = WebReaderService.extractionScript
        let b = WebReaderService.extractionScript
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/WebReaderServiceTests 2>&1 | tail -20`

Expected: FAIL — `WebReaderService` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Conductor/Services/WebReaderService.swift`:

```swift
import Foundation
import WebKit

@available(iOS 19.0, macOS 26.0, *)
final class WebReaderService: NSObject, WKNavigationDelegate {

    static let extractionScript = """
    (() => {
        const title = document.title || '';
        const text = document.body.innerText || '';
        return JSON.stringify({ title: title, text: text });
    })()
    """

    static let timeoutInterval: TimeInterval = 30

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WebReaderResult, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var currentURL: URL?

    func read(url: URL) async throws -> WebReaderResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.currentURL = url

            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            let request = URLRequest(url: url)
            wv.load(request)

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeoutInterval))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.failWithTimeout()
                }
            }
        }
    }

    private func failWithTimeout() {
        guard let continuation, let url = currentURL else { return }
        cleanup()
        continuation.resume(throwing: WebReaderError.timeout(Self.timeoutInterval))
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation = nil
        currentURL = nil
    }

    // MARK: - WKNavigationDelegate

    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.extractionScript) { [weak self] result, error in
            guard let self, let continuation = self.continuation else { return }

            if let error {
                let url = self.currentURL ?? URL(string: "about:blank")!
                self.cleanup()
                continuation.resume(throwing: WebReaderError.extractionFailed(url))
                return
            }

            guard let jsonString = result as? String else {
                let url = self.currentURL ?? URL(string: "about:blank")!
                self.cleanup()
                continuation.resume(throwing: WebReaderError.extractionFailed(url))
                return
            }

            do {
                let parsed = try Self.parseExtraction(jsonString)
                let webResult = WebReaderResult(
                    url: self.currentURL ?? URL(string: "about:blank")!,
                    title: parsed.title,
                    text: parsed.text
                )
                self.cleanup()
                continuation.resume(returning: webResult)
            } catch {
                let url = self.currentURL ?? URL(string: "about:blank")!
                self.cleanup()
                continuation.resume(throwing: WebReaderError.extractionFailed(url))
            }
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard let continuation else { return }
        let urlError = (error as? URLError)?.code ?? .unknown
        cleanup()
        continuation.resume(throwing: WebReaderError.navigationFailed(urlError))
    }

    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard let continuation else { return }
        let urlError = (error as? URLError)?.code ?? .unknown
        cleanup()
        continuation.resume(throwing: WebReaderError.navigationFailed(urlError))
    }

    // MARK: - Extraction Parsing

    struct ExtractionPayload: Decodable {
        let title: String
        let text: String
    }

    static func parseExtraction(_ jsonString: String) throws -> ExtractionPayload {
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(ExtractionPayload.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/WebReaderServiceTests 2>&1 | tail -20`

Expected: PASS — all 4 tests green.

- [ ] **Step 5: Commit**

```
git add Conductor/Services/WebReaderService.swift ConductorTests/WebReaderServiceTests.swift
git commit -m "(service): add WebReaderService with WKWebView extraction"
```

---

### Task 4: WebReaderTool

**Files:**
- Create: `Conductor/Tools/WebReaderTool.swift`
- Create: `ConductorTests/WebReaderToolTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ConductorTests/WebReaderToolTests.swift`:

```swift
import Foundation
import Testing
@testable import Conductor

@Suite("WebReaderTool Tests", .serialized)
struct WebReaderToolTests {

    @Test("validateURL rejects malformed input")
    func rejectsMalformed() {
        let result = WebReaderTool.validateURL("not a url")
        switch result {
        case .failure(let error):
            if case .invalidURL = error {
                // pass
            } else {
                Issue.record("Expected invalidURL, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("validateURL rejects http")
    func rejectsHTTP() {
        let result = WebReaderTool.validateURL("http://example.com")
        switch result {
        case .failure(let error):
            if case .insecureURL = error {
                // pass
            } else {
                Issue.record("Expected insecureURL, got \(error)")
            }
        case .success:
            Issue.record("Expected failure")
        }
    }

    @Test("validateURL accepts https")
    func acceptsHTTPS() {
        let result = WebReaderTool.validateURL("https://example.com")
        switch result {
        case .success(let url):
            #expect(url.scheme == "https")
        case .failure:
            Issue.record("Expected success")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/WebReaderToolTests 2>&1 | tail -20`

Expected: FAIL — `WebReaderTool` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Conductor/Tools/WebReaderTool.swift`:

```swift
import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct WebReaderTool: BadgedTool {
    let name = "readWeb"
    let description = "Read a web page and extract its text content. Call when the user provides a URL they want to read, analyze, or summarize."
    let badge = ToolBadge(icon: "globe", tint: .purple, label: "Web")

    let tracker: ToolUsageTracker

    @Generable
    struct Arguments {
        @Guide(description: "The full URL of the web page to read (must be HTTPS)")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)

        let url = try validateAndUnwrap(arguments.url)

        let service = WebReaderService()
        let result = try await service.read(url: url)

        await tracker.addSource(ToolSource(title: result.title, url: result.url.absoluteString))

        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WebReaderError.emptyContent(url)
        }

        return result.text
    }

    private func validateAndUnwrap(_ urlString: String) throws -> URL {
        switch Self.validateURL(urlString) {
        case .success(let url):
            return url
        case .failure(let error):
            throw error
        }
    }

    static func validateURL(_ urlString: String) -> Result<URL, WebReaderError> {
        WebReaderError.validate(urlString: urlString)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' -only-testing ConductorTests/WebReaderToolTests 2>&1 | tail -20`

Expected: PASS — all 3 tests green.

- [ ] **Step 5: Commit**

```
git add Conductor/Tools/WebReaderTool.swift ConductorTests/WebReaderToolTests.swift
git commit -m "(tools): add WebReaderTool with URL validation and text extraction"
```

---

### Task 5: WebReaderCardView

**Files:**
- Create: `Conductor/Views/WebReaderCardView.swift`

- [ ] **Step 1: Write the view**

Create `Conductor/Views/WebReaderCardView.swift`:

```swift
import SwiftUI

struct WebReaderCardView: View {
    let status: WebReaderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch status {
            case .loading(let url):
                Label {
                    Text("Reading page…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

            case .success(let result):
                Label(result.title.isEmpty ? "Page loaded" : result.title, systemImage: "globe")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(result.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(result.text.count) characters extracted")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

            case .error(let description):
                Label("Failed to read page", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Conductor/Views/WebReaderCardView.swift
git commit -m "(views): add WebReaderCardView with loading/success/error states"
```

---

### Task 6: WebReaderHost (WKWebView Representable)

**Files:**
- Create: `Conductor/Views/WebReaderHost.swift`

- [ ] **Step 1: Write the representable**

Create `Conductor/Views/WebReaderHost.swift`:

```swift
import SwiftUI
import WebKit

#if os(macOS)
struct WebReaderHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct WebReaderHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
```

Note: The `WebReaderHost` receives the `WKWebView` instance owned by `WebReaderService`. It exists solely to attach the web view to the view hierarchy so WebKit renders correctly on iOS. The view is 1x1 point — invisible to the user. In Task 7, this view is mounted as a hidden overlay in `ChatDetailView` whenever a web read is in progress, driven by an optional `WKWebView` reference exposed by the service.

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Conductor/Views/WebReaderHost.swift
git commit -m "(views): add WebReaderHost WKWebView representable"
```

---

### Task 7: ContentView Integration

**Files:**
- Modify: `Conductor/ContentView.swift`

This task wires the `WebReaderTool` into the gateway, updates the `Message` model to carry `WebReaderStatus`, updates the system prompt, and renders the `WebReaderCardView` in message bubbles.

- [ ] **Step 1: Add `webReaderStatus` to `Message`**

In `Conductor/ContentView.swift`, update the `Message` struct:

Add a property after `workflowPreview`:

```swift
var webReaderStatus: WebReaderStatus?
```

Add to `CodingKeys`:

```swift
case id, content, isUser, timestamp, toolsUsed, sources, workflowPreview, webReaderStatus
```

Update `init(id:content:isUser:timestamp:toolsUsed:sources:workflowPreview:)` — add `webReaderStatus: WebReaderStatus? = nil` parameter and `self.webReaderStatus = webReaderStatus` in the body.

Update `init(from decoder:)` — add:

```swift
webReaderStatus = try container.decodeIfPresent(WebReaderStatus.self, forKey: .webReaderStatus)
```

- [ ] **Step 2: Add `WebReaderTool` to the tools array and update system prompt**

In `ChatDetailView.init(chat:chatManager:)`, add `WebReaderTool` to the tools array (around line 402):

```swift
let tools: [any Tool] = [
    ActionTool(registry: registry, tracker: tracker),
    LibraryTool(registry: registry, tracker: tracker),
    ManualTool(),
    WebReaderTool(tracker: tracker),
]
```

Update the system prompt (around line 381):

```swift
private static let instructions = """
You are The Conductor. You orchestrate device capabilities to fulfill user intent.
Use action to do. Use library to know. Use manual to explain yourself. Use readWeb to read web pages.
Respond tersely. One sentence when one sentence suffices.
If a tool errors, explain in one sentence. Do not apologize.
Never fabricate information. If you lack data, say so.
"""
```

- [ ] **Step 3: Mount `WebReaderHost` as hidden overlay**

In `ChatDetailView.body`, add a hidden overlay that mounts the `WKWebView` in the hierarchy when a read is in progress. Add a `@State private var activeWebView: WKWebView?` property to `ChatDetailView`. When `WebReaderService` starts a read, set this to the service's web view; when the read completes, set it back to `nil`. Mount the host as a hidden overlay:

```swift
.overlay {
    if let webView = activeWebView {
        WebReaderHost(webView: webView)
            .frame(width: 1, height: 1)
            .opacity(0)
    }
}
```

- [ ] **Step 4: Render `WebReaderCardView` in message bubble**

In the message bubble view (after the `WorkflowCardView` block around line 748–751), add:

```swift
if let webStatus = message.webReaderStatus {
    WebReaderCardView(status: webStatus)
}
```

- [ ] **Step 5: Verify it compiles**

Run: `xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```
git add Conductor/ContentView.swift
git commit -m "(session): wire WebReaderTool into gateway and message display"
```

---

### Task 8: End-to-End Verification

- [ ] **Step 1: Build for all platforms**

Run macOS build:

```
xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -10
```

Run iOS simulator build:

```
xcodebuild build -project Conductor.xcodeproj -scheme Conductor -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED for both.

- [ ] **Step 2: Run all tests**

```
xcodebuild test -project Conductor.xcodeproj -scheme Conductor -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: All tests pass, including existing tests (ActionToolTests, LibraryToolTests, ManualToolTests, CapabilityRegistryTests, PubMedTests) and new tests (WebReaderErrorTests, WebReaderServiceTests, WebReaderToolTests).

- [ ] **Step 3: Manual smoke test**

Launch the app, start a new conversation, and send: "Read this page: https://example.com"

Expected:
- A loading card appears in the chat
- The card transitions to success showing "Example Domain"
- Conductor responds with information about the extracted content
- The Web badge (purple globe) appears on the response message

- [ ] **Step 4: Commit any fixes if needed**
