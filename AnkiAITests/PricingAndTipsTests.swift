import XCTest
@testable import AnkiAI

final class PricingAndTipsTests: XCTestCase {

    func testHaikuPricing() {
        // 1000 input + 500 output tokens
        let cost = AIPricing.costHaiku(input: 1000, output: 500)
        XCTAssertEqual(cost, 1000 * 0.0000008 + 500 * 0.000004, accuracy: 1e-12)
    }

    func testSonnetPricing() {
        let cost = AIPricing.costSonnet(input: 2000, output: 1000)
        XCTAssertEqual(cost, 2000 * 0.000003 + 1000 * 0.000015, accuracy: 1e-12)
    }

    func testErrorMessages() {
        XCTAssertEqual(AIErrorPresenter.message(for: .noInternet), "No internet connection.")
        XCTAssertTrue(AIErrorPresenter.message(for: .unauthorized).contains("Invalid API key"))
        XCTAssertTrue(AIErrorPresenter.message(for: .rateLimited).contains("Rate limit"))
        XCTAssertTrue(AIErrorPresenter.message(for: .overloaded).contains("overloaded"))
    }

    func testTipEngineCapsAtFive() {
        let tips = AITipEngine.generateTips(InsightsViewSampleProvider.stats)
        XCTAssertLessThanOrEqual(tips.count, 5)
    }

    func testTipEngineStreakZeroIsHighestPriority() {
        let stats = InsightStats(streak: 0, todayCount: 0, retention30d: 0.8, weakCardCount: 0,
                                 avgEaseFactor: 2500, avgDailyReviews: 0, matureCards: 0, totalCards: 0,
                                 worstDeck: nil, deckRetentions: [], avgSecPerCard: 0)
        let tips = AITipEngine.generateTips(stats)
        XCTAssertEqual(tips.first?.icon, "⚠️")
    }

    func testTipEngineSortedByPriorityDescending() {
        let tips = AITipEngine.generateTips(InsightsViewSampleProvider.stats)
        let priorities = tips.map { $0.priority }
        XCTAssertEqual(priorities, priorities.sorted(by: >))
    }

    // Repair 5 — no fabricated retention advice when review data is missing.
    private let retentionIcons = ["📉", "📊", "✅", "💡"]

    func testNoRetentionTipWhenRetentionDataMissing() {
        let stats = InsightStats(streak: 3, todayCount: 0, retention30d: nil, weakCardCount: 0,
                                 avgEaseFactor: 2500, avgDailyReviews: 0, matureCards: 0, totalCards: 100,
                                 worstDeck: nil, deckRetentions: [], avgSecPerCard: 0)
        let tips = AITipEngine.generateTips(stats)
        XCTAssertFalse(tips.contains { retentionIcons.contains($0.icon) }, "no retention tip on nil data")
    }

    func testRetentionTipShownWhenRealDataExists() {
        let stats = InsightStats(streak: 3, todayCount: 0, retention30d: 0.5, weakCardCount: 0,
                                 avgEaseFactor: 2500, avgDailyReviews: 0, matureCards: 0, totalCards: 100,
                                 worstDeck: nil, deckRetentions: [], avgSecPerCard: 0)
        let tips = AITipEngine.generateTips(stats)
        XCTAssertTrue(tips.contains { retentionIcons.contains($0.icon) }, "low retention tip on real data")
    }
}

/// Sample stats mirror of `InsightsView.sampleStats` for use in tests.
enum InsightsViewSampleProvider {
    static let stats = InsightStats(
        streak: 5, todayCount: 42, retention30d: 0.82, weakCardCount: 14,
        avgEaseFactor: 2100, avgDailyReviews: 30, matureCards: 320, totalCards: 540,
        worstDeck: DeckRetention(deckId: 3, deckName: "Physics::Quantum", retention: 0.58, reviewCount: 40),
        deckRetentions: [], avgSecPerCard: 18)
}
