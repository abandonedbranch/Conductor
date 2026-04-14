import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol AgentTool: Tool, AffordanceBearing {
    var friendlyName: String { get }
    // Retained until Task 28 removes the legacy ConductorOrchestrator
    // dispatcher that filters by `purpose`. New routing uses `affordance`.
    var purpose: AgentPurpose { get }
}
