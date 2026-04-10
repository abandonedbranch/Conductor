import Foundation
import Testing
@testable import Conductor

@Suite("AgentPurpose Tests")
struct AgentPurposeTests {

    @Test("Each purpose has a display color")
    func purposeHasColor() {
        for purpose in AgentPurpose.allCases {
            _ = purpose.displayColor
        }
    }

    @Test("Each purpose has a section heading")
    func purposeHasSectionHeading() {
        #expect(AgentPurpose.overview.sectionHeading == "Overview")
        #expect(AgentPurpose.research.sectionHeading == "Research Findings")
        #expect(AgentPurpose.web.sectionHeading == "Web Content")
        #expect(AgentPurpose.build.sectionHeading == "Workflow")
    }

    @Test("Each purpose has an agent description")
    func purposeHasAgentDescription() {
        for purpose in AgentPurpose.allCases {
            #expect(!purpose.agentDescription.isEmpty)
        }
    }

    @Test("Each purpose has a narration prefix")
    func purposeHasNarrationPrefix() {
        for purpose in AgentPurpose.allCases {
            #expect(!purpose.narrationPrefix.isEmpty)
        }
    }

    @Test("Raw values are stable strings")
    func rawValues() {
        #expect(AgentPurpose.overview.rawValue == "overview")
        #expect(AgentPurpose.research.rawValue == "research")
        #expect(AgentPurpose.web.rawValue == "web")
        #expect(AgentPurpose.build.rawValue == "build")
    }
}
