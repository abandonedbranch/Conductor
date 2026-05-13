import Foundation

enum StepStatus: Sendable, Hashable {
    case idle
    case running
    case completed
    case failed(message: String)
    case awaitingInput(role: String, kind: AtomKind)
}
