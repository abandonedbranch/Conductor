import Foundation

/// A single propositional assertion extracted from text by the LLM.
///
/// Produced by `ExtractClaimsVerb`, which feeds a `SummaryProduced.summary`
/// to the model and asks for the atomic claims the text *makes*. The name is
/// deliberate: these are statements the source claims, not facts the system
/// vouches for. Verification (evidence retrieval, citation, contradiction
/// detection) is out of scope for v2 — `Claim` is just the noun the pipeline
/// traffics in so later work can reason about provenance.
struct Claim: Sendable, Hashable {
    let text: String
}
