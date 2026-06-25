import SwiftUI

/// In-app forced-study session (M2.28): the user must review `requiredCards`
/// before the session can be finished. Snooze (if allowed) postpones it. This is
/// the iOS counterpart of the Android overlay enforcement.
struct ForcedStudySessionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var forced: ForcedStudyManager

    @State private var cardIds: [Int64] = []
    @State private var index = 0
    @State private var rendered: RenderedCard?
    @State private var labels: [String] = ["", "", "", ""]
    @State private var showAnswer = false
    @State private var reviewed = 0
    @State private var loading = true
    @State private var error: String?

    private var required: Int { forced.store.requiredCards }
    private var done: Bool { reviewed >= required }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Forced study").font(.headline)
                Spacer()
                Text("\(min(reviewed, required)) / \(required)")
                    .font(.body.monospacedDigit().bold())
            }
            .padding()
            Divider()

            if done {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundColor(.green)
                    Text("Session complete!").font(.title3.bold())
                    Button("Finish") { forced.complete() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if loading {
                Spacer(); ProgressView("Loading cards…"); Spacer()
            } else if let error {
                Spacer(); Text(error).foregroundColor(.secondary).padding(); Spacer()
            } else if cardIds.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No cards available to study right now.").foregroundColor(.secondary)
                    Button("Finish") { forced.complete() }.buttonStyle(.bordered)
                }
                Spacer()
            } else if let rendered {
                CardWebView(html: showAnswer ? rendered.answerHTML : rendered.questionHTML,
                            css: rendered.css, mediaDirectory: env.gateway.mediaDirectory)
                    .frame(maxHeight: .infinity)
                Divider()
                controls
            }

            if forced.canSnooze && !done {
                Button("Snooze \(forced.store.snoozeDurationMin) min") { forced.snooze() }
                    .font(.footnote).padding(.bottom, 8)
            }
        }
        .interactiveDismissDisabled(true)
        .task { await load() }
    }

    @ViewBuilder private var controls: some View {
        if showAnswer {
            HStack(spacing: 8) {
                answerButton(.again, .red); answerButton(.hard, .orange)
                answerButton(.good, .green); answerButton(.easy, .blue)
            }.padding()
        } else {
            Button("Show Answer") { showAnswer = true }
                .buttonStyle(.borderedProminent).padding()
        }
    }

    private func answerButton(_ rating: AnswerRating, _ color: Color) -> some View {
        let i = rating.rawValue - 1
        return Button {
            Task { await answer(rating) }
        } label: {
            VStack(spacing: 2) {
                Text(rating.label).font(.callout.bold())
                if i < labels.count, !labels[i].isEmpty { Text(labels[i]).font(.caption2) }
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).tint(color)
    }

    private func load() async {
        loading = true
        do {
            let deck = forced.store.deckName
            if let deck, !deck.isEmpty {
                cardIds = try await env.gateway.cardIds(inDeckNamed: deck)
            } else {
                cardIds = try await env.gateway.searchCardIds(query: "is:due")
            }
            if cardIds.isEmpty {
                cardIds = try await env.gateway.searchCardIds(query: "is:due OR is:new")
            }
            await renderCurrent()
        } catch { self.error = "\(error)" }
        loading = false
    }

    private func renderCurrent() async {
        guard index < cardIds.count else { return }
        showAnswer = false
        do {
            rendered = try await env.gateway.renderCard(cardId: cardIds[index])
            labels = (try? await env.gateway.answerButtonLabels(cardId: cardIds[index])) ?? ["", "", "", ""]
        } catch { self.error = "\(error)" }
    }

    private func answer(_ rating: AnswerRating) async {
        guard index < cardIds.count else { return }
        do {
            try await env.gateway.answerCard(cardId: cardIds[index], rating: rating)
            reviewed += 1
            index += 1
            if index < cardIds.count, !done { await renderCurrent() }
        } catch { self.error = "\(error)" }
    }
}
