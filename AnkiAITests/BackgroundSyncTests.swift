import XCTest
@testable import AnkiAI

/// M2.31: background sync must fail quietly and do nothing when logged out.
final class BackgroundSyncTests: XCTestCase {

    func testTaskIdentifierMatchesInfoPlist() {
        XCTAssertEqual(BackgroundSync.taskId, "com.evyatar.ankiai.sync")
    }

    func testNoOpWhenLoggedOut() async {
        // No session key → returns immediately without touching the network or files.
        await BackgroundSync.run(hkey: nil, collectionPath: "/nonexistent/collection.anki2")
        await BackgroundSync.run(hkey: "", collectionPath: "/nonexistent/collection.anki2")
        // Reaching here without a crash/hang is the assertion.
    }
}
