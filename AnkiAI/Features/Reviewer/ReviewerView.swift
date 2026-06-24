import SwiftUI

/// Reviewer (M2.2 read slice): loads REAL cards from a deck and renders their
/// question/answer + note-type CSS via the Anki backend. Read-only — answer
/// buttons, undo, and scheduler mutations are the next slice. "Ask Claude" opens
/// the AI chat (card-context wiring to the backend comes later).
struct ReviewerView: View {
    @EnvironmentObject private var env: AppEnvironment
    let deckName: String

    @State private var cardIds: [Int64] = []
    @State private var index = 0
    @State private var rendered: RenderedCard?
    @State private var showAnswer = false
    @State private var isLoading = true
    @State private var isAnswering = false
    @State private var error: String?
    @State private var showChat = false

    private var leaf: String { deckName.components(separatedBy: "::").last ?? deckName }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer(); ProgressView("Loading cards…"); Spacer()
            } else if let error {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding()
                }
                Spacer()
            } else if cardIds.isEmpty {
                Spacer(); Text("No cards in this deck.").foregroundColor(.secondary); Spacer()
            } else if let rendered {
                CardWebView(html: showAnswer ? rendered.answerHTML : rendered.questionHTML, css: rendered.css)
                    .frame(maxHeight: .infinity)
                Divider()
                controls
            }
        }
        .navigationTitle(leaf)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { Task { await mutateCurrent { try await env.gateway.buryCard(cardId: $0) }; await next() } }
                        label: { Label("Bury card", systemImage: "arrow.down.to.line") }
                    Button { Task { await mutateCurrent { try await env.gateway.suspendCard(cardId: $0) }; await next() } }
                        label: { Label("Suspend card", systemImage: "pause.circle") }
                    Divider()
                    Button { Task { await undoLast() } }
                        label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(cardIds.isEmpty)
            }
        }
        .task { await loadDeck() }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: env.makeChatViewModel(cardId: cardIds.indices.contains(index) ? cardIds[index] : -2))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showChat = false } }
                    }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(index + 1) / \(cardIds.count)").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Ask Claude") { showChat = true }.buttonStyle(.bordered).font(.caption)
            }
            if !showAnswer {
                Button("Show Answer") { showAnswer = true }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else {
                // Real scheduler grading via the backend.
                HStack(spacing: 8) {
                    ForEach(AnswerRating.allCases, id: \.rawValue) { rating in
                        Button(rating.label) { Task { await answer(rating) } }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(isAnswering)
                    }
                }
            }
        }
        .padding()
    }

    private func loadDeck() async {
        isLoading = true; error = nil
        do {
            cardIds = try await env.gateway.cardIds(inDeckNamed: deckName)
            index = 0
            if !cardIds.isEmpty { try await renderCurrent() }
        } catch {
            self.error = "\(error)"
        }
        isLoading = false
    }

    private func renderCurrent() async throws {
        showAnswer = false
        rendered = try await env.gateway.renderCard(cardId: cardIds[index])
    }

    private func next() async {
        guard !cardIds.isEmpty else { return }
        index = (index + 1) % cardIds.count
        do { try await renderCurrent() } catch { self.error = "\(error)" }
    }

    private func answer(_ rating: AnswerRating) async {
        guard cardIds.indices.contains(index) else { return }
        isAnswering = true
        do {
            try await env.gateway.answerCard(cardId: cardIds[index], rating: rating)
            await next()
        } catch {
            self.error = "\(error)"
        }
        isAnswering = false
    }

    private func mutateCurrent(_ op: (Int64) async throws -> Void) async {
        guard cardIds.indices.contains(index) else { return }
        do { try await op(cardIds[index]) } catch { self.error = "\(error)" }
    }

    private func undoLast() async {
        do {
            try await env.gateway.undo()
            await loadDeck()
        } catch {
            self.error = "\(error)"
        }
    }
}
