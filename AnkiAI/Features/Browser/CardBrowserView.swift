import SwiftUI

/// Card browser (M2.7): search the real collection with any Anki query
/// (e.g. `deck:Math`, `tag:vocab`, free text) and browse matching cards. Tapping
/// a row opens the backend-rendered card. Read-only for now.
struct CardBrowserView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var query = ""
    @State private var results: [Int64] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    Text(error).font(.caption).foregroundColor(.red).padding()
                } else if isLoading && results.isEmpty {
                    ProgressView()
                } else {
                    List {
                        Section {
                            ForEach(results, id: \.self) { id in
                                NavigationLink {
                                    CardDetailView(cardId: id)
                                } label: {
                                    CardRowView(cardId: id)
                                }
                            }
                        } footer: {
                            Text("\(results.count) card(s). Try `deck:Math`, `tag:vocab`, or free text.")
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .searchable(text: $query, prompt: "Search cards…")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .onChange(of: query) { _ in Task { await runSearch() } }
            .task { await runSearch() }
        }
    }

    private func runSearch() async {
        isLoading = true
        error = nil
        do {
            results = try await env.gateway.searchCardIds(query: query)
        } catch {
            self.error = "\(error)"
        }
        isLoading = false
    }
}

/// One browser row: the card's rendered question, stripped to plain text.
private struct CardRowView: View {
    @EnvironmentObject private var env: AppEnvironment
    let cardId: Int64
    @State private var text = "…"

    var body: some View {
        Text(text)
            .lineLimit(2)
            .task {
                if let r = try? await env.gateway.renderCard(cardId: cardId) {
                    let stripped = HTMLText.stripHTML(r.questionHTML)
                    text = stripped.isEmpty ? "(empty)" : stripped
                }
            }
    }
}

/// Full card detail: backend-rendered question and answer.
private struct CardDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let cardId: Int64
    @State private var rendered: RenderedCard?
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                Text(error).font(.caption).foregroundColor(.red).padding()
            } else if let rendered {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        CardWebView(html: rendered.questionHTML, css: rendered.css).frame(minHeight: 160)
                        Divider()
                        CardWebView(html: rendered.answerHTML, css: rendered.css).frame(minHeight: 200)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { rendered = try await env.gateway.renderCard(cardId: cardId) }
            catch { self.error = "\(error)" }
        }
    }
}
