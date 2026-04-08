#if os(macOS)
import Foundation
import Automator
import FoundationModels

// MARK: - Planner Types (used by secondary session)

@available(macOS 26.0, *)
@Generable
struct WorkflowPlan {
    @Guide(description: "A short descriptive title for the workflow")
    var title: String

    @Guide(description: "Ordered list of actions to perform. Use EXACT action names from the provided catalog.")
    var steps: [PlannedStep]
}

@available(macOS 26.0, *)
@Generable
struct PlannedStep {
    @Guide(description: "The exact action name from the catalog")
    var actionName: String

    @Guide(description: "Parameter overrides as key-value pairs. Only include parameters you need to change from defaults.")
    var parameters: [PlannedParameter]?
}

@available(macOS 26.0, *)
@Generable
struct PlannedParameter {
    @Guide(description: "The parameter key from the catalog")
    var key: String

    @Guide(description: "The value to set")
    var value: String
}

// MARK: - Tool

@available(macOS 26.0, *)
struct BuildAutomatorWorkflowTool: BadgedTool {
    let name = "buildAutomatorWorkflow"
    let description = "Build a macOS Automator workflow from a natural language description. Describe what the workflow should do (e.g. 'ask the user to select images then scale them to 800 pixels') and this tool will find the right actions, configure them, and build the workflow."
    let tracker: ToolUsageTracker
    let badge = ToolBadge(icon: "gear.badge", tint: .gray, label: "Automator")

    private let index: AutomatorActionIndex

    init(tracker: ToolUsageTracker, index: AutomatorActionIndex) {
        self.tracker = tracker
        self.index = index
    }

    @Generable
    struct Arguments {
        @Guide(description: "Natural language description of what the workflow should do")
        var workflowDescription: String
    }

    func call(arguments: Arguments) async -> String {
        await tracker.record(badge)

        // Step 1: Get the action catalog
        let catalog = await index.catalog()
        guard !catalog.isEmpty else {
            return "Could not scan Automator actions. Automator may not be available on this system."
        }

        // Step 2: Use a secondary session to plan the workflow
        let plan: WorkflowPlan
        do {
            plan = try await planWorkflow(description: arguments.workflowDescription, catalog: catalog)
        } catch {
            return "Could not plan workflow: \(error.localizedDescription)"
        }

        guard !plan.steps.isEmpty else {
            return "Could not determine which actions to use for: \"\(arguments.workflowDescription)\""
        }

        // Step 3: Mechanically build the AMWorkflow
        let workflow = AMWorkflow()
        var stepPreviews: [WorkflowStepPreview] = []
        var errors: [String] = []

        for (i, step) in plan.steps.enumerated() {
            guard let bundleURL = await index.bundleURL(forActionNamed: step.actionName) else {
                errors.append("Step \(i + 1): No action named \"\(step.actionName)\" found.")
                continue
            }

            guard let action = try? AMAction(contentsOf: bundleURL) else {
                errors.append("Step \(i + 1): Could not load \"\(step.actionName)\".")
                continue
            }

            if let bundleAction = action as? AMBundleAction, let params = step.parameters {
                let existingParams = bundleAction.parameters ?? NSMutableDictionary()
                for param in params {
                    existingParams[param.key] = coerceValue(param.value, existingDefault: existingParams[param.key])
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

        // Step 4: Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = plan.title
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let tempURL = tempDir.appendingPathComponent("\(fileName).workflow")

        do {
            try workflow.write(to: tempURL)
        } catch {
            return "Could not save workflow to temporary location: \(error.localizedDescription)"
        }

        let preview = WorkflowPreview(
            title: plan.title,
            steps: stepPreviews,
            tempFileURL: tempURL
        )
        await tracker.setWorkflowPreview(preview)

        // Step 5: Return description for the main session
        var lines = ["Workflow: \"\(plan.title)\"\n\nSteps:"]
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

    // MARK: - Planner

    private func planWorkflow(description: String, catalog: String) async throws -> WorkflowPlan {
        let instructions = """
        You are a workflow planner. Given a catalog of macOS Automator actions and a user's \
        description of what they want, produce a WorkflowPlan with the exact action names \
        from the catalog and any parameter overrides needed.

        Rules:
        - Use ONLY action names that appear in the catalog below. Do not invent names.
        - Order actions so that each action's output type matches the next action's input type.
        - Include parameter overrides only when the user's request specifies values that differ from defaults.
        - For file/folder selection, use "Ask for Finder Items".
        - Keep workflows minimal — only include actions the user asked for.

        CATALOG:
        \(catalog)
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: description,
            generating: WorkflowPlan.self
        )
        return response.content
    }

    // MARK: - Parameter Coercion

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
