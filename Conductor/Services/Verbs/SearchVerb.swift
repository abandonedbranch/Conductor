import Foundation

enum SearchVerb: VerbDefinition {
    static let verb: Verb = .search
    static let lemmas = ["search", "find", "look up", "look for", "query"]
    static let parameters = [
        VerbParameter(role: "search.terms", kind: .text, aliases: [:], required: true, defaultValue: nil),
        VerbParameter(
            role: "search.target",
            kind: .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web"]),
            aliases: [
                "pubmed": "pubMed", "pub med": "pubMed",
                "arxiv": "arxiv", "arxiv.org": "arxiv",
                "web": "web", "google": "web", "internet": "web"
            ],
            required: true,
            defaultValue: nil
        ),
        VerbParameter(role: "search.limit", kind: .number, aliases: [:], required: false, defaultValue: .number(5))
    ]
    static let needs: [UpstreamEventNeed] = []

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        fatalError("implemented in Task 25")
    }
}
