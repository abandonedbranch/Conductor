import Foundation

struct StitchedResponse: Sendable {
    let sections: [ResponseSection]

    struct ResponseSection: Sendable {
        let heading: String
        let content: String
        let sources: [ToolSource]
    }

    var formatted: String {
        sections.map { section in
            "## \(section.heading)\n\n\(section.content)"
        }.joined(separator: "\n\n")
    }
}

extension TaskGraph {
    func stitch() -> StitchedResponse {
        let ordered = topologicalSort()
        let sections = ordered
            .filter { $0.status == .completed }
            .map { node in
                StitchedResponse.ResponseSection(
                    heading: node.purpose.sectionHeading,
                    content: node.entries.map(\.content).joined(separator: "\n\n"),
                    sources: node.entries.compactMap { entry in
                        entry.sourceURL.map { ToolSource(title: entry.toolName, url: $0) }
                    }
                )
            }
        return StitchedResponse(sections: sections)
    }
}
