import SwiftUI

/// Reviewer: studies the deck's real scheduler QUEUE (due/learning/new in the
/// scheduler's order, respecting daily limits; suspended/buried/future cards are
/// excluded). Each answer is graded through the backend and persists immediately,
/// so leaving after one card keeps that card answered. Finishing the queue shows
/// a completion state.
struct ReviewerView: View {
    @EnvironmentObject private var env: AppEnvironment
    let deckName: String

    @State private var currentCardId: Int64?
    @State private var rendered: RenderedCard?
    @State private var labels: [String] = ["", "", "", ""]
    @State private var counts = (new: 0, learn: 0, review: 0)
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
            } else if finished {
                completionView
            } else if let rendered {
                CardWebView(html: showAnswer ? rendered.answerHTML : rendered.questionHTML, css: rendered.css,
                            mediaDirectory: env.gateway.mediaDirectory)
                    .frame(maxHeight: .infinity)
                Divider()
                controls
            } else {
                Spacer(); Text("No cards in this deck.".loc).foregroundColor(.secondary); Spacer()
            }
        }
        .navigationTitle(leaf)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showEditor = true }
                        label: { Label("Edit card".loc, systemImage: "pencil") }
                    Button { Task { await mutateCurrent { try await env.gateway.buryCard(cardId: $0) }; await advance() } }
                        label: { Label("Bury card".loc, systemImage: "arrow.down.to.line") }
                    Button { Task { await mutateCurrent { try await env.gateway.suspendCard(cardId: $0) }; await advance() } }
                        label: { Label("Suspend card", systemImage: "pause.circle") }
                    Button { Task { await moveCurrentToDefault(); await advance() } }
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
                .accessibilityLabel("Card actions".loc)
                .disabled(currentCardId == nil || finished)
            }
        }
        .task { await startStudy() }
        .sheet(isPresented: $showEditor) {
            if let cid = currentCardId {
                NoteEditorView(cardId: cid) { Task { await renderCurrent() } }
            }
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: env.makeChatViewModel(cardId: currentCardId ?? -2))
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
            Text("You've finished the cards due now in \(leaf).")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Review again") { Task { await startStudy() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                countLabel(counts.new, .blue)
                countLabel(counts.learn, .red)
                countLabel(counts.review, .green)
                Spacer()
                Button("Ask Claude".loc) { showChat = true }.buttonStyle(.bordered).font(.caption)
            }
            if !showAnswer {
                Button("Show Answer".loc) { showAnswer = true }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else {
                // Real scheduler grading; each button shows the next interval.
                HStack(spacing: 8) {
                    ForEach(Array(AnswerRating.allCases.enumerated()), id: \.element.rawValue) { i, rating in
                        Button {
                            Task { await answer(rating) }
                        } label: {
                            VStack(spacing: 2) {
                                Text(rating.label.loc)
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

    private func countLabel(_ value: Int, _ color: Color) -> some View {
        Text("\(value)").font(.caption.monospacedDigit().bold()).foregroundColor(value == 0 ? .secondary : color)
    }

    private func startStudy() async {
        isLoading = true; error = nil; finished = false; showAnswer = false
        do {
            try await env.gateway.setStudyDeck(named: deckName)
            await advance()
        } catch {
            self.error = "\(error)"
        }
        isLoading = false
    }

    /// Pull the next due card from the scheduler queue (or finish).
    private func advance() async {
        do {
            let q = try await env.gateway.nextDueCard()
            counts = (q.newCount, q.learnCount, q.reviewCount)
            if let cid = q.cardId {
                currentCardId = cid
                try await renderCurrent()
            } else {
                currentCardId = nil
                finished = true
            }
        } catch {
            self.error = "\(error)"
        }
    }

    private func renderCurrent() async {
        guard let cid = currentCardId else { return }
        showAnswer = false
        do {
            rendered = try await env.gateway.renderCard(cardId: cid)
            labels = (try? await env.gateway.answerButtonLabels(cardId: cid)) ?? ["", "", "", ""]
        } catch {
            self.error = "\(error)"
        }
    }

    private func answer(_ rating: AnswerRating) async {
        guard let cid = currentCardId else { return }
        isAnswering = true
        do {
            try await env.gateway.answerCard(cardId: cid, rating: rating)
            await advance()
        } catch {
            self.error = "\(error)"
        }
        isAnswering = false
    }

    private func mutateCurrent(_ op: (Int64) async throws -> Void) async {
        guard let cid = currentCardId else { return }
        do { try await op(cid) } catch { self.error = "\(error)" }
    }

    private func flagCurrent(_ flag: Int) async {
        await mutateCurrent { try await env.gateway.setFlag(cardId: $0, flag: flag) }
    }

    private func moveCurrentToDefault() async {
        guard let cid = currentCardId else { return }
        do {
            let deckId = try await env.gateway.resolveOrCreateDeck(name: "Default")
            try await env.gateway.moveCard(cardId: cid, toDeckId: deckId)
        } catch {
            self.error = "\(error)"
        }
    }

    private func undoLast() async {
        do {
            try await env.gateway.undo()
            await startStudy()
        } catch {
            self.error = "\(error)"
        }
    }
}
