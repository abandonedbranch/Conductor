import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol AgentTool: Tool, AffordanceBearing {
    var friendlyName: String { get }
}
