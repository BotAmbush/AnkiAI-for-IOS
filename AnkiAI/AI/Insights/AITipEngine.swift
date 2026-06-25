import Foundation

/// Per-deck retention summary. Mirrors `analytics/RevlogAnalyzer.kt` `DeckRetention`.
public struct DeckRetention: Equatable, Sendable {
    public let deckId: Int64
    public let deckName: String
    public let retention: Float
    public let reviewCount: Int
    public init(deckId: Int64, deckName: String, retention: Float, reviewCount: Int) {
        self.deckId = deckId
        self.deckName = deckName
        self.retention = retention
        self.reviewCount = reviewCount
    }
}

/// Aggregate stats feeding the tip engine. Mirrors `insights/AiTipEngine.kt` `InsightStats`.
public struct InsightStats: Equatable, Sendable {
    public let streak: Int
    public let todayCount: Int
    public let retention30d: Float
    public let weakCardCount: Int
    public let avgEaseFactor: Float
    public let avgDailyReviews: Float
    public let matureCards: Int
    public let totalCards: Int
    public let worstDeck: DeckRetention?
    public let deckRetentions: [DeckRetention]
    public let avgSecPerCard: Float

    public init(streak: Int, todayCount: Int, retention30d: Float, weakCardCount: Int,
                avgEaseFactor: Float, avgDailyReviews: Float, matureCards: Int, totalCards: Int,
                worstDeck: DeckRetention?, deckRetentions: [DeckRetention], avgSecPerCard: Float) {
        self.streak = streak
        self.todayCount = todayCount
        self.retention30d = retention30d
        self.weakCardCount = weakCardCount
        self.avgEaseFactor = avgEaseFactor
        self.avgDailyReviews = avgDailyReviews
        self.matureCards = matureCards
        self.totalCards = totalCards
        self.worstDeck = worstDeck
        self.deckRetentions = deckRetentions
        self.avgSecPerCard = avgSecPerCard
    }
}

public struct AITip: Equatable, Identifiable {
    public let id = UUID()
    public let icon: String
    public let message: String
    public let priority: Int
}

/// Pure port of `AiTipEngine.generateTips`. Returns the top 5 tips by priority.
/// Message strings use English text; localization is wired through `Localized`.
public enum AITipEngine {
    /// `includeStreak`: the streak tip needs a consecutive-day count from the
    /// revlog, which card-search cannot provide; callers without revlog access
    /// pass `false` to omit it rather than show a misleading number.
    public static func generateTips(_ stats: InsightStats, includeStreak: Bool = true) -> [AITip] {
        var tips: [AITip] = []

        // Streak
        if includeStreak {
            switch stats.streak {
            case 0: tips.append(AITip(icon: "⚠️", message: L.streakZero, priority: 10))
            case 1: tips.append(AITip(icon: "🌱", message: L.streakOne, priority: 5))
            case 2...6: tips.append(AITip(icon: "🔥", message: L.streakFew(stats.streak), priority: 4))
            case 7...29: tips.append(AITip(icon: "🏆", message: L.streakWeek(stats.streak), priority: 3))
            default: tips.append(AITip(icon: "🌟", message: L.streakMonth(stats.streak), priority: 2))
            }
        }

        // Retention
        let retPct = Int(stats.retention30d * 100)
        switch stats.retention30d {
        case ..<0.60: tips.append(AITip(icon: "📉", message: L.retentionLow(retPct), priority: 9))
        case 0.60..<0.75: tips.append(AITip(icon: "📊", message: L.retentionMedium(retPct), priority: 6))
        case 0.75..<0.90: tips.append(AITip(icon: "✅", message: L.retentionGood(retPct), priority: 1))
        default: tips.append(AITip(icon: "💡", message: L.retentionHigh(retPct), priority: 2))
        }

        // Weak cards
        if stats.weakCardCount > 0 {
            let msg: String
            if stats.weakCardCount > 50 { msg = L.weakMany(stats.weakCardCount) }
            else if stats.weakCardCount > 10 { msg = L.weakSome(stats.weakCardCount) }
            else { msg = L.weakFew(stats.weakCardCount) }
            tips.append(AITip(icon: "⚡", message: msg, priority: 7))
        }

        // Ease factor
        if stats.avgEaseFactor < 1800 {
            tips.append(AITip(icon: "🎯", message: L.easeLow(Int(stats.avgEaseFactor / 10)), priority: 8))
        }

        // Today vs average
        if stats.avgDailyReviews > 0 {
            let ratio = Float(stats.todayCount) / stats.avgDailyReviews
            if ratio >= 1.5 {
                tips.append(AITip(icon: "🚀", message: L.todayHigh(stats.todayCount, Int((ratio - 1) * 100)), priority: 3))
            } else if ratio < 0.3 && stats.todayCount > 0 {
                tips.append(AITip(icon: "📅", message: L.todayLow, priority: 5))
            }
        }

        // Worst deck
        if let worst = stats.worstDeck, worst.retention < 0.65 {
            tips.append(AITip(icon: "📚", message: L.deckWeak(worst.deckName, Int(worst.retention * 100)), priority: 8))
        }

        // Mature milestone
        let maturePct = stats.totalCards > 0 ? Int(Float(stats.matureCards) / Float(stats.totalCards) * 100) : 0
        if maturePct >= 80 { tips.append(AITip(icon: "🎓", message: L.matureHigh(maturePct), priority: 1)) }
        else if maturePct >= 50 { tips.append(AITip(icon: "📈", message: L.matureHalf, priority: 2)) }
        else if maturePct < 20 && stats.totalCards > 50 { tips.append(AITip(icon: "🌱", message: L.matureLow, priority: 4)) }

        // Time per card
        if stats.avgSecPerCard > 60 {
            tips.append(AITip(icon: "⏱️", message: L.timeLong(Int(stats.avgSecPerCard)), priority: 6))
        }

        return tips.sorted { $0.priority > $1.priority }.prefix(5).map { $0 }
    }

    /// Tip copy. Mirrors `ai_strings.xml` keys (English values); RTL/Hebrew added in localization milestone.
    private enum L {
        static let streakZero = "No streak yet — review a card today to start one."
        static let streakOne = "Day 1 — you started a streak. Keep it going tomorrow."
        static func streakFew(_ d: Int) -> String { "\(d)-day streak — building momentum." }
        static func streakWeek(_ d: Int) -> String { "\(d)-day streak — great consistency!" }
        static func streakMonth(_ d: Int) -> String { "\(d)-day streak — outstanding discipline!" }
        static func retentionLow(_ p: Int) -> String { "Retention is \(p)% (last 30 days). Consider shorter cards or more reviews." }
        static func retentionMedium(_ p: Int) -> String { "Retention is \(p)% — room to improve." }
        static func retentionGood(_ p: Int) -> String { "Retention is \(p)% — solid." }
        static func retentionHigh(_ p: Int) -> String { "Retention is \(p)% — excellent recall." }
        static func weakMany(_ n: Int) -> String { "\(n) weak cards need attention." }
        static func weakSome(_ n: Int) -> String { "\(n) weak cards to review." }
        static func weakFew(_ n: Int) -> String { "\(n) weak card(s) flagged." }
        static func easeLow(_ p: Int) -> String { "Average ease is \(p)% — cards may be too hard." }
        static func todayHigh(_ c: Int, _ p: Int) -> String { "\(c) reviews today — \(p)% above your average!" }
        static let todayLow = "Light day so far — a few more reviews keep you on track."
        static func deckWeak(_ name: String, _ p: Int) -> String { "Deck \"\(name)\" retention is \(p)% — needs focus." }
        static func matureHigh(_ p: Int) -> String { "\(p)% of your cards are mature — well learned!" }
        static let matureHalf = "Over half your cards are mature — great progress."
        static let matureLow = "Most cards are still young — keep reviewing to mature them."
        static func timeLong(_ s: Int) -> String { "Averaging \(s)s per card — consider simpler cards." }
    }
}
