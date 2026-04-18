import Foundation

enum ReadVerb: VerbDefinition {
    static let verb: Verb = .read
    static let lemmas = ["read", "open", "fetch", "load"]
    static let parameters = [
        VerbParameter(role: "url", kind: .url, aliases: [:], required: true, defaultValue: nil)
    ]
    static let needs: [UpstreamEventNeed] = []

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        fatalError("implemented in Task 19")
    }
}
