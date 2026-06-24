import SwiftUI

/// Deck picker. Mirrors `DeckPicker` — lists decks and exposes the AI card
/// creator FAB. (Real deck stats/counts arrive with the backend in milestone 2.)
struct DeckListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var decks: [DeckNameId] = []
    @State private var showCreator = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(decks) { deck in
                        NavigationLink {
                            ReviewerView(cardId: 1000) // sample card until backend supplies queues
                        } label: {
                            Label(deck.name, systemImage: "tray.full")
                        }
                    }
                } footer: {
                    Text("Deck counts and the review queue connect to the Anki collection in milestone 2.")
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
            .task { decks = (try? await env.gateway.allDecks()) ?? [] }
        }
    }
}
