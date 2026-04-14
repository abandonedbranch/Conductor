import Foundation
import Testing
@testable import Conductor

@Suite("Vocabulary")
struct VocabularyTests {
    @Test("IntentVerb covers the seed set")
    func intentVerbCases() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let raws = IntentVerb.allCases.map(\.rawValue).sorted()
        #expect(raws == ["build", "find", "read", "recall", "summarize"])
    }

    @Test("IntentSubject covers the seed set")
    func intentSubjectCases() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let raws = Set(IntentSubject.allCases.map(\.rawValue))
        #expect(raws == ["academic", "biomedical", "preprint", "encyclopedic", "webpage", "workflow", "conversational"])
    }

    @Test("AnswerShape covers the seed set")
    func answerShapeCases() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let raws = Set(AnswerShape.allCases.map(\.rawValue))
        #expect(raws == ["overview", "summary", "citations", "workflow", "direct"])
    }
}
