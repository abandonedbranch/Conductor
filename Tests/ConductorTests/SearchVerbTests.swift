import Testing
import Foundation
@testable import Conductor

@Suite struct SearchVerbTests {
    @Test func dispatches_toPubMed_whenTargetIsPubMed() async throws {
        let http = FakeHTTPClient()
        let search = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=CRISPR&retmax=3&retmode=json")!
        let summary = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=111&retmode=json")!
        http.scripted[search] = Data(#"{"esearchresult":{"idlist":["111"]}}"#.utf8)
        http.scripted[summary] = Data(#"{"result":{"uids":["111"],"111":{"title":"A","uid":"111"}}}"#.utf8)

        let inputs = ResolvedInputs(atoms: [
            "search.terms": .text("CRISPR"),
            "search.target": .choice(namespace: "search.target", value: "pubMed"),
            "search.limit": .number(3)
        ], upstream: [])
        let events = try await SearchVerb.execute(
            resolved: inputs,
            origin: .step(id: UUID(), index: 0),
            http: http,
            llm: FakeLLMSession()
        )
        let sr = events.compactMap { $0 as? SearchResults }.first
        #expect(sr?.target == "pubMed")
        #expect(sr?.papers.count == 1)
    }

    @Test func usesClaimsExtracted_whenPresent() async throws {
        let http = FakeHTTPClient()
        let search = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=sickle-cell%20CRISPR&retmax=3&retmode=json")!
        let summary = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=1&retmode=json")!
        http.scripted[search] = Data(#"{"esearchresult":{"idlist":["1"]}}"#.utf8)
        http.scripted[summary] = Data(#"{"result":{"uids":["1"],"1":{"title":"T","uid":"1"}}}"#.utf8)
        let claims = ClaimsExtracted(claims: [Claim(text: "sickle-cell"), Claim(text: "CRISPR")], origin: .step(id: UUID(), index: 0))
        let inputs = ResolvedInputs(atoms: [
            "search.target": .choice(namespace: "search.target", value: "pubMed"),
            "search.limit": .number(3)
        ], upstream: [claims])
        let events = try await SearchVerb.execute(resolved: inputs, origin: .step(id: UUID(), index: 1), http: http, llm: FakeLLMSession())
        #expect((events.first as? SearchResults) != nil)
    }
}
