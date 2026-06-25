import XCTest
@testable import AnkiAI

/// M2.24: the pure media-rewriting used by CardWebView to resolve `<img>` and
/// `[sound:]` references against the collection's media folder.
final class CardWebViewMediaTests: XCTestCase {

    func testRelativeImageIsRewrittenToMediaScheme() {
        let out = CardWebView.rewriteMedia(#"<img src="cat.jpg">"#)
        XCTAssertTrue(out.contains(#"src="appres://media/cat.jpg""#), out)
    }

    func testAbsoluteImageIsLeftAlone() {
        let https = CardWebView.rewriteMedia(#"<img src="https://example.com/a.png">"#)
        XCTAssertTrue(https.contains("https://example.com/a.png"))
        XCTAssertFalse(https.contains("appres://"))
        let data = CardWebView.rewriteMedia(#"<img src="data:image/png;base64,AAAA">"#)
        XCTAssertTrue(data.contains("data:image/png"))
        XCTAssertFalse(data.contains("appres://"))
    }

    func testSoundTagBecomesAudioPlayer() {
        let out = CardWebView.rewriteMedia("listen [sound:hello.mp3] now")
        XCTAssertTrue(out.contains(#"<audio controls src="appres://media/hello.mp3">"#), out)
        XCTAssertFalse(out.contains("[sound:"))
    }

    func testFilenameWithSpaceIsPercentEncoded() {
        let out = CardWebView.rewriteMedia(#"<img src="my pic.jpg">"#)
        XCTAssertTrue(out.contains("appres://media/my%20pic.jpg"), out)
    }

    func testNonMediaHtmlUnchanged() {
        let html = "<b>שלום</b> \\(x^2\\)"
        XCTAssertEqual(CardWebView.rewriteMedia(html), html)
    }
}
