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
