import Testing
@testable import Conductor

@Suite("ToolAffordance")
struct ToolAffordanceTests {
    @Test("AffordanceDescriptor surfaces the embedded affordance")
    func descriptorAffordance() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let aff = ToolAffordance(
            verbs: [.find],
            subjects: [.academic],
            answerShapes: [.citations],
            priority: 10
        )
        let desc = AffordanceDescriptor(name: "PubMed", affordance: aff)
        #expect(desc.affordance.verbs.contains(.find))
        #expect(desc.name == "PubMed")
    }
}
