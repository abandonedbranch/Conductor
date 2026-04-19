import Foundation
import Observation

struct PendingAsk: Sendable, Equatable, Identifiable {
    let role: String
    let kind: AtomKind
    var id: String { role }
}

@Observable
@MainActor
final class AppModel {
    var prose: String = ""
    var steps: [Step] = []
    var isRunning: Bool = false
    var pendingAsk: PendingAsk?
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
        pendingAsk = PendingAsk(role: role, kind: kind)
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
