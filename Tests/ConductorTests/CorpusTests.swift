import Testing
import Foundation
@testable import Conductor

@Suite struct CorpusTests {
    private static let corpus: [(prose: String, expectedVerbs: Set<Verb>)] = [
        ("Read https://example.com", [.read]),
        ("Summarize the article at https://example.com", [.read, .summarize]),
        ("Find 3 PubMed papers about CRISPR", [.search]),
        ("Search arxiv for transformers", [.search]),
        ("Look up 5 papers on quantum computing on arxiv", [.search]),
        ("Summarize https://x.com and find related work", [.read, .summarize, .search]),
        ("Extract claims from the summary", [.extractClaims]),
        ("Fetch https://a.com and summarize it", [.read, .summarize]),
        ("Open https://b.com and pull out the claims", [.read, .summarize, .extractClaims]),
        ("Find 10 papers on sickle-cell on PubMed", [.search]),
        ("Query the web for climate change", [.search]),
        ("Summarize the article at https://c.com", [.read, .summarize]),
        ("Read https://d.com then find 3 related arxiv papers", [.read, .search]),
        ("Search pubmed for BRCA1", [.search]),
        ("Find 4 related papers on arxiv.org", [.search]),
        ("Load https://e.com", [.read]),
        ("Digest https://f.com", [.read, .summarize]),
        ("Summarize and extract claims from https://g.com", [.read, .summarize, .extractClaims]),
        ("Find papers on quantum", [.search]),
        ("Search google for LLMs", [.search]),
        ("Look for 2 papers on cancer on PubMed", [.search]),
        ("Open https://h.com, summarize, extract claims, find 3 related papers", [.read, .summarize, .extractClaims, .search]),
        ("Summarize https://i.com as a paper summary", [.read, .summarize]),
        ("Read and summarize the article at https://j.com", [.read, .summarize]),
        ("Pull claims from the summary", [.extractClaims]),
        ("Search arxiv for protein folding", [.search]),
        ("Find 7 papers about fusion on PubMed", [.search]),
        ("Summarize the article and search the web for critiques", [.read, .summarize, .search]),
        ("Open https://k.com", [.read]),
        ("Digest the article at https://l.com and find 3 arxiv papers on it", [.read, .summarize, .search]),
    ]

    @Test func atLeastSeventyPercentCompilesWithoutLLM() async throws {
        let llm = FakeLLMSession()
        llm.scriptedIntent = PipelineIntent(verbs: [.search])
        var l4Used = 0
        var verbMisses = 0
        for (prose, expected) in Self.corpus {
            let result = try await ProseCompiler.compile(prose: prose, llm: llm)
            if result.usedLLM { l4Used += 1 }
            if !expected.isSubset(of: Set(result.verbs)) { verbMisses += 1 }
        }
        let l4FreeRatio = Double(Self.corpus.count - l4Used) / Double(Self.corpus.count)
        #expect(l4FreeRatio >= 0.70, "only \(Int(l4FreeRatio * 100))% L4-free; target 70%")
        #expect(verbMisses <= 3, "too many verb-set mismatches: \(verbMisses)")
    }
}
