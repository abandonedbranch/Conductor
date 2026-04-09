import Foundation
import Testing
@testable import Conductor

@Suite("LibraryTool Tests", .serialized)
struct LibraryToolTests {

    private func makeRegistry() async -> CapabilityRegistry {
        let registry = CapabilityRegistry()
        await registry.register(Capability(
            id: "pubmed",
            name: "PubMed",
            description: "Biomedical and clinical research",
            keywords: ["biomedical", "clinical", "medical", "health", "life science"]
        ) { request in
            "PubMed results for: \(request.extractedGoal)"
        })
        await registry.register(Capability(
            id: "arxiv",
            name: "arXiv",
            description: "Physics, math, computer science preprints",
            keywords: ["physics", "math", "computer science", "preprint", "machine learning"]
        ) { request in
            "arXiv results for: \(request.extractedGoal)"
        })
        await registry.register(Capability(
            id: "wikipedia",
            name: "Wikipedia",
            description: "General knowledge and encyclopedic information",
            keywords: ["general", "history", "overview", "encyclopedia"]
        ) { request in
            "Wikipedia results for: \(request.extractedGoal)"
        })
        return registry
    }

    @Test("Routes to explicit domain when provided")
    func routesByDomain() async {
        let registry = await makeRegistry()
        let result = await LibraryRouter.route(query: "CRISPR", domain: "biomedical", registry: registry)
        #expect(result.contains("PubMed"))
    }

    @Test("Auto-routes based on query keywords when no domain")
    func autoRoutesByQuery() async {
        let registry = await makeRegistry()
        let result = await LibraryRouter.route(query: "clinical trial for immunotherapy", domain: nil, registry: registry)
        #expect(result.contains("PubMed"))
    }

    @Test("Falls back to first result when query is ambiguous")
    func fallbackOnAmbiguousQuery() async {
        let registry = await makeRegistry()
        let result = await LibraryRouter.route(query: "interesting facts", domain: nil, registry: registry)
        // Should still return something, not fail
        #expect(!result.isEmpty)
    }

    @Test("Returns error message when domain matches nothing")
    func unknownDomain() async {
        let registry = await makeRegistry()
        let result = await LibraryRouter.route(query: "test", domain: "astrology", registry: registry)
        #expect(result.contains("No search backend"))
    }
}
