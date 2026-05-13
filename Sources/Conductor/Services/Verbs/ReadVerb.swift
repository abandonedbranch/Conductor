import Foundation

enum ReadVerb: VerbDefinition {
    static let verb: Verb = .read
    static let lemmas = ["read", "open", "fetch", "load"]
    static let parameters = [
        VerbParameter(role: "url", kind: .url, aliases: [:], required: true, defaultValue: nil)
    ]
    static let needs: [UpstreamEventNeed] = []

    static func execute(
        resolved: ResolvedInputs,
        origin: Origin,
        http: any HTTPClient,
        llm: any LLMSession
    ) async throws -> [any Event] {
        guard case let .url(url)? = resolved.atoms["url"] else {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "missing url", origin: origin)]
        }
        do {
            let data = try await http.get(url)
            let body = String(data: data, encoding: .utf8) ?? ""
            let title = extractTitle(from: body) ?? url.host ?? url.absoluteString
            let text = stripTags(from: body)
            return [ReadCompleted(body: text, title: title, url: url, origin: origin)]
        } catch {
            return [StepFailed(stepID: origin.stepID ?? UUID(), message: "\(error)", origin: origin)]
        }
    }

    private static func extractTitle(from html: String) -> String? {
        guard let start = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive),
              start.upperBound < end.lowerBound else { return nil }
        return String(html[start.upperBound..<end.lowerBound])
    }

    private static func stripTags(from html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
