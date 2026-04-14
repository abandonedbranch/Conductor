import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct ComposedResponse: Sendable, Codable {
    @Guide(description: "The main prose response to the user")
    var prose: String
    @Guide(description: "Optional section breakdown")
    var sections: [Section]?

    @Generable
    struct Section: Codable, Sendable {
        @Guide(description: "Heading for this section")
        var heading: String
        @Guide(description: "Content under this heading")
        var content: String
    }
}

@available(iOS 19.0, macOS 26.0, *)
protocol ComposeResponseRunning: Sendable {
    func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse
}

@available(iOS 19.0, macOS 26.0, *)
struct ComposeResponseSession {
    let runner: any ComposeResponseRunning

    func compose(intent: LanguageIntentQuery, outcome: [Atom]) async throws -> ComposedResponse {
        let rag = Self.ragProjection(from: outcome)
        return try await runner.compose(intent: intent, ragBlock: rag)
    }

    static func ragProjection(from outcome: [Atom]) -> String {
        let lines = outcome.compactMap { atom -> String? in
            switch atom {
            case let .success(content, source, toolName, _):
                if let source { return "[\(toolName) · \(source.absoluteString)] \(content)" }
                return "[\(toolName)] \(content)"
            case let .note(text, _): return "[note] \(text)"
            case .error: return nil
            }
        }
        return ProjectionBudget.bound(
            lines.joined(separator: "\n---\n"),
            characterBudget: ProjectionBudget.composeResponseProjection
        )
    }
}

@available(iOS 19.0, macOS 26.0, *)
struct LiveComposeRunner: ComposeResponseRunning {
    func compose(intent: LanguageIntentQuery, ragBlock: String) async throws -> ComposedResponse {
        let session = LanguageModelSession(
            tools: [],
            instructions: """
            You are synthesizing a response. You do not have memory verbs or domain tools.
            The user asked for: \(intent.subjects.joined(separator: ", ")).
            AnswerShape: \(intent.answerShape.rawValue).
            Use the following RAG block as your only source of truth:
            ---
            \(ragBlock)
            ---
            Produce a ComposedResponse. Be concise. Cite by tool name when relevant.
            """
        )
        let response = try await session.respond(to: "Synthesize.", generating: ComposedResponse.self)
        return response.content
    }
}
