import Foundation

enum SearchVerb: VerbDefinition {
    static let verb: Verb = .search
    static let lemmas = ["search", "find", "look up", "look for", "query"]
    static let parameters = [
        VerbParameter(role: "search.terms", kind: .text, aliases: [:], required: true, defaultValue: nil),
        VerbParameter(
            role: "search.target",
            kind: .choice(namespace: "search.target", cases: ["pubMed", "arxiv", "web", "wikipedia"]),
            aliases: [
                "pubmed": "pubMed", "pub med": "pubMed",
                "arxiv": "arxiv", "arxiv.org": "arxiv",
                "web": "web", "google": "web", "internet": "web",
                "wikipedia": "wikipedia", "wiki": "wikipedia", "wikipedia.org": "wikipedia"
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
        let terms: String
        if let claims = resolved.upstream.compactMap({ $0 as? ClaimsExtracted }).last, !claims.claims.isEmpty {
            terms = claims.claims.map { $0.text }.joined(separator: " ")
        } else if case let .text(t)? = resolved.atoms["search.terms"] {
            terms = t
        } else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no search terms", origin: origin)]
        }

        guard case let .choice(_, target)? = resolved.atoms["search.target"] else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no search target", origin: origin)]
        }

        let limit: Int = {
            if case let .number(n)? = resolved.atoms["search.limit"] { return Int(n) }
            return 5
        }()

        do {
            let papers: [Paper]
            switch target {
            case "pubMed":    papers = try await PubMedBackend.search(terms: terms, limit: limit, http: http)
            case "arxiv":     papers = try await ArxivBackend.search(terms: terms, limit: limit, http: http)
            case "web":       papers = try await WebBackend.search(terms: terms, limit: limit, http: http)
            case "wikipedia": papers = try await WikipediaBackend.search(terms: terms, limit: limit, http: http)
            default:
                return [StepFailed(stepID: origin.stepID ?? UUID(), message: "unknown target \(target)", origin: origin)]
            }
            return [SearchResults(papers: papers, target: target, origin: origin)]
        } catch {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "\(error)", origin: origin)]
        }
    }
}
