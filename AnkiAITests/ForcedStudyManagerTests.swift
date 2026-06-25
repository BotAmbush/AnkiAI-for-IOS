import XCTest
@testable import AnkiAI

/// M2.28: forced-study due/snooze/complete logic.
@MainActor
final class ForcedStudyManagerTests: XCTestCase {

    private func freshStore() -> ForcedStudyStore {
        let suite = UserDefaults(suiteName: "fs-test-\(UUID().uuidString)")!
        return ForcedStudyStore(defaults: suite)
    }

    func testNotDueWhenDisabled() {
        let store = freshStore()
        store.isEnabled = false
        let m = ForcedStudyManager(store: store)
        XCTAssertFalse(m.sessionDue)
    }

    func testDueAfterInterval() {
        let store = freshStore()
        store.isEnabled = true
        store.intervalMinutes = 60
        store.lastCompleted = Date().addingTimeInterval(-2 * 3600) // 2h ago
        let m = ForcedStudyManager(store: store)
        XCTAssertTrue(m.sessionDue, "session is due after the interval elapsed")
    }

    func testNotDueWithinInterval() {
        let store = freshStore()
        store.isEnabled = true
        store.intervalMinutes = 60
        store.lastCompleted = Date().addingTimeInterval(-5 * 60) // 5 min ago
        let m = ForcedStudyManager(store: store)
        XCTAssertFalse(m.sessionDue)
    }

    func testSnoozePostponesAndCounts() {
        let store = freshStore()
        store.isEnabled = true
        store.intervalMinutes = 60
        store.snoozeEnabled = true
        store.maxSnoozes = 2
        store.snoozeDurationMin = 10
        store.lastCompleted = Date().addingTimeInterval(-2 * 3600)
        let m = ForcedStudyManager(store: store)
        XCTAssertTrue(m.sessionDue)
        XCTAssertTrue(m.canSnooze)
        m.snooze()
        XCTAssertFalse(m.sessionDue)
        XCTAssertEqual(store.snoozesUsed, 1)
    }

    func testCompleteResetsAndClearsDue() {
        let store = freshStore()
        store.isEnabled = true
        store.intervalMinutes = 60
        store.lastCompleted = Date().addingTimeInterval(-2 * 3600)
        let m = ForcedStudyManager(store: store)
        XCTAssertTrue(m.sessionDue)
        m.complete()
        XCTAssertFalse(m.sessionDue)
        XCTAssertEqual(store.snoozesUsed, 0)
        m.refresh()
        XCTAssertFalse(m.sessionDue, "not due again right after completing")
    }
}
