import XCTest
@testable import AnkiAI

/// Issue 3 — AnkiWeb auth state: demo/seeded is never "authenticated"; Logout
/// immediately clears the session; the local collection is untouched.
final class AnkiWebAuthStateTests: XCTestCase {

    private func store() -> AISettingsStore {
        AISettingsStore(keychain: InMemorySecretStore(),
                        defaults: UserDefaults(suiteName: "auth-\(UUID().uuidString)")!)
    }

    func testNotLoggedInByDefault() {
        XCTAssertFalse(store().isAnkiWebLoggedIn, "a fresh/demo install is not authenticated")
    }

    func testLoginRequiresANonEmptySessionKey() {
        let s = store()
        s.ankiWebHKey = ""          // empty is not a valid session
        XCTAssertFalse(s.isAnkiWebLoggedIn)
        s.ankiWebHKey = "real-session-key"
        XCTAssertTrue(s.isAnkiWebLoggedIn)
    }

    func testLogOutClearsSessionUsernameAndBgState() {
        let s = store()
        s.ankiWebHKey = "k"; s.ankiWebUsername = "me@example.com"; s.lastBackgroundSyncResult = "err"
        XCTAssertTrue(s.isAnkiWebLoggedIn)
        s.logOutAnkiWeb()
        XCTAssertFalse(s.isAnkiWebLoggedIn)
        XCTAssertNil(s.ankiWebHKey)
        XCTAssertNil(s.ankiWebUsername)
        XCTAssertNil(s.lastBackgroundSyncResult)
    }

    func testLogOutDoesNotTouchApiKeyOrCollectionProvenance() {
        let s = store()
        s.ankiWebHKey = "k"; s.apiKey = "sk-ant-test"; s.collectionProvenance = .downloadedFromAnkiWeb
        s.logOutAnkiWeb()
        XCTAssertEqual(s.apiKey, "sk-ant-test", "logout must not remove the Claude key")
        XCTAssertEqual(s.collectionProvenance, .downloadedFromAnkiWeb, "logout must not touch the collection")
    }
}
