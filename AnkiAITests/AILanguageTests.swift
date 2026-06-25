import XCTest
@testable import AnkiAI

/// Issue 2 — AI language selection + bidi direction detection (no string reversal).
final class AILanguageTests: XCTestCase {

    func testHebrewModeAlwaysRTLRegardlessOfText() {
        XCTAssertTrue(TextDirection.isRTL(language: .hebrew, text: "all english here"))
        XCTAssertTrue(TextDirection.isRTL(language: .hebrew, text: ""))
    }

    func testEnglishModeAlwaysLTR() {
        XCTAssertFalse(TextDirection.isRTL(language: .english, text: "שלום עולם"))
    }

    func testAutomaticUsesFirstStrongDirection() {
        XCTAssertTrue(TextDirection.isRTL(language: .automatic, text: "שלום world"))
        XCTAssertFalse(TextDirection.isRTL(language: .automatic, text: "hello עולם"))
    }

    func testFirstStrong() {
        XCTAssertTrue(TextDirection.firstStrongIsRTL("מה זה?"))
        XCTAssertFalse(TextDirection.firstStrongIsRTL("What is this?"))
        // Leading neutrals (digits/punctuation) are skipped to the first strong char.
        XCTAssertTrue(TextDirection.firstStrongIsRTL("123. שלום"))
        XCTAssertFalse(TextDirection.firstStrongIsRTL("123. hello"))
    }

    func testNeutralOnlyContentIsLTR() {
        XCTAssertFalse(TextDirection.firstStrongIsRTL("101.1₂"))   // binary number, no strong char
        XCTAssertFalse(TextDirection.firstStrongIsRTL("=== --- +++"))
    }

    func testInlineLatinFormulaIsLTR() {
        XCTAssertFalse(TextDirection.firstStrongIsRTL("E = mc^2"))
    }

    func testPromptInstructionMentionsLanguage() {
        XCTAssertTrue(AILanguage.hebrew.promptInstruction.localizedCaseInsensitiveContains("Hebrew"))
        XCTAssertTrue(AILanguage.english.promptInstruction.localizedCaseInsensitiveContains("English"))
        XCTAssertFalse(AILanguage.automatic.promptInstruction.isEmpty)
    }

    func testLanguagePersistsInSettings() {
        let s = AISettingsStore(keychain: InMemorySecretStore(),
                                defaults: UserDefaults(suiteName: "lang-\(UUID().uuidString)")!)
        XCTAssertEqual(s.aiLanguage, .automatic)
        s.aiLanguage = .hebrew
        XCTAssertEqual(s.aiLanguage, .hebrew)
    }

    func testHebrewPromptKeepsSchemaUnchanged() {
        // The instruction must explicitly tell the model NOT to change JSON keys.
        XCTAssertTrue(AILanguage.hebrew.promptInstruction.localizedCaseInsensitiveContains("JSON"))
    }
}
