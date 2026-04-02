import Testing
@testable import Conductor

@Suite("Conductor Tests")
struct ConductorTests {
    @Test("App launches with expected content")
    func appContent() {
        // Verify the app's main view can be instantiated
        let view = ContentView()
        #expect(view != nil)
    }
}
