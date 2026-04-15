import Testing
@testable import Conductor

@Suite("Tool affordance wiring")
struct ToolAffordanceWiringTests {
    @Test("WikipediaSearchTool declares overview + encyclopedic")
    func wikipedia() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let t = WikipediaSearchTool()
        #expect(t.affordance.verbs.contains(.find))
        #expect(t.affordance.subjects.contains(.encyclopedic))
        #expect(t.affordance.answerShapes.contains(.overview))
    }

    @Test("PubMedSearchTool declares biomedical citations")
    func pubmed() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let t = PubMedSearchTool()
        #expect(t.affordance.subjects.contains(.biomedical))
        #expect(t.affordance.answerShapes.contains(.citations))
    }

    @Test("WebReaderTool declares webpage + summary/direct")
    func web() {
        guard #available(iOS 19.0, macOS 26.0, *) else { return }
        let t = WebReaderTool()
        #expect(t.affordance.verbs.contains(.read))
        #expect(t.affordance.subjects.contains(.webpage))
    }
}
