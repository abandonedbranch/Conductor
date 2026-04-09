import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
struct WebReaderTool: BadgedTool {
    let name = "readWeb"
    let description = "Read a web page and extract its text content. Call when the user provides a URL they want to read, analyze, or summarize."
    let badge = ToolBadge(icon: "globe", tint: .purple, label: "Web")

    let tracker: ToolUsageTracker

    @Generable
    struct Arguments {
        @Guide(description: "The full URL of the web page to read (must be HTTPS)")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        await tracker.record(badge)

        let url = try validateAndUnwrap(arguments.url)

        let service = await WebReaderService()
        let result = try await service.read(url: url)

        await tracker.addSource(ToolSource(title: result.title, url: result.url.absoluteString))

        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WebReaderError.emptyContent(url)
        }

        return result.text
    }

    private func validateAndUnwrap(_ urlString: String) throws -> URL {
        switch Self.validateURL(urlString) {
        case .success(let url):
            return url
        case .failure(let error):
            throw error
        }
    }

    static func validateURL(_ urlString: String) -> Result<URL, WebReaderError> {
        WebReaderError.validate(urlString: urlString)
    }
}
