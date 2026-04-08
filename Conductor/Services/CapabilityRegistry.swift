import Foundation

struct CapabilityRequest: Sendable {
    let userMessage: String
    let extractedGoal: String
    let parameters: [String: String]?
}

struct Capability: Sendable {
    let id: String
    let name: String
    let description: String
    let keywords: [String]
    let execute: @Sendable (CapabilityRequest) async -> String
}

struct ScoredCapability: Sendable {
    let capability: Capability
    let score: Int
}

actor CapabilityRegistry {
    private var capabilities: [Capability]

    init(capabilities: [Capability] = []) {
        self.capabilities = capabilities
    }

    func register(_ capability: Capability) {
        capabilities.append(capability)
    }

    func search(query: String, maxResults: Int) -> [ScoredCapability] {
        let queryLower = query.lowercased()
        guard !queryLower.isEmpty else {
            return []
        }

        let terms = queryLower.split(separator: " ").map(String.init)
        var scored: [ScoredCapability] = []

        for capability in capabilities {
            var score = 0
            let nameLower = capability.name.lowercased()
            let descLower = capability.description.lowercased()
            let kwLower = capability.keywords.map { $0.lowercased() }

            for term in terms {
                if nameLower.contains(term) { score += 3 }
                if kwLower.contains(where: { $0.contains(term) }) { score += 2 }
                if descLower.contains(term) { score += 1 }
            }

            if score > 0 {
                scored.append(ScoredCapability(capability: capability, score: score))
            }
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(maxResults))
    }
}
