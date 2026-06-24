import SwiftUI
import WebKit

/// Renders Anki card HTML with MathJax, mirroring AnkiDroid's WebView-based
/// rendering. Math uses the `\( \)` / `\[ \]` delimiters the AI prompts enforce.
/// RTL/Hebrew is preserved because the HTML carries its own `dir` attributes.
struct CardWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrap(html), baseURL: nil)
    }

    /// Wraps card HTML in a document that loads MathJax v3 locally-configured to
    /// use the same delimiters as the cards. Bundled MathJax is added in a later
    /// slice; for now it loads from a CDN so rendering is correct on a network.
    static func wrap(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          body { font-family: -apple-system, sans-serif; font-size: 18px; margin: 16px; color: #1a1a1a; background: transparent; }
          @media (prefers-color-scheme: dark) { body { color: #f2f2f2; } }
        </style>
        <script>
          window.MathJax = {
            tex: { inlineMath: [['\\\\(', '\\\\)']], displayMath: [['\\\\[', '\\\\]']] },
            options: { skipHtmlTags: ['script','noscript','style','textarea','pre'] }
          };
        </script>
        <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js"></script>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
