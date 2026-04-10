import Foundation

struct NarrationEvent: Codable, Sendable {
    let taskID: UUID
    let purpose: AgentPurpose
    let message: String
    let timestamp: Date

    init(taskID: UUID, purpose: AgentPurpose, message: String) {
        self.taskID = taskID
        self.purpose = purpose
        self.message = message
        self.timestamp = .now
    }
}
