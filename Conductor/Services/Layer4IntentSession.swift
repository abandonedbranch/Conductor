import Foundation

enum Layer4IntentSession {
    static func classify(prose: String, llm: any LLMSession) async throws -> [Verb] {
        let intent = try await llm.inferPipeline(from: prose)
        return intent.verbs
    }
}
