import Foundation
import Testing
@testable import Conductor

@Suite("ActionTool Tests", .serialized)
struct ActionToolTests {

    private func makeRegistry(_ capabilities: [Capability]) async -> CapabilityRegistry {
        let registry = CapabilityRegistry()
        for cap in capabilities {
            await registry.register(cap)
        }
        return registry
    }

    @Test("Returns no-match message when no capabilities match")
    func zeroMatches() async {
        let registry = await makeRegistry([
            Capability(id: "a", name: "Build Workflow", description: "", keywords: ["automator"]) { _ in "built" }
        ])
        let result = await ActionResolver.resolve(userMessage: "play some music", registry: registry)
        switch result {
        case .noMatch(let message):
            #expect(message.contains("No program"))
        default:
            Issue.record("Expected noMatch, got \(result)")
        }
    }

    @Test("Executes single matching capability")
    func singleMatch() async {
        let registry = await makeRegistry([
            Capability(id: "a", name: "Build Workflow", description: "", keywords: ["automator", "workflow"]) { request in
                "built: \(request.extractedGoal)"
            }
        ])
        let result = await ActionResolver.resolve(userMessage: "build an automator workflow to rename files", registry: registry)
        switch result {
        case .executed(let output):
            #expect(output.contains("built"))
        default:
            Issue.record("Expected executed, got \(result)")
        }
    }

    @Test("Returns vague intent when multiple capabilities match")
    func multipleMatches() async {
        let registry = await makeRegistry([
            Capability(id: "a", name: "Automate Files", description: "", keywords: ["automate", "files"]) { _ in "a" },
            Capability(id: "b", name: "Automate Photos", description: "", keywords: ["automate", "photos"]) { _ in "b" },
        ])
        let result = await ActionResolver.resolve(userMessage: "automate something", registry: registry)
        switch result {
        case .vagueIntent(let count):
            #expect(count == 2)
        default:
            Issue.record("Expected vagueIntent, got \(result)")
        }
    }
}
