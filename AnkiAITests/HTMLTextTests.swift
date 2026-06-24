import XCTest
@testable import AnkiAI

final class HTMLTextTests: XCTestCase {

    func testStripHTMLBasic() {
        let input = #"<div dir="rtl"><b>שלום</b>&nbsp;world</div>"#
        XCTAssertEqual(HTMLText.stripHTML(input), "שלום world")
    }

    func testStripHTMLEntities() {
        XCTAssertEqual(HTMLText.stripHTML("a &lt;b&gt; &amp; c"), "a <b> & c")
    }

    func testMathAwareInlineMath() {
        let input = #"energy <span dir="ltr">\(E=mc^2\)</span> here"#
        XCTAssertEqual(HTMLText.mathAwareStripHTML(input), "energy [math: E=mc^2] here")
    }

    func testMathAwareBlockMath() {
        let input = #"<div>\[p=\hbar k\]</div>"#
        XCTAssertEqual(HTMLText.mathAwareStripHTML(input), "[math: p=\\hbar k]")
    }

    func testMathAwareAnkiMathjaxTag() {
        let input = "<anki-mathjax>x^2</anki-mathjax>"
        XCTAssertEqual(HTMLText.mathAwareStripHTML(input), "[math: x^2]")
    }

    func testHebrewPreserved() {
        let input = #"<div dir="rtl" style="text-align: right;"><b>מהי קבוע פלאנק?</b></div>"#
        XCTAssertEqual(HTMLText.stripHTML(input), "מהי קבוע פלאנק?")
    }
}
