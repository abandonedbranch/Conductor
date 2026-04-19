import Testing
import Foundation
@testable import Conductor

@Suite struct OriginTests {
    @Test func compileOrigin_hasNilStepID() {
        let o = Origin.compile()
        #expect(o.stepID == nil)
        #expect(o.stepIndex == nil)
    }

    @Test func stepOrigin_carriesIndexAndID() {
        let id = UUID()
        let o = Origin.step(id: id, index: 2)
        #expect(o.stepID == id)
        #expect(o.stepIndex == 2)
        #expect(o.iteration == nil)
    }

    @Test func iterationOrigin_carriesIteration() {
        let id = UUID()
        let o = Origin.step(id: id, index: 2, iteration: 3)
        #expect(o.iteration == 3)
    }
}
