# Conductor – Agent Guidelines

## Project

Multiplatform SwiftUI app targeting iOS 17+, iPadOS 17+, and macOS 14+.
Open `Conductor.xcodeproj` to build and run.

## Code Style

- Swift 6 with strict concurrency enabled. All new code must compile cleanly under `SWIFT_STRICT_CONCURRENCY=complete`.
- Use SwiftUI as the sole UI framework. Do not introduce UIKit or AppKit unless there is no SwiftUI equivalent.
- Prefer value types (`struct`, `enum`) over reference types. Use `class` only when identity semantics or reference sharing is required.
- Use Swift's structured concurrency (`async`/`await`, `TaskGroup`, actors) for all asynchronous work. Never use completion handlers or `DispatchQueue` in new code.
- Model state with `@Observable` (Observation framework). Do not use `ObservableObject`/`@Published` — those are legacy Combine patterns.
- Use the Swift Testing framework (`import Testing`, `@Test`, `#expect`) for new unit tests. Do not add XCTest-based unit tests.
- Keep files focused. One primary type per file, named to match (`FooView.swift` contains `struct FooView: View`).
- Omit `self.` unless required for disambiguation.
- Use trailing closure syntax. Omit argument labels when the closure is the only argument.
- Prefer `let` over `var`. Prefer immutable data flow.
- Use `guard` for early exits. Avoid deep nesting.
- Use Swift's type inference — omit explicit types when the compiler can infer them and the result is still readable.

## Architecture

- Follow the pattern: **View → Model → Service**. Views observe models; models call services; services own I/O.
- Mark models and services with appropriate `@Observable` or actor isolation as needed.
- Platform-specific code goes behind `#if os(macOS)` / `#if os(iOS)` guards. Keep shared code the default.
- Put shared SwiftUI views in `Conductor/Views/`, models in `Conductor/Models/`, services in `Conductor/Services/`.

## Git Practices

- Do not include `Co-Authored-By`, `Co-Created-By`, or any AI attribution trailers in commit messages.
- Write commit messages as a short imperative summary (≤ 72 chars) optionally followed by a blank line and a body explaining *why*.
- Keep commits focused — one logical change per commit.
