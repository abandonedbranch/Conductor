import Foundation
import Testing
@testable import Conductor

@Suite("CapabilityRegistry Tests", .serialized)
struct CapabilityRegistryTests {

    private func makeCapability(
        id: String,
        name: String,
        keywords: [String] = [],
        description: String = ""
    ) -> Capability {
        Capability(
            id: id,
            name: name,
            description: description,
            keywords: keywords,
            execute: { _ in "executed \(id)" }
        )
    }

    @Test("Returns empty results for query with no matches")
    func zeroMatches() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Build Workflow", keywords: ["automator"]))
        let results = await registry.search(query: "spreadsheet", maxResults: 5)
        #expect(results.isEmpty)
    }

    @Test("Returns single match when query hits one capability")
    func singleMatch() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Build Workflow", keywords: ["automator", "workflow"]))
        await registry.register(makeCapability(id: "b", name: "Search PubMed", keywords: ["biomedical", "clinical"]))
        let results = await registry.search(query: "workflow", maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].capability.id == "a")
    }

    @Test("Returns multiple matches sorted by score")
    func multipleMatchesSorted() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(
            id: "a",
            name: "Build Workflow",
            keywords: ["automator", "workflow", "automate"],
            description: "Build macOS Automator workflows"
        ))
        await registry.register(makeCapability(
            id: "b",
            name: "Run Shortcut",
            keywords: ["shortcut", "automate"],
            description: "Run a Shortcuts workflow"
        ))
        let results = await registry.search(query: "automate workflow", maxResults: 5)
        #expect(results.count == 2)
        #expect(results[0].capability.id == "a")
        #expect(results[0].score > results[1].score)
    }

    @Test("Name matches score higher than keyword matches")
    func nameScoresHigherThanKeyword() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Search Images", keywords: ["photo"]))
        await registry.register(makeCapability(id: "b", name: "Edit Photo", keywords: ["images"]))
        let results = await registry.search(query: "images", maxResults: 5)
        #expect(results[0].capability.id == "a")
    }

    @Test("Search is case insensitive")
    func caseInsensitive() async {
        let registry = CapabilityRegistry()
        await registry.register(makeCapability(id: "a", name: "Build Workflow", keywords: ["AUTOMATOR"]))
        let results = await registry.search(query: "automator", maxResults: 5)
        #expect(results.count == 1)
    }

    @Test("Respects maxResults limit")
    func respectsMaxResults() async {
        let registry = CapabilityRegistry()
        for i in 1...10 {
            await registry.register(makeCapability(id: "\(i)", name: "Tool \(i)", keywords: ["common"]))
        }
        let results = await registry.search(query: "common", maxResults: 3)
        #expect(results.count == 3)
    }
}
