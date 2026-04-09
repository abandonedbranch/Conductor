# WebReaderTool Design

## Overview

A fourth gateway tool that loads a user-provided HTTPS URL, extracts the page's text content via WebKit, and returns it to the chat context for Conductor to analyze.

Conductor is not a web browser. The WebReaderTool is a research assistant — it fetches and extracts text so the user can work with it conversationally. No interactive browsing, no SPA navigation, no lazy-load workarounds.

## Motivation

Conductor's existing tools search structured APIs (PubMed, Wikipedia, arXiv, etc.) and build Automator workflows. Users also need to pull text from arbitrary web pages — articles, documentation, blog posts — into their research context. The WebReaderTool fills this gap using only Apple SDKs.

## Architecture

### Gateway Position

The three-tool gateway becomes a four-tool gateway:

| Tool | Purpose |
|------|---------|
| LibraryTool | Search knowledge backends |
| ManualTool | Static documentation pages |
| ActionTool | Execute capabilities |
| **WebReaderTool** | **Extract text from web pages** |

### Components

Five new files following View → Model → Service:

| File | Type | Role |
|------|------|------|
| `Conductor/Tools/WebReaderTool.swift` | Tool | Gateway entry point. Receives URL, delegates to service, returns extracted text. |
| `Conductor/Services/WebReaderService.swift` | Actor | Owns extraction logic. Validates URL, triggers load, runs JS extraction, cleans up text. |
| `Conductor/Models/WebReaderState.swift` | @Observable | Bridges service and view. Tracks per-read state: loading, success, error. |
| `Conductor/Models/WebReaderError.swift` | Enum | Structured Swift errors with context for Conductor to interpret. |
| `Conductor/Views/WebReaderHost.swift` | View | `UIViewRepresentable`/`NSViewRepresentable` wrapping `WKWebView`. Renders the status card in chat. |

### Data Flow

1. User provides a URL in chat.
2. `WebReaderTool` validates the URL scheme (HTTPS only) and calls `WebReaderService.read(url)`.
3. Service creates a `WebReaderState` and sets it to `.loading(url)`.
4. `WebReaderHost` mounts a `WKWebView` in the view hierarchy (not user-visible) and begins navigation.
5. On `didFinish` navigation, the service runs the fixed extraction script via `evaluateJavaScript`.
6. Service updates state to `.success(title, text)` or `.error(...)`.
7. The `WKWebView` is torn down. The status card remains in chat history.
8. Extracted text is returned to chat context.

## Text Extraction

### JavaScript Strategy

All JavaScript is predefined and static. The model never generates or modifies scripts at runtime.

**Extraction script:**

```javascript
(() => {
  const title = document.title || '';
  const text = document.body.innerText || '';
  return JSON.stringify({ title, text });
})()
```

This runs once after `WKNavigationDelegate.didFinish`. `innerText` handles:

- Stripping HTML tags
- Respecting `display: none` / `visibility: hidden`
- Preserving basic text structure (newlines from block elements)

### Deliberately Out of Scope

- **Lazy-loaded content** — No scroll-to-load. Extracts what renders on initial load.
- **SPA client-side rendering** — No wait-for-render heuristics. If the page hasn't rendered by `didFinish`, the tool extracts whatever is there.
- **Interactive content** — No clicking tabs, expanding accordions, or dismissing modals.
- **Vision OCR** — No image-to-text extraction. Future iteration if needed.
- **Generated JavaScript** — No dynamic script creation. All JS is compiled into the binary.

These limitations are intentional. A fully automated browser system is a different tool. Subagents that physically interact with pages may address these cases in the future.

## Error Handling

### Error Enum

```swift
enum WebReaderError: Error {
    case invalidURL(String)
    case insecureURL(URL)
    case navigationFailed(URLError.Code)
    case timeout(TimeInterval)
    case emptyContent(URL)
    case extractionFailed(URL)
}
```

### Error Contract

Tools throw structured Swift errors. Conductor reads the error and decides how to respond to the user. No hardcoded user-facing strings in the tool layer.

Pattern: `Tool execution → Error thrown → Conductor reads error → Conductor acts on error`

This pattern enables increasingly sophisticated error recovery logic in the future without changing the tool interface.

### Error Cases

| Case | Trigger | Context Provided |
|------|---------|-----------------|
| `invalidURL` | Malformed or unparseable URL string | The original string |
| `insecureURL` | HTTP scheme (not HTTPS) | The parsed URL |
| `navigationFailed` | DNS, SSL, connection errors | The `URLError.Code` |
| `timeout` | Page didn't finish loading within 30 seconds | The timeout duration |
| `emptyContent` | `innerText` returned empty/whitespace | The URL that loaded |
| `extractionFailed` | JS evaluation threw or returned nil | The URL that loaded |

## UX

### Status Card

Every web read produces a card in the chat history. The card is permanent — it does not dismiss after loading completes.

**States:**

- **Loading** — Shows URL, animated indicator. Signals that work is being done.
- **Success** — Shows page title and URL. The extracted text flows into context.
- **Error** — Shows error state. User can click regen to retry.

The card persists in chat scrollback as an informative piece of history. This allows the user to see what was loaded, retry on error, and reference past reads.

### Visual Feedback Rule

Per project convention: every user-initiated action provides subtle visual feedback indicating state. The status card satisfies this for web reads.

## Platform

### Targets

iOS 17+, iPadOS 17+, macOS 14+. WebKit's `WKWebView` is available on all three.

### Platform-Specific Code

Only `WebReaderHost` requires platform guards:

- **iOS/iPadOS** — `UIViewRepresentable` wrapping `WKWebView`
- **macOS** — `NSViewRepresentable` wrapping `WKWebView`

Service, model, error, and tool are fully shared across platforms.

### Security

HTTPS only. HTTP URLs are rejected with `WebReaderError.insecureURL`. No `NSAppTransportSecurity` exceptions in Info.plist.

## Constraints

- Apple SDKs only — WebKit for page loading, Foundation for networking types. No third-party packages.
- All JavaScript is static and deterministic — compiled into the binary, never generated at runtime.
- No retry logic — fail with a descriptive error and let Conductor decide.
- Swift 6 strict concurrency — the service is an actor, the model is `@Observable`, all async work uses structured concurrency.
