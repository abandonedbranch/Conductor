import Foundation
import Testing
@testable import Conductor

@Suite("LanguageIntentQuery")
struct LanguageIntentQueryTests {
    @Test("Round-trips through JSONEncoder/Decoder")
    func codable() throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let original = LanguageIntentQuery(
            verbs: [.find, .summarize],
            subjects: ["CRISPR"],
            answerShape: .overview,
            continuation: .extends
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LanguageIntentQuery.self, from: data)
        #expect(decoded.verbs == [.find, .summarize])
        #expect(decoded.subjects == ["CRISPR"])
        #expect(decoded.answerShape == .overview)
        #expect(decoded.continuation == .extends)
    }

    @Test("Continuation accepts all four cases")
    func continuationCases() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let cases: [LanguageIntentQuery.Continuation] = [.refines, .extends, .pivots, .recalls]
        #expect(cases.count == 4)
    }
}
