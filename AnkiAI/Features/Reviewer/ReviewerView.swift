import SwiftUI

/// Reviewer: loads REAL cards from a deck, renders question/answer + note-type CSS
/// via the backend, and grades them through the real scheduler. Answer buttons
/// show the next interval per rating; finishing the deck shows a completion state.
struct ReviewerView: View {
    @EnvironmentObject private var env: AppEnvironment
    let deckName: String

    @State private var cardIds: [Int64] = []
    @State private var index = 0
    @State private var rendered: RenderedCard?
    @State private var labels: [String] = ["", "", "", ""]
    @State private var showAnswer = false
    @State private var finished = false
    @State private var isLoading = true
    @State private var isAnswering = false
    @State private var error: String?
    @State private var showChat = false
    @State private var showEditor = false

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
            } else if finished {
                completionView
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
                    Button { showEditor = true }
                        label: { Label("Edit card", systemImage: "pencil") }
                    Button { Task { await mutateCurrent { try await env.gateway.buryCard(cardId: $0) }; await next() } }
                        label: { Label("Bury card", systemImage: "arrow.down.to.line") }
                    Button { Task { await mutateCurrent { try await env.gateway.suspendCard(cardId: $0) }; await next() } }
                        label: { Label("Suspend card", systemImage: "pause.circle") }
                    Button { Task { await moveCurrentToDefault(); await next() } }
                        label: { Label("Move to Default deck", systemImage: "tray.and.arrow.down") }
                    Menu {
                        Button("None") { Task { await flagCurrent(0) } }
                        Button("🔴 Red") { Task { await flagCurrent(1) } }
                        Button("🟠 Orange") { Task { await flagCurrent(2) } }
                        Button("🟢 Green") { Task { await flagCurrent(3) } }
                        Button("🔵 Blue") { Task { await flagCurrent(4) } }
                    } label: { Label("Flag", systemImage: "flag") }
                    Divider()
                    Button { Task { await undoLast() } }
                        label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(cardIds.isEmpty || finished)
            }
        }
        .task { await loadDeck() }
        .sheet(isPresented: $showEditor) {
            if cardIds.indices.contains(index) {
                NoteEditorView(cardId: cardIds[index]) {
                    Task { try? await renderCurrent() }
                }
            }
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: env.makeChatViewModel(cardId: cardIds.indices.contains(index) ? cardIds[index] : -2))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showChat = false } }
                    }
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("🎉").font(.system(size: 56))
            Text("Deck complete").font(.title2.bold())
            Text("You've gone through all \(cardIds.count) card(s) in \(leaf).")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Review again") { Task { await loadDeck() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // Real scheduler grading; each button shows the next interval.
                HStack(spacing: 8) {
                    ForEach(Array(AnswerRating.allCases.enumerated()), id: \.element.rawValue) { i, rating in
                        Button {
                            Task { await answer(rating) }
                        } label: {
                            VStack(spacing: 2) {
                                Text(rating.label)
                                if i < labels.count, !labels[i].isEmpty {
                                    Text(labels[i]).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAnswering)
                    }
                }
            }
        }
        .padding()
    }

    private func loadDeck() async {
        isLoading = true; error = nil; finished = false
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
        // Interval labels are best-effort (non-fatal if unavailable).
        labels = (try? await env.gateway.answerButtonLabels(cardId: cardIds[index])) ?? ["", "", "", ""]
    }

    private func next() async {
        guard !cardIds.isEmpty else { return }
        if index + 1 >= cardIds.count {
            finished = true   // reached the end of the deck — show completion
            return
        }
        index += 1
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

    private func flagCurrent(_ flag: Int) async {
        await mutateCurrent { try await env.gateway.setFlag(cardId: $0, flag: flag) }
    }

    private func moveCurrentToDefault() async {
        guard cardIds.indices.contains(index) else { return }
        do {
            let deckId = try await env.gateway.resolveOrCreateDeck(name: "Default")
            try await env.gateway.moveCard(cardId: cardIds[index], toDeckId: deckId)
        } catch {
            self.error = "\(error)"
        }
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
