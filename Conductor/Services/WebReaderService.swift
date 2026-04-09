import Foundation
import WebKit

@MainActor
final class WebReaderService: NSObject, WKNavigationDelegate {

    static nonisolated let extractionScript = """
    (() => {
        const title = document.title || '';
        const text = document.body.innerText || '';
        return JSON.stringify({ title: title, text: text });
    })()
    """

    static nonisolated let timeoutInterval: TimeInterval = 30

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WebReaderResult, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var currentURL: URL?

    func read(url: URL) async throws -> WebReaderResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.currentURL = url

            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            let request = URLRequest(url: url)
            wv.load(request)

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeoutInterval))
                guard !Task.isCancelled else { return }
                self?.failWithTimeout()
            }
        }
    }

    private func failWithTimeout() {
        guard let continuation else { return }
        cleanup()
        continuation.resume(throwing: WebReaderError.timeout(Self.timeoutInterval))
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation = nil
        currentURL = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.extractionScript) { [weak self] result, error in
            guard let self, let continuation = self.continuation else { return }

            if let error {
                let url = self.currentURL ?? URL(string: "about:blank")!
                self.cleanup()
                continuation.resume(throwing: WebReaderError.extractionFailed(url))
                return
            }

            guard let jsonString = result as? String else {
                let url = self.currentURL ?? URL(string: "about:blank")!
                self.cleanup()
                continuation.resume(throwing: WebReaderError.extractionFailed(url))
                return
            }

            do {
                let parsed = try Self.parseExtraction(jsonString)
                let webResult = WebReaderResult(
                    url: self.currentURL ?? URL(string: "about:blank")!,
                    title: parsed.title,
                    text: parsed.text
                )
                self.cleanup()
                continuation.resume(returning: webResult)
            } catch {
                let url = self.currentURL ?? URL(string: "about:blank")!
                self.cleanup()
                continuation.resume(throwing: WebReaderError.extractionFailed(url))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard let continuation else { return }
        let urlError = (error as? URLError)?.code ?? .unknown
        cleanup()
        continuation.resume(throwing: WebReaderError.navigationFailed(urlError))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard let continuation else { return }
        let urlError = (error as? URLError)?.code ?? .unknown
        cleanup()
        continuation.resume(throwing: WebReaderError.navigationFailed(urlError))
    }

    // MARK: - Extraction Parsing

    struct ExtractionPayload: Decodable, Sendable {
        let title: String
        let text: String
    }

    static nonisolated func parseExtraction(_ jsonString: String) throws -> ExtractionPayload {
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(ExtractionPayload.self, from: data)
    }
}
