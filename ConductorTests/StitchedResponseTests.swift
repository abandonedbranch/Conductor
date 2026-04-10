import Foundation
import Testing
@testable import Conductor

@Suite("StitchedResponse Tests")
struct StitchedResponseTests {

    @Test("Formatted output includes section headings and content")
    func formattedOutput() {
        let sections = [
            StitchedResponse.ResponseSection(
                heading: "Overview",
                content: "CRISPR is a gene editing technology.",
                sources: []
            ),
            StitchedResponse.ResponseSection(
                heading: "Research Findings",
                content: "Frangoul et al. demonstrated clinical response.",
                sources: [ToolSource(title: "PubMed", url: "https://pubmed.ncbi.nlm.nih.gov/123")]
            ),
        ]
        let response = StitchedResponse(sections: sections)
        let output = response.formatted
        #expect(output.contains("## Overview"))
        #expect(output.contains("CRISPR is a gene editing technology."))
        #expect(output.contains("## Research Findings"))
        #expect(output.contains("Frangoul"))
    }

    @Test("Empty sections produce empty formatted output")
    func emptyResponse() {
        let response = StitchedResponse(sections: [])
        #expect(response.formatted.isEmpty)
    }

    @Test("Stitch from TaskGraph produces sections in topological order")
    func stitchFromGraph() async {
        let graph = TaskGraph()

        let a = TaskGraph.TaskNode(
            id: UUID(), purpose: .overview, goal: "overview",
            completionCriteria: "done", toolNames: ["Wikipedia"],
            dependsOn: []
        )
        let b = TaskGraph.TaskNode(
            id: UUID(), purpose: .research, goal: "research",
            completionCriteria: "done", toolNames: ["PubMed"],
            dependsOn: [a.id]
        )
        await graph.addNode(a)
        await graph.addNode(b)
        await graph.updateStatus(a.id, to: .completed)
        await graph.updateStatus(b.id, to: .completed)

        let entryA = LogEntry(
            id: UUID(), taskID: a.id, purpose: .overview,
            toolName: "Wikipedia", content: "Overview content",
            sourceURL: "https://en.wikipedia.org/wiki/Test", timestamp: .now
        )
        let entryB = LogEntry(
            id: UUID(), taskID: b.id, purpose: .research,
            toolName: "PubMed", content: "Research content",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/123", timestamp: .now
        )
        await graph.append(entryA, to: a.id)
        await graph.append(entryB, to: b.id)

        let response = await graph.stitch()
        #expect(response.sections.count == 2)
        #expect(response.sections[0].heading == "Overview")
        #expect(response.sections[1].heading == "Research Findings")
        #expect(response.sections[0].sources.count == 1)
    }

    @Test("Stitch skips failed nodes")
    func stitchSkipsFailed() async {
        let graph = TaskGraph()
        let a = TaskGraph.TaskNode(
            id: UUID(), purpose: .overview, goal: "overview",
            completionCriteria: "done", toolNames: ["Wikipedia"],
            dependsOn: []
        )
        await graph.addNode(a)
        await graph.updateStatus(a.id, to: .failed)
        let response = await graph.stitch()
        #expect(response.sections.isEmpty)
    }
}
