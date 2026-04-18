import Foundation

enum Projections {
    static func articleSummary(log: [any Event]) -> SummaryProduced? {
        log.reversed().compactMap { $0 as? SummaryProduced }.first { $0.role == "articleSummary" }
    }

    static func paperSummaries(log: [any Event]) -> [SummaryProduced] {
        log.compactMap { $0 as? SummaryProduced }.filter { $0.role == "paperSummary" }
    }

    static func searchResults(log: [any Event]) -> SearchResults? {
        log.reversed().compactMap { $0 as? SearchResults }.first
    }

    static func pipelineStatus(log: [any Event], steps: [Step]) -> [StepStatus] {
        steps.map { step in
            if let failure = log.compactMap({ $0 as? StepFailed }).first(where: { $0.stepID == step.id }) {
                return .failed(message: failure.message)
            }
            if log.contains(where: { $0.origin.stepID == step.id && !($0 is StepFailed) }) {
                return .completed
            }
            return .idle
        }
    }
}
