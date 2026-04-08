import Foundation
import Testing
@testable import Conductor

@Suite("WorkflowPreview Tests")
struct WorkflowPreviewTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let preview = WorkflowPreview(
            title: "Resize Images",
            steps: [
                WorkflowStepPreview(actionName: "Ask for Finder Items", parameterSummary: "type=files", outputType: "public.file-url"),
                WorkflowStepPreview(actionName: "Scale Images", parameterSummary: "scaleFactor=800", outputType: "public.image"),
            ],
            tempFileURL: URL(fileURLWithPath: "/tmp/workflow.workflow")
        )

        let data = try JSONEncoder().encode(preview)
        let decoded = try JSONDecoder().decode(WorkflowPreview.self, from: data)

        #expect(decoded.title == "Resize Images")
        #expect(decoded.steps.count == 2)
        #expect(decoded.steps[0].actionName == "Ask for Finder Items")
        #expect(decoded.steps[1].parameterSummary == "scaleFactor=800")
        #expect(decoded.tempFileURL.path == "/tmp/workflow.workflow")
    }

    @Test("Empty steps array round-trips")
    func emptySteps() throws {
        let preview = WorkflowPreview(
            title: "Empty Workflow",
            steps: [],
            tempFileURL: URL(fileURLWithPath: "/tmp/empty.workflow")
        )
        let data = try JSONEncoder().encode(preview)
        let decoded = try JSONDecoder().decode(WorkflowPreview.self, from: data)
        #expect(decoded.steps.isEmpty)
    }
}
