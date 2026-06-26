import SwiftUI
import Charts

/// AI Insights + statistics dashboard. Surfaces live collection counts, AI study
/// tips from `AITipEngine`, and backend statistics graphs (reviews / forecast).
struct InsightsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var tips: [AITip] = []
    @State private var stats: CollectionStats?
    @State private var graphs: StatsGraphs?

    private static let window = 30

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
                if let graphs {
                    Section("Reviews (last \(Self.window) days)") {
                        barChart(graphs.reviews.filter { $0.day >= -Self.window }, color: .green)
                    }
                    Section("Due forecast (next \(Self.window) days)") {
                        barChart(graphs.futureDue.filter { $0.day >= 0 && $0.day <= Self.window }, color: .blue)
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
                    Text("Live from your collection + revlog: card counts, weak cards (≥3 lapses), today's reviews, study streak, average reviews/day, and average time/card. 30-day retention is shown only when you have enough recent reviews (no estimate is invented otherwise). Average ease and per-deck retention are not yet computed.")
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
        // nil when there isn't enough review data — never a fabricated 0.85.
        let retention: Float? = reviewed30 > 0 ? max(0, 1 - Float(again30) / Float(reviewed30)) : nil
        let g = try? await env.gateway.statsGraphs(search: "", days: 365)
        graphs = g
        // REAL revlog-derived metrics (no placeholders): streak, daily reviews,
        // seconds/card, and today's count come from the backend graph data.
        let real = InsightStats(
            streak: g?.streak ?? 0,
            todayCount: g?.todayReviews ?? today,
            retention30d: retention,
            weakCardCount: weak,
            avgEaseFactor: 2500,                 // ease tip suppressed (not yet computed — see note)
            avgDailyReviews: Float(g?.avgReviewsPerStudiedDay ?? 0),
            matureCards: s?.mature ?? 0,
            totalCards: s?.total ?? 0,
            worstDeck: nil,                      // per-deck retention not yet computed (see note)
            deckRetentions: [],
            avgSecPerCard: Float(g?.avgSecondsPerCard ?? 0))
        tips = AITipEngine.generateTips(real, includeStreak: true)
    }

    @ViewBuilder private func barChart(_ points: [GraphPoint], color: Color) -> some View {
        if points.contains(where: { $0.count > 0 }) {
            Chart(points) { p in
                BarMark(x: .value("Day", p.day), y: .value("Cards", p.count))
                    .foregroundStyle(color)
            }
            .frame(height: 140)
            .padding(.vertical, 4)
        } else {
            Text("No data yet.").font(.caption).foregroundColor(.secondary)
        }
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
