import Testing
@testable import Conductor

@available(iOS 19.0, macOS 26.0, *)
private func makeDesc(
    _ name: String,
    verbs: Set<IntentVerb>,
    subjects: Set<IntentSubject>,
    shapes: Set<AnswerShape>,
    priority: Int = 0
) -> AffordanceDescriptor {
    AffordanceDescriptor(
        name: name,
        affordance: .init(verbs: verbs, subjects: subjects, answerShapes: shapes, priority: priority)
    )
}

@Suite("deterministicSearch")
struct DeterministicSearchTests {
    @Test("Filters out tools that don't share any verb")
    func verbFilter() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .citations, continuation: nil)
        let pool = [
            makeDesc("A", verbs: [.find], subjects: [.academic], shapes: [.citations]),
            makeDesc("B", verbs: [.build], subjects: [.academic], shapes: [.citations]),
        ]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.map(\.name) == ["A"])
    }

    @Test("Filters out tools that don't contain the requested answerShape")
    func shapeFilter() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .workflow, continuation: nil)
        let pool = [
            makeDesc("Wiki", verbs: [.find], subjects: [.academic], shapes: [.overview]),
            makeDesc("Auto", verbs: [.find], subjects: [.academic], shapes: [.workflow]),
        ]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.map(\.name) == ["Auto"])
    }

    @Test("Ranks by priority descending when tools tie on matches")
    func priorityOrder() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["CRISPR"], answerShape: .citations, continuation: nil)
        let pool = [
            makeDesc("Low", verbs: [.find], subjects: [.academic], shapes: [.citations], priority: 1),
            makeDesc("High", verbs: [.find], subjects: [.academic], shapes: [.citations], priority: 9),
        ]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.map(\.name) == ["High", "Low"])
    }

    @Test("Truncates to cap")
    func cap() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(verbs: [.find], subjects: [], answerShape: .citations, continuation: nil)
        let pool = (0..<10).map {
            makeDesc("T\($0)", verbs: [.find], subjects: [.academic], shapes: [.citations], priority: $0)
        }
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 3)
        #expect(result.count == 3)
    }

    @Test("Empty result when no pool entries match")
    func empty() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(verbs: [.build], subjects: [], answerShape: .workflow, continuation: nil)
        let pool = [makeDesc("X", verbs: [.find], subjects: [.academic], shapes: [.citations])]
        let result = deterministicSearch(intent: intent, intentSubjects: [.academic], pool: pool, cap: 10)
        #expect(result.isEmpty)
    }
}
