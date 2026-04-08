#if os(macOS)
import Foundation
import Automator
import FoundationModels

@available(macOS 26.0, *)
struct BuildAutomatorWorkflowTool: BadgedTool {
    let name = "buildAutomatorWorkflow"
    let description = "Build a macOS Automator workflow from a list of actions. IMPORTANT: You MUST call searchAutomatorActions first to get the exact bundle paths — do not guess paths. Search for each type of action needed (e.g. search for 'ask finder' to get a file picker, search for 'scale' to get image resize). Use the bundle paths from search results."
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "gear.badge", tint: .gray, label: "Automator")

    @Generable
    struct Arguments {
        @Guide(description: "A descriptive title for the workflow")
        var workflowTitle: String

        @Guide(description: "Ordered list of workflow steps")
        var steps: [WorkflowStep]
    }

    @Generable
    struct WorkflowStep {
        @Guide(description: "Full path to the .action bundle (from searchAutomatorActions results)")
        var actionBundlePath: String

        @Guide(description: "Parameter overrides. Keys must match parameter names from searchAutomatorActions results.")
        var parameters: [ParameterPair]?
    }

    @Generable
    struct ParameterPair {
        @Guide(description: "The parameter name")
        var key: String

        @Guide(description: "The parameter value")
        var value: String
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(badge)

        let workflow = AMWorkflow()
        var stepPreviews: [WorkflowStepPreview] = []
        var errors: [String] = []

        for (i, step) in arguments.steps.enumerated() {
            let bundleURL = URL(fileURLWithPath: step.actionBundlePath)

            guard let action = try? AMAction(contentsOf: bundleURL) else {
                errors.append("Step \(i + 1): Could not load action at \(step.actionBundlePath). Skipping.")
                continue
            }

            if let bundleAction = action as? AMBundleAction, let params = step.parameters {
                let existingParams = bundleAction.parameters ?? NSMutableDictionary()
                for pair in params {
                    existingParams[pair.key] = coerceValue(pair.value, existingDefault: existingParams[pair.key])
                }
                bundleAction.parameters = existingParams
            }

            workflow.addAction(action)

            let paramSummary = step.parameters?.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? ""
            let outputType = (action as? AMBundleAction).flatMap { bundleAction in
                (bundleAction.bundle.infoDictionary?["AMProvides"] as? [String: Any])?["Types"] as? [String]
            }?.first ?? "unknown"

            stepPreviews.append(WorkflowStepPreview(
                actionName: action.name,
                parameterSummary: paramSummary,
                outputType: outputType
            ))
        }

        guard !stepPreviews.isEmpty else {
            return "Could not build workflow: no valid actions loaded.\(errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = arguments.workflowTitle
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let tempURL = tempDir.appendingPathComponent("\(fileName).workflow")

        do {
            try workflow.write(to: tempURL)
        } catch {
            return "Could not save workflow to temporary location: \(error.localizedDescription)"
        }

        let preview = WorkflowPreview(
            title: arguments.workflowTitle,
            steps: stepPreviews,
            tempFileURL: tempURL
        )
        await tracker.setWorkflowPreview(preview)

        var lines = ["Workflow: \"\(arguments.workflowTitle)\"\n\nSteps:"]
        for (i, step) in stepPreviews.enumerated() {
            let params = step.parameterSummary.isEmpty ? "" : " (\(step.parameterSummary))"
            lines.append("\(i + 1). \(step.actionName)\(params) → [\(step.outputType)]")
        }

        if !errors.isEmpty {
            lines.append("\nWarnings:\n" + errors.joined(separator: "\n"))
        }

        lines.append("\nWorkflow ready. Use the Save button to export as a .workflow file.")

        return lines.joined(separator: "\n")
    }

    private func coerceValue(_ stringValue: String, existingDefault: Any?) -> Any {
        switch existingDefault {
        case is Int:
            return Int(stringValue) ?? stringValue
        case is Double:
            return Double(stringValue) ?? stringValue
        case is Float:
            return Float(stringValue) ?? stringValue
        case is Bool:
            return stringValue.lowercased() == "true"
        default:
            if let intVal = Int(stringValue) { return intVal }
            if let doubleVal = Double(stringValue) { return doubleVal }
            if stringValue.lowercased() == "true" || stringValue.lowercased() == "false" {
                return stringValue.lowercased() == "true"
            }
            return stringValue
        }
    }
}
#endif
