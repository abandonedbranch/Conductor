import Testing
import Foundation
@testable import Conductor

@Suite struct NeedsClosureTests {
    @Test func prependsRead_beforeSummarize_whenNoReadExists() {
        let pipeline = NeedsClosure.inflate(verbs: [.summarize], existingLog: [])
        #expect(pipeline == [.read, .summarize])
    }

    @Test func noInflation_whenReadAlreadyInPipeline() {
        let pipeline = NeedsClosure.inflate(verbs: [.read, .summarize], existingLog: [])
        #expect(pipeline == [.read, .summarize])
    }

    @Test func noInflation_whenReadEventAlreadyInLog() {
        let rc = ReadCompleted(body: "", title: "", url: URL(string: "https://x")!, origin: .step(id: UUID(), index: 0))
        let pipeline = NeedsClosure.inflate(verbs: [.summarize], existingLog: [rc])
        #expect(pipeline == [.summarize])
    }

    @Test func prependsSearch_beforeSummarizeOfSearchResults_whenChosen() {
        let pipeline = NeedsClosure.inflate(verbs: [.summarize], existingLog: [])
        #expect(pipeline.first == .read)
    }
}
