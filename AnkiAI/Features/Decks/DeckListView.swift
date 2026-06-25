import SwiftUI

/// Deck picker. M2.1: lists **real** decks and subdecks with **live**
/// new/learn/review counts read from the Anki backend (no fake data). The AI
/// card creator opens from here. Review/scheduling are later milestones.
struct DeckListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var decks: [DeckTreeEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showCreator = false
    @State private var showCustomStudy = false
    @State private var renameTarget: DeckTreeEntry?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Opening collection…")
                } else if let loadError {
                    ContentUnavailableViewCompat(
                        title: "Couldn't open collection",
                        message: loadError,
                        retry: { Task { await load() } })
                } else if decks.isEmpty {
                    Text("No decks yet.").foregroundColor(.secondary)
                } else {
                    List(decks) { deck in
                        NavigationLink {
                            ReviewerView(deckName: deck.name)
                        } label: {
                            DeckRow(deck: deck)
                        }
                        .swipeActions(edge: .trailing) {
                            if deck.deckId != 1 { // never delete the Default deck
                                Button(role: .destructive) {
                                    Task { await remove(deck) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            Button {
                                renameText = deck.name
                                renameTarget = deck
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showCustomStudy = true } label: {
                        Label("Custom Study".loc, systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreator = true } label: {
                        Label("Create Cards with AI".loc, systemImage: "sparkles")
                    }
                }
            }
            .sheet(isPresented: $showCustomStudy) {
                CustomStudyView { Task { await load() } }
            }
            .sheet(isPresented: $showCreator) {
                NavigationStack {
                    ChatView(viewModel: env.makeChatViewModel(cardId: -1))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showCreator = false }
                            }
                        }
                }
            }
            .alert("Rename deck", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Full name (use :: for subdecks)", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Rename") { Task { await rename() } }
            } message: {
                Text("Use \"Parent::Child\" to nest decks.")
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func rename() async {
        guard let target = renameTarget else { return }
        renameTarget = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != target.name else { return }
        do {
            try await env.gateway.renameDeck(deckId: target.deckId, newName: name)
            await load()
        } catch { loadError = "\(error)" }
    }

    private func remove(_ deck: DeckTreeEntry) async {
        do {
            try await env.gateway.removeDeck(deckId: deck.deckId)
            await load()
        } catch { loadError = "\(error)" }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            decks = try await env.gateway.deckTree()
        } catch {
            loadError = "\(error)"
        }
        isLoading = false
    }
}

private struct DeckRow: View {
    let deck: DeckTreeEntry
    private var leaf: String { deck.name.components(separatedBy: "::").last ?? deck.name }

    var body: some View {
        HStack {
            Image(systemName: deck.level == 0 ? "tray.full" : "tray")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(leaf)
                .padding(.leading, CGFloat(max(0, deck.level - 1)) * 14)
            Spacer()
            CountChip(value: deck.newCount, color: .blue)
            CountChip(value: deck.learnCount, color: .red)
            CountChip(value: deck.reviewCount, color: .green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(leaf). \(deck.newCount) \("new".loc), \(deck.learnCount) \("learning".loc), \(deck.reviewCount) \("due".loc)")
    }
}

private struct CountChip: View {
    let value: Int
    let color: Color
    var body: some View {
        Text("\(value)")
            .font(.caption.monospacedDigit())
            .foregroundColor(value == 0 ? .secondary : color)
            .frame(minWidth: 22)
    }
}

/// Minimal iOS 16-compatible "content unavailable" view with a retry action.
private struct ContentUnavailableViewCompat: View {
    let title: String
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Retry", action: retry).buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
