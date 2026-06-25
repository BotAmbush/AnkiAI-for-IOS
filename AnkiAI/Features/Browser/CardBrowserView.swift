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
    @State private var selection = Set<Int64>()
    @State private var editMode: EditMode = .inactive
    @State private var showTagPrompt = false
    @State private var tagText = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    Text(error).font(.caption).foregroundColor(.red).padding()
                } else if isLoading && results.isEmpty {
                    ProgressView()
                } else {
                    List(selection: $selection) {
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
            .navigationTitle(editMode == .active && !selection.isEmpty ? "\(selection.count) selected" : "Browse")
            .environment(\.editMode, $editMode)
            .searchable(text: $query, prompt: "Search cards…")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .onChange(of: query) { _ in Task { await runSearch() } }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
                if editMode == .active {
                    ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
                }
            }
            .alert("Add tag", isPresented: $showTagPrompt) {
                TextField("tag", text: $tagText)
                Button("Cancel", role: .cancel) {}
                Button("Add") { Task { await bulkTag() } }
            } message: {
                Text("Add a tag to \(selection.count) selected card(s).")
            }
            .task { await runSearch() }
        }
    }

    @ViewBuilder private var bulkActionBar: some View {
        if working { ProgressView() }
        Menu {
            Button { Task { await bulkSuspend() } } label: { Label("Suspend", systemImage: "pause.circle") }
            Button { Task { await bulkUnsuspend() } } label: { Label("Unsuspend", systemImage: "play.circle") }
        } label: { Label("Suspend", systemImage: "pause.circle") }
            .disabled(selection.isEmpty || working)
        Spacer()
        Menu {
            Button("None") { Task { await bulkFlag(0) } }
            Button("🔴 Red") { Task { await bulkFlag(1) } }
            Button("🟠 Orange") { Task { await bulkFlag(2) } }
            Button("🟢 Green") { Task { await bulkFlag(3) } }
            Button("🔵 Blue") { Task { await bulkFlag(4) } }
        } label: { Label("Flag", systemImage: "flag") }
            .disabled(selection.isEmpty || working)
        Spacer()
        Button { showTagPrompt = true } label: { Label("Tag", systemImage: "tag") }
            .disabled(selection.isEmpty || working)
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

    private func bulkSuspend() async {
        working = true
        for id in selection { try? await env.gateway.suspendCard(cardId: id) }
        await finishBulk()
    }

    private func bulkUnsuspend() async {
        working = true
        for id in selection { try? await env.gateway.unsuspendCard(cardId: id) }
        await finishBulk()
    }

    private func bulkFlag(_ flag: Int) async {
        working = true
        for id in selection { try? await env.gateway.setFlag(cardId: id, flag: flag) }
        await finishBulk()
    }

    private func bulkTag() async {
        let tag = tagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        working = true
        for id in selection {
            if let info = try? await env.gateway.cardInfo(cardId: id) {
                try? await env.gateway.addTags(noteId: info.noteId, tags: tag)
            }
        }
        tagText = ""
        await finishBulk()
    }

    private func finishBulk() async {
        selection.removeAll()
        editMode = .inactive
        working = false
        await runSearch()
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
