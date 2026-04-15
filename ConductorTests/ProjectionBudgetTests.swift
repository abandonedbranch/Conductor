import Foundation
import Testing
@testable import Conductor

@Suite("ProjectionBudget")
struct ProjectionBudgetTests {
    @Test("Worst-case sub-agent budget fits in 4096 tokens")
    func worstCase() {
        let systemPrompt = 200
        let verbDefs = 4 * 150
        let toolDefs = 3 * 150
        let driver = 100
        let verbOutput =
            ProjectionBudget.contextProjection +
            ProjectionBudget.actionsProjection +
            ProjectionBudget.findRelatedResults
        let toolOutput = 800
        let modelGen = 512
        let total = systemPrompt + verbDefs + toolDefs + driver +
                    (verbOutput / 4) + toolOutput + modelGen
        #expect(total < 4096)
    }

    @Test("Truncation sentinel mentions findRelated for recovery")
    func sentinel() {
        let s = ProjectionBudget.truncationSentinel(remaining: 5)
        #expect(s.contains("5"))
        #expect(s.contains("findRelated"))
    }
}
