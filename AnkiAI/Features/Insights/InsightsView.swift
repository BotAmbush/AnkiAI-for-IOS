import SwiftUI

/// AI Insights dashboard. Mirrors `AiInsightsDashboardFragment` — surfaces
/// study-pattern tips from `AITipEngine`. Live stats come from the revlog
/// analyzer once the backend is connected (milestone 2); milestone 1 shows the
/// engine working against representative sample stats.
struct InsightsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var tips: [AITip] = []
    @State private var stats: CollectionStats?

    var body: some View {
        NavigationStack {
            List {
                Section("Collection") {
                    if let stats {
                        statRow("Total cards", stats.total)
                        statRow("New", stats.newCount, .blue)
                        statRow("Learning", stats.learning, .red)
                        statRow("Review (due)", stats.review, .green)
                        statRow("Mature (≥21d)", stats.mature)
                        statRow("Suspended", stats.suspended)
                    } else {
                        ProgressView()
                    }
                }
                Section {
                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Text(tip.icon).font(.title2)
                            Text(tip.message)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("AI tips")
                } footer: {
                    Text("Live from your collection: card counts, weak cards (≥3 lapses), today's reviews, and 30-day retention. Streak history and per-card timing need the full revlog graph data (a documented follow-up).")
                }
            }
            .navigationTitle("Insights")
            .task { await load() }
        }
    }

    /// Build a REAL InsightStats from the collection via search queries.
    /// Reliable fields (total/mature/weak/today/30-day retention) are computed;
    /// streak and per-card averages need the revlog graph data, so their tips are
    /// suppressed (neutral values + includeStreak:false) rather than faked.
    private func load() async {
        let s = try? await env.gateway.collectionStats()
        stats = s
        let weak = (try? await env.gateway.searchCardIds(query: "prop:lapses>=3").count) ?? 0
        let today = (try? await env.gateway.searchCardIds(query: "rated:1").count) ?? 0
        let reviewed30 = (try? await env.gateway.searchCardIds(query: "rated:30").count) ?? 0
        let again30 = (try? await env.gateway.searchCardIds(query: "rated:30:1").count) ?? 0
        let retention: Float = reviewed30 > 0 ? max(0, 1 - Float(again30) / Float(reviewed30)) : 0.85
        let real = InsightStats(
            streak: 0, todayCount: today, retention30d: retention, weakCardCount: weak,
            avgEaseFactor: 2500, avgDailyReviews: 0,
            matureCards: s?.mature ?? 0, totalCards: s?.total ?? 0,
            worstDeck: nil, deckRetentions: [], avgSecPerCard: 0)
        tips = AITipEngine.generateTips(real, includeStreak: false)
    }

    private func statRow(_ label: String, _ value: Int, _ color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)").font(.body.monospacedDigit().bold()).foregroundColor(color)
        }
    }

    static let sampleStats = InsightStats(
        streak: 5, todayCount: 42, retention30d: 0.82, weakCardCount: 14,
        avgEaseFactor: 2100, avgDailyReviews: 30, matureCards: 320, totalCards: 540,
        worstDeck: DeckRetention(deckId: 3, deckName: "Physics::Quantum", retention: 0.58, reviewCount: 40),
        deckRetentions: [], avgSecPerCard: 18)
}
