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

/// Full card detail: backend-rendered question and answer + scheduling info.
private struct CardDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let cardId: Int64
    @State private var rendered: RenderedCard?
    @State private var info: CardInfo?
    @State private var error: String?
    @State private var showEditor = false

    var body: some View {
        Group {
            if let error {
                Text(error).font(.caption).foregroundColor(.red).padding()
            } else if let rendered {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        CardWebView(html: rendered.questionHTML, css: rendered.css,
                                    mediaDirectory: env.gateway.mediaDirectory).frame(minHeight: 140)
                        Divider()
                        CardWebView(html: rendered.answerHTML, css: rendered.css,
                                    mediaDirectory: env.gateway.mediaDirectory).frame(minHeight: 160)
                        if let info { infoSection(info) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
            }
        }
        .sheet(isPresented: $showEditor) {
            NoteEditorView(cardId: cardId) { Task { await reload() } }
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            rendered = try await env.gateway.renderCard(cardId: cardId)
            info = try? await env.gateway.cardInfo(cardId: cardId)
        } catch { self.error = "\(error)" }
    }

    @ViewBuilder
    private func infoSection(_ info: CardInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("Card info").font(.headline)
            row("Deck", info.deck)
            row("Type", info.cardType)
            row("Due", dueText(info))
            if info.interval > 0 { row("Interval", "\(info.interval) day(s)") }
            row("Reviews", "\(info.reviews)")
            row("Lapses", "\(info.lapses)")
            if info.ease > 0 { row("Ease", "\(info.ease / 10)%") }
        }
        .padding()
    }

    private func dueText(_ info: CardInfo) -> String {
        if let date = info.dueDate {
            let days = Int((date.timeIntervalSinceNow / 86400).rounded())
            let when = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
            return days <= 0 ? "now / overdue" : "\(when) (\(date.formatted(date: .abbreviated, time: .omitted)))"
        }
        if let pos = info.duePosition { return "new (position \(pos))" }
        return "—"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
