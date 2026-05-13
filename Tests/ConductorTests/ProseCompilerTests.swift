import Testing
import Foundation
@testable import Conductor

@Suite struct ProseCompilerTests {
    @Test func compiles_deterministically_whenL1L2Suffice() async throws {
        let llm = FakeLLMSession()
        let result = try await ProseCompiler.compile(
            prose: "Summarize the article at https://example.com and find 3 related PubMed papers",
            llm: llm
        )
        #expect(result.verbs.contains(.summarize))
        #expect(result.verbs.contains(.search))
        #expect(result.usedLLM == false)
        #expect(result.atoms.contains { $0.role == "url" })
        #expect(result.atoms.contains { $0.role == "search.target" })
        #expect(result.atoms.contains { $0.role == "search.limit" })
    }

    @Test func fallsToLLM_whenLayer2FindsNoVerbs() async throws {
        let llm = FakeLLMSession()
        llm.scriptedIntent = PipelineIntent(verbs: [.search])
        let result = try await ProseCompiler.compile(prose: "I've got this thing", llm: llm)
        #expect(result.usedLLM == true)
        #expect(result.verbs == [.search])
    }
}
