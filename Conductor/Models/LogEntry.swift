import Foundation

struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let taskID: UUID
    let purpose: AgentPurpose
    let toolName: String
    let content: String
    let sourceURL: String?
    let timestamp: Date
}
