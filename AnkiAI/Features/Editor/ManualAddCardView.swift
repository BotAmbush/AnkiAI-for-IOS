import SwiftUI

/// Manual note/card creation (Issue 2) — a NATIVE entry point independent of the
/// AI creator. Supports Basic and Cloze note types, deck + tags, validates the
/// required field, and saves through the REAL production backend (not the stub /
/// not the AI path). New notes appear in Browse and sync via AnkiWeb.
struct ManualAddCardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    var onAdded: (() -> Void)?

    enum Kind: String, CaseIterable, Identifiable { case basic = "Basic", cloze = "Cloze"; var id: String { rawValue } }

    @State private var kind: Kind = .basic
    @State private var fields: [String] = ["", ""]
    @State private var tagsText = ""
    @State private var decks: [DeckNameId] = []
    @State private var deckId: Int64 = 0
    @State private var saving = false
    @State private var error: String?

    /// Field labels per note type (matches the default Anki note types).
    private var fieldNames: [String] { kind == .basic ? ["Front", "Back"] : ["Text", "Back Extra"] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note type") {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _ in fields = Array(repeating: "", count: fieldNames.count) }
                    if kind == .cloze {
                        Text("Use {{c1::…}} in Text to make a cloze deletion.").font(.caption).foregroundColor(.secondary)
                    }
                }
                ForEach(fieldNames.indices, id: \.self) { i in
                    Section(fieldNames[i] + (i == 0 ? " (required)" : "")) {
                        TextEditor(text: Binding(get: { i < fields.count ? fields[i] : "" },
                                                 set: { if i < fields.count { fields[i] = $0 } }))
                            .frame(minHeight: 80)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Section("Tags") {
                    TextField("space-separated tags", text: $tagsText)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section("Deck") {
                    Picker("Deck", selection: $deckId) {
                        ForEach(decks) { Text($0.name).tag($0.id) }
                    }
                }
                if let error { Section { Text(error).font(.caption).foregroundColor(.red) } }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { Task { await save() } }.disabled(!canSave) }
                }
            }
            .task { await loadDecks() }
        }
    }

    private var canSave: Bool {
        deckId != 0 && !(fields.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadDecks() async {
        decks = (try? await env.gateway.allDecks()) ?? []
        if deckId == 0 { deckId = decks.first?.id ?? 0 }
    }

    private func save() async {
        guard canSave else { error = "The first field is required and a deck must be selected."; return }
        saving = true; error = nil
        do {
            let notetypeId = try await env.gateway.notetypeId(named: kind.rawValue)
            let noteId = try await env.gateway.addNote(notetypeId: notetypeId, fields: fields, deckId: deckId)
            let tags = tagsText.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            if !tags.isEmpty {
                try await env.gateway.addTags(noteId: noteId, tags: tags.joined(separator: " "))
            }
            onAdded?()
            dismiss()
        } catch {
            self.error = "\(error)"   // surface the real backend error
        }
        saving = false
    }
}
