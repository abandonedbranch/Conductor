import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct LogEntry: Identifiable, Sendable {
    @Guide(description: "A unique identifier for this log entry")
    var id: String

    @Guide(description: "The task graph node identifier this entry belongs to")
    var taskID: String

    @Guide(description: "The agent purpose category: overview, research, web, or build")
    var purpose: String

    @Guide(description: "The name of the tool that produced this entry")
    var toolName: String

    @Guide(description: "The content or result produced by the tool")
    var content: String

    @Guide(description: "The source URL, if the content was fetched from the web")
    var sourceURL: String?

    @Guide(description: "ISO 8601 timestamp when this entry was created")
    var timestamp: String
}
