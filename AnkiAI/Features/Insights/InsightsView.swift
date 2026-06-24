import SwiftUI

/// AI Insights dashboard. Mirrors `AiInsightsDashboardFragment` — surfaces
/// study-pattern tips from `AITipEngine`. Live stats come from the revlog
/// analyzer once the backend is connected (milestone 2); milestone 1 shows the
/// engine working against representative sample stats.
struct InsightsView: View {
    @State private var tips: [AITip] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Text(tip.icon).font(.title2)
                            Text(tip.message)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Tips are generated from your review history. Sample data shown until the collection is connected.")
                }
            }
            .navigationTitle("Insights")
            .onAppear { tips = AITipEngine.generateTips(Self.sampleStats) }
        }
    }

    static let sampleStats = InsightStats(
        streak: 5, todayCount: 42, retention30d: 0.82, weakCardCount: 14,
        avgEaseFactor: 2100, avgDailyReviews: 30, matureCards: 320, totalCards: 540,
        worstDeck: DeckRetention(deckId: 3, deckName: "Physics::Quantum", retention: 0.58, reviewCount: 40),
        deckRetentions: [], avgSecPerCard: 18)
}
