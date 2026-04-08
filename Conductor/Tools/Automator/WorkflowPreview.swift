import Foundation

struct WorkflowStepPreview: Codable, Hashable {
    let actionName: String
    let parameterSummary: String
    let outputType: String
}

struct WorkflowPreview: Codable, Hashable {
    let title: String
    let steps: [WorkflowStepPreview]
    let tempFileURL: URL
}
