import SwiftUI
import WebKit

/// Serves bundled web resources (MathJax) to the WebView over the `appres://`
/// scheme so cards render math fully offline (no CDN). SVG output is used because
/// the `tex-mml-svg.js` build is self-contained (no separate font files).
final class BundleResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let mathjaxData: Data? = {
        guard let url = Bundle.main.url(forResource: "tex-mml-svg", withExtension: "js") else { return nil }
        return try? Data(contentsOf: url)
    }()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let data = Self.mathjaxData else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let resp = URLResponse(url: url, mimeType: "application/javascript",
                               expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Renders Anki card HTML with MathJax, mirroring AnkiDroid's WebView-based
/// rendering. Math uses the `\( \)` / `\[ \]` delimiters the AI prompts enforce.
/// RTL/Hebrew is preserved because the HTML carries its own `dir` attributes.
///
/// When `css` is non-empty (a backend-rendered card's note-type CSS), the body is
/// wrapped in `<div class="card">…</div>` and the CSS is injected — matching how
/// Anki applies note-type styling.
struct CardWebView: UIViewRepresentable {
    let html: String
    var css: String = ""

    /// True when MathJax is bundled in the app → render offline via `appres://`.
    static let hasLocalMathJax = BundleResourceSchemeHandler.mathjaxData != nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if Self.hasLocalMathJax {
            config.setURLSchemeHandler(BundleResourceSchemeHandler(), forURLScheme: "appres")
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrap(html, css: css), baseURL: nil)
    }

    /// Wraps card HTML in a document that loads MathJax v3 configured to use the
    /// same delimiters as the cards. MathJax is served from the app bundle
    /// (`appres://`) for offline rendering, falling back to a CDN only if the
    /// bundled copy is missing.
    static func wrap(_ body: String, css: String = "") -> String {
        let noteCSS = css.isEmpty ? "" : "\n<style>\n\(css)\n</style>"
        let content = css.isEmpty ? body : "<div class=\"card\">\(body)</div>"
        let mathjaxSrc = hasLocalMathJax
            ? "appres://local/tex-mml-svg.js"
            : "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-svg.js"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          body { font-family: -apple-system, sans-serif; font-size: 18px; margin: 16px; color: #1a1a1a; background: transparent; }
          @media (prefers-color-scheme: dark) { body { color: #f2f2f2; } }
        </style>\(noteCSS)
        <script>
          window.MathJax = {
            tex: { inlineMath: [['\\\\(', '\\\\)']], displayMath: [['\\\\[', '\\\\]']] },
            svg: { fontCache: 'global' },
            options: { skipHtmlTags: ['script','noscript','style','textarea','pre'] }
          };
        </script>
        <script src="\(mathjaxSrc)" id="MathJax-script"></script>
        </head>
        <body>
        \(content)
        </body>
        </html>
        """
    }
}
