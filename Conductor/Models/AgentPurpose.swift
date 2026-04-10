import SwiftUI

enum AgentPurpose: String, Codable, CaseIterable, Sendable {
    case overview
    case research
    case web
    case build

    var displayColor: Color {
        switch self {
        case .overview: return .orange
        case .research: return .blue
        case .web:      return .purple
        case .build:    return .gray
        }
    }

    var sectionHeading: String {
        switch self {
        case .overview: return "Overview"
        case .research: return "Research Findings"
        case .web:      return "Web Content"
        case .build:    return "Workflow"
        }
    }

    var agentDescription: String {
        switch self {
        case .overview: return "a research assistant gathering background context"
        case .research: return "a research assistant finding authoritative sources"
        case .web:      return "a web reader extracting page content"
        case .build:    return "a workflow builder creating automations"
        }
    }

    var narrationPrefix: String {
        switch self {
        case .overview: return "Looking up background information"
        case .research: return "Searching research databases"
        case .web:      return "Reading web page"
        case .build:    return "Building workflow"
        }
    }
}
