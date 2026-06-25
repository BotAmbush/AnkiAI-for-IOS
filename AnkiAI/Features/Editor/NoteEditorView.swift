import SwiftUI

/// Manual note editor (M2.15): edit a card's note fields and save via the backend
/// (`update_notes`, undoable). Fields are edited as raw HTML — a rich editor is a
/// later refinement. Complements the AI "improve card" path.
struct NoteEditorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let cardId: Int64
    var onSaved: (() -> Void)?

    @State private var noteId: Int64 = 0
    @State private var notetypeName = ""
    @State private var fieldNames: [String] = []
    @State private var fields: [String] = []
    @State private var tagsText = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                        Text(error).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding()
                    }
                } else if loaded {
                    Form {
                        ForEach(fieldNames.indices, id: \.self) { i in
                            Section(fieldNames[i]) {
                                TextEditor(text: Binding(
                                    get: { i < fields.count ? fields[i] : "" },
                                    set: { if i < fields.count { fields[i] = $0 } }))
                                    .frame(minHeight: 90)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        Section {
                            TextField("space-separated tags", text: $tagsText)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        } header: { Text("Tags") }
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(notetypeName.isEmpty ? "Edit card" : "Edit · \(notetypeName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { Task { await save() } }.disabled(!loaded) }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let note = try await env.gateway.editableNote(cardId: cardId)
            noteId = note.noteId
            notetypeName = note.notetypeName
            fieldNames = note.fieldNames
            fields = note.fields
            tagsText = note.tags.joined(separator: " ")
            loaded = true
        } catch {
            self.error = "\(error)"
        }
    }

    private func save() async {
        saving = true
        do {
            let tags = tagsText.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            try await env.gateway.updateNote(NoteData(id: noteId, notetypeId: 0, fields: fields, tags: tags))
            onSaved?()
            dismiss()
        } catch {
            self.error = "\(error)"
        }
        saving = false
    }
}
