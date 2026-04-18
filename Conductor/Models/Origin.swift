import Foundation

struct Origin: Sendable, Hashable {
    let stepID: UUID?
    let stepIndex: Int?
    let iteration: Int?
    let parentStepID: UUID?

    static func compile() -> Origin {
        Origin(stepID: nil, stepIndex: nil, iteration: nil, parentStepID: nil)
    }

    static func step(id: UUID, index: Int, iteration: Int? = nil, parentStepID: UUID? = nil) -> Origin {
        Origin(stepID: id, stepIndex: index, iteration: iteration, parentStepID: parentStepID)
    }
}
