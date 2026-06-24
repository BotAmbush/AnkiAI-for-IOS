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
                    Text("Card counts are live from your collection. AI tips use sample review history until revlog analysis is wired (M2.x).")
                }
            }
            .navigationTitle("Insights")
            .task {
                stats = try? await env.gateway.collectionStats()
                tips = AITipEngine.generateTips(Self.sampleStats)
            }
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
