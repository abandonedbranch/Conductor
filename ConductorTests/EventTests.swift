import Testing
import Foundation
@testable import Conductor

@Suite struct EventTests {
    private struct DummyEvent: Event {
        let id = UUID()
        let origin = Origin.compile()
        let timestamp = Date()
    }

    @Test func eventProtocol_requiresIDAndOrigin() {
        let e = DummyEvent()
        #expect(e.origin.stepID == nil)
        #expect(type(of: e.id) == UUID.self)
    }
}
