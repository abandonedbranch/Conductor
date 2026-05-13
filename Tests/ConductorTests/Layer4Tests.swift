import Testing
import Foundation
@testable import Conductor

@Suite struct Layer4Tests {
    @Test func callsLLM_onlyWhenNoVerbsKnown() async throws {
        let llm = FakeLLMSession()
        llm.scriptedIntent = PipelineIntent(verbs: [.search])
        let verbs = try await Layer4IntentSession.classify(prose: "I've got this thing", llm: llm)
        #expect(verbs == [.search])
    }
}
