import Testing
import Foundation
@testable import Conductor

@Suite struct PubMedBackendTests {
    @Test func parsesESearchAndESummary() async throws {
        let http = FakeHTTPClient()
        let searchURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=crispr&retmax=2&retmode=json")!
        let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=111,222&retmode=json")!
        http.scripted[searchURL] = Data(#"{"esearchresult":{"idlist":["111","222"]}}"#.utf8)
        http.scripted[summaryURL] = Data(#"{"result":{"uids":["111","222"],"111":{"title":"A","uid":"111"},"222":{"title":"B","uid":"222"}}}"#.utf8)
        let papers = try await PubMedBackend.search(terms: "crispr", limit: 2, http: http)
        #expect(papers.count == 2)
        #expect(papers[0].identifier == "111")
    }
}
