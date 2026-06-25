import XCTest
@testable import AnkiAI

/// M4 — real revlog-derived insight metrics (streak, daily reviews, time/card)
/// computed from the backend graph series (no placeholders).
final class StatsGraphsComputeTests: XCTestCase {

    private func g(_ reviews: [(Int, Int)], totalReviews: Int = 0, totalTimeMs: Int = 0) -> StatsGraphs {
        StatsGraphs(reviews: reviews.map { GraphPoint(day: $0.0, count: $0.1) },
                    futureDue: [], added: [], totalReviews: totalReviews, totalTimeMs: totalTimeMs)
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        // 0, -1, -2 studied; gap at -3; -4 studied → streak = 3
        XCTAssertEqual(g([(0, 5), (-1, 3), (-2, 1), (-4, 2)]).streak, 3)
    }

    func testStreakCountsFromYesterdayWhenNotStudiedToday() {
        XCTAssertEqual(g([(-1, 3), (-2, 1)]).streak, 2)
    }

    func testNoStreakWhenLastStudyOlderThanYesterday() {
        XCTAssertEqual(g([(-3, 3), (-4, 2)]).streak, 0)
    }

    func testEmptyHasNoStreakNorTime() {
        let e = g([])
        XCTAssertEqual(e.streak, 0)
        XCTAssertEqual(e.avgSecondsPerCard, 0, accuracy: 0.001)
        XCTAssertEqual(e.avgReviewsPerStudiedDay, 0, accuracy: 0.001)
    }

    func testAverages() {
        let s = g([(0, 10), (-1, 20)], totalReviews: 30, totalTimeMs: 60000)
        XCTAssertEqual(s.avgReviewsPerStudiedDay, 15, accuracy: 0.01)   // 30 / 2 studied days
        XCTAssertEqual(s.avgSecondsPerCard, 2, accuracy: 0.01)          // 60000ms / 1000 / 30
        XCTAssertEqual(s.todayReviews, 10)
    }
}
