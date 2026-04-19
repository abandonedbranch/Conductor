import Testing
import Foundation
@testable import Conductor

@MainActor @Suite struct EndToEndTests {
    @Test func crisprProseProducesFullPipelineWithoutLLM() async throws {
        let prose = "Summarize the article at https://example.com about CRISPR and sickle-cell, and find 3 related PubMed papers"
        let http = FakeHTTPClient()
        let articleURL = URL(string: "https://example.com")!
        http.scripted[articleURL] = Data("<title>CRISPR article</title><body>body</body>".utf8)

        let searchURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=CRISPR%20and%20sickle-cell&retmax=3&retmode=json")!
        http.scripted[searchURL] = Data(#"{"esearchresult":{"idlist":["1","2","3"]}}"#.utf8)
        let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=1,2,3&retmode=json")!
        http.scripted[summaryURL] = Data(#"{"result":{"uids":["1","2","3"],"1":{"title":"A","uid":"1"},"2":{"title":"B","uid":"2"},"3":{"title":"C","uid":"3"}}}"#.utf8)

        let llm = FakeLLMSession()
        llm.scriptedSummary = SummaryGenerable(summary: "About CRISPR.", claims: [], sentiment: "neutral")

        let log = EventLog()
        let compiled = try await ProseCompiler.compile(prose: prose, llm: llm)
        #expect(compiled.usedLLM == false)
        for a in compiled.atoms { log.append(a) }
        let inflated = NeedsClosure.inflate(verbs: compiled.verbs, existingLog: log.events)
        let steps = inflated.enumerated().map { i, v in Step(index: i, verb: v) }

        let runtime = Runtime(log: log, http: http, llm: llm, askResolver: AutoAcceptAskResolver())
        try await runtime.run(steps: steps)

        #expect(log.eventsOfType(ReadCompleted.self).count == 1)
        #expect(log.eventsOfType(SummaryProduced.self).count >= 1)
        #expect(log.eventsOfType(SearchResults.self).first?.papers.count == 3)
    }
}
