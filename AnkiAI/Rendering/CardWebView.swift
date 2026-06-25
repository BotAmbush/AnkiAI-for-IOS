import SwiftUI
import WebKit

/// Serves app-local resources to the WebView over the `appres://` scheme:
///  - `appres://*/tex-mml-svg.js` → the bundled MathJax (offline math, SVG build);
///  - `appres://media/<file>`     → a file from the collection's media folder
///    (so `<img>` and `[sound:]` references render after a media sync).
final class AppResSchemeHandler: NSObject, WKURLSchemeHandler {
    let mediaDirectory: URL?
    init(mediaDirectory: URL?) { self.mediaDirectory = mediaDirectory }

    static let mathjaxData: Data? = {
        guard let url = Bundle.main.url(forResource: "tex-mml-svg", withExtension: "js") else { return nil }
        return try? Data(contentsOf: url)
    }()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        if url.host == "media", let dir = mediaDirectory {
            guard let fileURL = Self.mediaFileURL(in: dir, requestURL: url),
                  let data = try? Data(contentsOf: fileURL) else {
                task.didFailWithError(URLError(.fileDoesNotExist)); return
            }
            respond(task, url: url, data: data, mime: Self.mime(forExtension: fileURL.pathExtension))
            return
        }
        if let data = Self.mathjaxData {
            respond(task, url: url, data: data, mime: "application/javascript")
        } else {
            task.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let resp = URLResponse(url: url, mimeType: mime,
                               expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Resolve an `appres://media/<name>` request to a file STRICTLY inside `dir`.
    /// Guards against path traversal: the request's last path component is taken
    /// (so embedded `/` and `..` segments are dropped) and the resolved path is
    /// verified to remain within the media folder. Returns nil if it would escape
    /// or the name is empty. Pure + testable.
    static func mediaFileURL(in dir: URL, requestURL: URL) -> URL? {
        let raw = requestURL.lastPathComponent
        let name = raw.removingPercentEncoding ?? raw
        // Reject empties and anything that still tries to traverse.
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else { return nil }
        let base = dir.standardizedFileURL
        let candidate = base.appendingPathComponent(name).standardizedFileURL
        // Final containment check: the candidate must sit directly under base.
        guard candidate.deletingLastPathComponent().standardizedFileURL.path == base.path else {
            return nil
        }
        return candidate
    }

    static func mime(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "mp3": return "audio/mpeg"
        case "ogg", "oga": return "audio/ogg"
        case "wav": return "audio/wav"
        case "m4a", "aac": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
}

/// Renders Anki card HTML with MathJax + media, mirroring AnkiDroid's WebView
/// rendering. Math uses the `\( \)` / `\[ \]` delimiters the AI prompts enforce.
/// RTL/Hebrew is preserved because the HTML carries its own `dir` attributes.
///
/// When `css` is non-empty (a backend-rendered card's note-type CSS), the body is
/// wrapped in `<div class="card">…</div>` and the CSS is injected — matching how
/// Anki applies note-type styling. When `mediaDirectory` is set, `<img>` and
/// `[sound:]` references are rewritten to the `appres://media/` scheme.
struct CardWebView: UIViewRepresentable {
    let html: String
    var css: String = ""
    var mediaDirectory: URL? = nil

    /// True when MathJax is bundled in the app → render offline via `appres://`.
    static let hasLocalMathJax = AppResSchemeHandler.mathjaxData != nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Register the handler whenever MathJax is bundled or media is available.
        if Self.hasLocalMathJax || mediaDirectory != nil {
            config.setURLSchemeHandler(AppResSchemeHandler(mediaDirectory: mediaDirectory), forURLScheme: "appres")
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrap(html, css: css, rewriteMedia: mediaDirectory != nil), baseURL: nil)
    }

    static func wrap(_ body: String, css: String = "", rewriteMedia: Bool = false) -> String {
        let noteCSS = css.isEmpty ? "" : "\n<style>\n\(css)\n</style>"
        let processed = rewriteMedia ? self.rewriteMedia(body) : body
        let content = css.isEmpty ? processed : "<div class=\"card\">\(processed)</div>"
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
          img { max-width: 100%; height: auto; }
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

    /// Rewrites relative `<img src="x">` and `[sound:x]` references to the
    /// `appres://media/` scheme so they load from the collection's media folder.
    /// Absolute URLs (http(s)/data/appres) are left untouched. Pure + testable.
    static func rewriteMedia(_ html: String) -> String {
        var out = html
        // [sound:file] → an inline audio player.
        out = replace(out, pattern: "\\[sound:([^\\]]+)\\]") { name in
            "<audio controls src=\"appres://media/\(encode(name))\"></audio>"
        }
        // <img ... src="file" ...> → rewrite the src if it's a relative filename.
        out = rewriteImgSrc(out)
        return out
    }

    private static func rewriteImgSrc(_ html: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(<img[^>]*?\\ssrc=\")([^\"]+)(\")",
                                                options: [.caseInsensitive]) else { return html }
        let ns = html as NSString
        var result = ""
        var last = 0
        re.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let pre = ns.substring(with: m.range(at: 1))
            let src = ns.substring(with: m.range(at: 2))
            let post = ns.substring(with: m.range(at: 3))
            let newSrc = isAbsolute(src) ? src : "appres://media/\(encode(src))"
            result += pre + newSrc + post
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func isAbsolute(_ src: String) -> Bool {
        let s = src.lowercased()
        return s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("data:")
            || s.hasPrefix("appres://") || s.hasPrefix("//")
    }

    private static func encode(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }

    private static func replace(_ s: String, pattern: String, _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        re.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let captured = m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range)
            result += transform(captured)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
