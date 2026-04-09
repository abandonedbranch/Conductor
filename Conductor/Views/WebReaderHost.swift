import SwiftUI
import WebKit

#if os(macOS)
struct WebReaderHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct WebReaderHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
