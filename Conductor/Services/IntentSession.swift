import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol IntentSessionRunning: Sendable {
    func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery
}

@available(iOS 19.0, macOS 26.0, *)
struct IntentSession {
    let runner: any IntentSessionRunning
    let graph: WorkingMemoryGraph

    func handle(message: String) async throws {
        let turn = await graph.currentTurn()
        let contextVerb: GetContextVerb? = (turn == 0) ? nil : GetContextVerb(graph: graph)
        let intent = try await runner.extract(message: message, contextVerb: contextVerb)
        await graph.append(intent: intent)
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct LiveIntentRunner: IntentSessionRunning {
    static let parseInstructions = """
    You translate the user's message into a structured LanguageIntentQuery.
    Do not answer the user. Do not speculate. Only emit the typed value.
    Pick verbs from: find, summarize, recall, build, read.
    Pick answerShape from: overview, summary, citations, workflow, direct.
    If this message continues a prior turn, set continuation accordingly.
    """

    func extract(message: String, contextVerb: GetContextVerb?) async throws -> LanguageIntentQuery {
        let tools: [any Tool] = contextVerb.map { [$0 as any Tool] } ?? []
        let session = LanguageModelSession(
            tools: tools,
            instructions: Self.parseInstructions
        )
        let response = try await session.respond(to: message, generating: LanguageIntentQuery.self)
        return response.content
    }
}
