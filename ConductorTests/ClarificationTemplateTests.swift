import Testing
@testable import Conductor

@Suite("ClarificationTemplate")
struct ClarificationTemplateTests {
    @Test("Renders user-visible text that includes the verbs and subjects")
    func renders() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(
            verbs: [.build],
            subjects: ["quantum chromodynamics"],
            answerShape: .workflow,
            continuation: nil
        )
        let tools = [
            AffordanceDescriptor(name: "PubMed", affordance: .init(
                verbs: [.find], subjects: [.academic], answerShapes: [.citations], priority: 1
            )),
        ]
        let text = ClarificationTemplate.render(intent: intent, toolbox: tools)
        #expect(text.contains("build"))
        #expect(text.contains("quantum chromodynamics"))
        // Hint should mention something from the toolbox affordances.
        #expect(text.contains("academic") || text.contains("citations"))
    }

    @Test("Hint is empty-safe when toolbox is empty")
    func emptyToolbox() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let intent = LanguageIntentQuery(verbs: [.find], subjects: ["x"], answerShape: .direct, continuation: nil)
        let text = ClarificationTemplate.render(intent: intent, toolbox: [])
        #expect(!text.isEmpty)
    }
}
