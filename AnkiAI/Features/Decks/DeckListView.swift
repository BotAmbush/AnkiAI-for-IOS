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
                    List(decks) { deck in DeckRow(deck: deck) }
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreator = true } label: {
                        Label("Create Cards with AI", systemImage: "sparkles")
                    }
                }
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
            .task { await load() }
            .refreshable { await load() }
        }
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
            Text(leaf)
                .padding(.leading, CGFloat(deck.level) * 14)
            Spacer()
            CountChip(value: deck.newCount, color: .blue)
            CountChip(value: deck.learnCount, color: .red)
            CountChip(value: deck.reviewCount, color: .green)
        }
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
