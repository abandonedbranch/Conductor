import Foundation

struct StepFailed: Event {
    let id = UUID()
    let timestamp = Date()
    let stepID: UUID
    let message: String
    let origin: Origin
}
