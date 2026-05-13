import Foundation
import Observation

/// Bridge from the Runtime to an interactive ask surface. Implementations
/// (`AppAskResolver` in production, fakes in tests) present the user with an
/// `AskView` for `kind` and return the resolved `AtomValue`, or `nil` if the
/// user dismissed. The Runtime records the answer as an `AtomRecorded`
/// event with source `.userAsked`, so later steps see it in the log.
protocol AskResolver: Sendable {
    func ask(role: String, kind: AtomKind) async -> AtomValue?
}

/// Executes a compiled pipeline one `Step` at a time.
///
/// Runtime does three non-obvious things:
///
///   1. **Resolves parameters per-step**, in this precedence order:
///      log lookup (latest `AtomRecorded` matching the role) → declared
///      default → user ask via `AskResolver`. If the user declines a
///      required ask, the step emits `StepFailed` and returns, rather
///      than propagating an exception — missing input is a normal
///      failure mode, not a programming error.
///
///   2. **Fans out over collection upstream events.** When a step's needs
///      reference a `SearchResults` with more than one paper, the runtime
///      loops the step once per paper, tagging each iteration in its
///      `Origin.iteration`. This is how "search for papers, then summarize
///      them" yields one `SummaryProduced` per paper.
///
///   3. **Attributes verb-execute failures to the active step.** Earlier
///      revisions let execute-time errors bubble up to `AppModel`, which
///      logged `StepFailed` with a random UUID that no step matched — the
///      UI rendered the failing step as idle instead of failed. The
///      `do/catch` around `def.execute` inside `runOneIteration` now emits
///      `StepFailed(stepID: step.id, ...)` and re-throws to halt downstream
///      steps that depend on the failed producer.
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
        do {
            let emitted = try await def.execute(resolved: inputs, origin: origin, http: http, llm: llm)
            log.append(emitted)
        } catch {
            log.append(StepFailed(stepID: step.id, message: "\(error)", origin: origin))
            throw error
        }
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
