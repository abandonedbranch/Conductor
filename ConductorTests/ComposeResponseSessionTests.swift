import Foundation
import Testing
@testable import Conductor

@Suite("ComposeResponseSession")
struct ComposeResponseSessionTests {
    @available(iOS 19.0, macOS 26.0, *)
    struct Stub: ComposeResponseRunning {
        func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse {
            ComposedResponse(prose: "synthesized: \(intent.subjects.joined(separator: ", "))", sections: nil)
        }
    }

    @Test("Composes prose from intent + RAG projection")
    func composes() async throws {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let session = ComposeResponseSession(runner: Stub())
        let intent = LanguageIntentQuery(verbs: [.summarize], subjects: ["crispr"], answerShape: .summary, continuation: nil)
        let outcome: [Atom] = [.success(content: "edits DNA", source: nil, toolName: "PubMed", timestamp: .now)]
        let response = try await session.compose(intent: intent, outcome: outcome)
        #expect(response.prose.contains("crispr"))
    }

    @Test("RAG projection is bounded by ProjectionBudget")
    func bounded() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let giant = Array(repeating: Atom.success(content: String(repeating: "x", count: 1000), source: nil, toolName: "T", timestamp: .now), count: 20)
        let projection = ComposeResponseSession.ragProjection(from: giant)
        #expect(projection.count <= ProjectionBudget.composeResponseProjection + 100)
    }
}
