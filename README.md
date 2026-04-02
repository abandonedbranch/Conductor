# Conductor

Conductor is a user-agent — software that interprets human intent and
coordinates device capabilities to fulfill that intent. It sits between what
users want to accomplish and what their device can do.

Unlike assistants that respond to discrete requests, Conductor orchestrates. It
receives natural language input, understands the underlying goal, and routes
that goal across multiple system functions — launching apps, searching, managing
reminders, filtering information — as needed. The user specifies the outcome;
Conductor determines the path.

## How It Works

Conductor infers workflow from intent. It does not ask users to define explicit
instruction sequences. Foundation models with agentic capabilities close the
gap between human language and system action, making the device responsive to
how people actually think and speak.

## What Conductor Is Not

- **Not an assistant.** Siri exists; Conductor complements it, doesn't replace it.
- **Not a developer tool.** That's Xcode's domain.
- **Not a general-purpose automation layer.** That's Automator's territory.

Conductor is the intelligent intermediary. It assumes you know what you want but
shouldn't need to specify every step.

## Values

Conductor is built on three non-negotiable commitments:

### Open Source

The entire codebase is public. Every design decision, every trade-off, every
line of code is visible and auditable. Contributions are welcome — the project
improves through collective scrutiny, not closed-door development.

### Transparency

Users deserve to know exactly what the software does on their behalf. Conductor
does not perform hidden actions, make undisclosed network calls, or obscure its
decision-making. When it acts, the user can see what it did and why.

### Privacy

User data belongs to users. Conductor processes intent locally wherever
possible. It does not collect telemetry, phone home, or share data with third
parties. When network access is required, the user is informed and in control.
No silent tracking. No analytics. No exceptions.

These three values are not features — they are constraints. Every design
decision must satisfy all three. Code that violates any of them does not ship.

## Design Principles

- **Clarity over cleverness.** Direct language. No marketing speak.
- **Systems thinking.** Coordination and flow, not a single input-output mechanism.
- **Minimal friction.** An extension of the user's thinking, not a tool being operated.
- **Technical honesty.** Acknowledge limits. Don't oversell capabilities.

## Building

Open `Conductor.xcodeproj` in Xcode. The app targets iOS 17+, iPadOS 17+, and
macOS 14+. Select a destination and run.

See [CLAUDE.md](CLAUDE.md) for coding conventions and
[CONTRIBUTORS](CONTRIBUTORS) for contribution guidelines.
