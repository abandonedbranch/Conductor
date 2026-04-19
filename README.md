# Conductor

Conductor is a natural-language workflow creator. You type prose — "Summarize
https://example.com/article" or "Find papers on sickle-cell disease and
summarize them" — and Conductor compiles that prose into an ordered pipeline
of typed verbs, runs each one, and shows exactly what happened at every step.

It is not a chatbot. It does not reply in prose. It does not make silent
decisions. Every step is a structured, inspectable operation with visible
inputs, outputs, and provenance.

## How It Works

Conductor compiles prose through a four-layer stack, consulting the LLM last
and only when the deterministic layers cannot finish the job:

1. **NSDataDetector** — extracts URLs, dates, numbers, and other structured
   atoms from the input. Deterministic, on-device, microsecond-scale.
2. **NLTagger** — matches verbs by lemma and parameter aliases. No ML.
3. **NLEmbedding** — fuzzy-matches unrecognized verb words by semantic
   similarity to the verb catalog. Deterministic, on-device.
4. **Foundation Models** — last-resort verb classification, invoked only when
   layers 1–3 leave gaps. Its output is a narrow `@Generable` enum, never
   free-form prose.

Over the built-in prose corpus, ~70% of inputs compile without reaching
layer 4.

The compiled pipeline runs under an event-sourced runtime. Each verb
(`read`, `summarize`, `search`, `extractClaims`) emits typed events into an
append-only log. Downstream verbs consume upstream events through an explicit
"needs" declaration rather than shared state, and the SwiftUI views are
projections over the log. When a required input is missing, Conductor asks
the user through a typed prompt (URL, number, date, text, choice) — it never
guesses silently.

## LLM Usage

Every on-device LLM call is stateless typed inference. A fresh
`LanguageModelSession` is constructed per call and destroyed on return. No
call relies on another call's session context. The LLM's output is a
`@Generable` value — a typed grammar, not prose.

Natural language is a user interface, not a dialogue partner. The LLM
translates human language into structured values the rest of the system can
act on. Results cross session boundaries only through the working memory
graph.

## What Conductor Is Not

- **Not an assistant.** Siri exists; Conductor is a different shape.
- **Not a developer tool.** That is Xcode's domain.
- **Not a general-purpose automation layer.** That is Automator's territory.
- **Not an agentic chatbot.** The LLM is one narrow translator inside a
  larger deterministic system, not the brain.

## Values

Conductor is built on three non-negotiable commitments:

### Open Source

The entire codebase is public. Every design decision, every trade-off, every
line of code is visible and auditable. The project is licensed under GPLv3 —
you are free to fork, modify, and create derivative works. That freedom is
the point.

### Transparency

Users deserve to know exactly what the software does on their behalf.
Conductor surfaces the compiled pipeline, the status of every verb, and the
origin of every atom. It does not perform hidden actions, make undisclosed
network calls, or obscure its decision-making.

### Privacy

User data belongs to users. Conductor processes intent locally wherever
possible. It does not collect telemetry, phone home, or share data with third
parties. When network access is required, the user is informed and in
control. No silent tracking. No analytics. No exceptions.

These three values are not features — they are constraints. Every design
decision must satisfy all three. Code that violates any of them does not
ship.

## Design Principles

- **Clarity over cleverness.** Direct language. No marketing speak.
- **Deterministic first, LLM last.** The smallest possible question, the
  narrowest possible grammar.
- **Typed outputs.** Every LLM output is `@Generable`. No prose-shaped
  returns.
- **Systems thinking.** Coordination and flow, not a single input-output
  mechanism.
- **Technical honesty.** Acknowledge limits. Don't oversell capabilities.

## Building

Open `Conductor.xcodeproj` in Xcode. The app targets iOS 26+, iPadOS 26+, and
macOS 26+ (the Foundation Models framework pins the minimum). Select a
destination and run the `Conductor` scheme.

Tests use the Swift Testing framework. Run them from Xcode or via
`xcodebuild test -scheme Conductor -destination 'platform=macOS'`.

See [CLAUDE.md](CLAUDE.md) for coding conventions and
[CONTRIBUTORS](CONTRIBUTORS) for contribution guidelines.
