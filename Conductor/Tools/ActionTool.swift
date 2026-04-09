import Foundation
import FoundationModels

// MARK: - Errors

struct VagueIntentError: Error {
    let matchCount: Int
}

// MARK: - Resolution Result (for testing)

enum ActionResult: Sendable {
    case executed(String)
    case noMatch(String)
    case vagueIntent(Int)
}

// MARK: - Resolution Logic

enum ActionResolver {
    static func resolve(userMessage: String, registry: CapabilityRegistry) async -> ActionResult {
        let matches = await registry.search(query: userMessage, maxResults: 5)

        guard !matches.isEmpty else {
            return .noMatch("No program exists to fulfill this request.")
        }

        if matches.count > 1 {
            // Execute only if the top match is clearly dominant (2x the second score)
            if matches[0].score >= matches[1].score * 2 {
                let request = CapabilityRequest(
                    userMessage: userMessage,
                    extractedGoal: userMessage,
                    parameters: nil
                )
                let output = await matches[0].capability.execute(request)
                return .executed(output)
            }
            return .vagueIntent(matches.count)
        }

        let request = CapabilityRequest(
            userMessage: userMessage,
            extractedGoal: userMessage,
            parameters: nil
        )
        let output = await matches[0].capability.execute(request)
        return .executed(output)
    }
}

// MARK: - ActionTool

@available(iOS 19.0, macOS 26.0, *)
struct ActionTool: Tool {
    let name = "action"
    let description = "Execute a device capability. Call when the user wants to do something — build, create, convert, run."
    let registry: CapabilityRegistry
    let tracker: ToolUsageTracker

    @Generable
    struct Arguments {
        @Guide(description: "The user's message describing what they want to do")
        var userMessage: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = await Self.resolve(userMessage: arguments.userMessage, registry: registry)
        switch result {
        case .executed(let output):
            return output
        case .noMatch(let message):
            return message
        case .vagueIntent(let count):
            throw VagueIntentError(matchCount: count)
        }
    }

    static func resolve(userMessage: String, registry: CapabilityRegistry) async -> ActionResult {
        await ActionResolver.resolve(userMessage: userMessage, registry: registry)
    }
}
