import Foundation

enum ExtractClaimsVerb: VerbDefinition {
    static let verb: Verb = .extractClaims
    static let lemmas = ["extract", "pull", "identify"]
    static let parameters: [VerbParameter] = []
    static let needs = [
        UpstreamEventNeed(eventTypeNames: ["SummaryProduced"], required: true)
    ]

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        guard let summary = resolved.upstream.compactMap({ $0 as? SummaryProduced }).last else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "no summary", origin: origin)]
        }
        do {
            let gen = try await llm.extractClaims(from: summary.summary)
            let claims = gen.claims.map { Claim(text: $0) }
            return [ClaimsExtracted(claims: claims, origin: origin)]
        } catch {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "\(error)", origin: origin)]
        }
    }
}
