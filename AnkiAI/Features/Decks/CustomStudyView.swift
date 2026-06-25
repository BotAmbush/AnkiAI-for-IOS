import SwiftUI

/// Custom study (M2.25): builds a filtered deck from an Anki search + card limit.
/// The new deck appears in the deck list; studying it reschedules cards normally.
struct CustomStudyView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    var onCreated: () -> Void

    @State private var name = "Custom Study"
    @State private var search = "is:due"
    @State private var limit = 50
    @State private var creating = false
    @State private var error: String?

    private let presets: [(label: String, search: String)] = [
        ("Due now", "is:due"),
        ("Forgotten recently (7d)", "rated:7:1"),
        ("New cards", "is:new"),
        ("Hard or again (7d)", "rated:7:1 OR rated:7:2"),
        ("Added this week", "added:7"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Deck name", text: $name)
                }
                Section {
                    TextField("Anki search (e.g. deck:French is:due)", text: $search)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Stepper("Card limit: \(limit)", value: $limit, in: 1...500, step: 10)
                } header: {
                    Text("What to study")
                } footer: {
                    Text("Uses Anki search syntax. The filtered deck gathers matching cards; answering them updates their normal schedule.")
                }
                Section("Presets") {
                    ForEach(presets, id: \.label) { p in
                        Button(p.label) { search = p.search }
                    }
                }
                if let error { Section { Text(error).font(.caption).foregroundColor(.red) } }
            }
            .navigationTitle("Custom Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if creating { ProgressView() } else {
                        Button("Create") { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || search.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func create() async {
        creating = true; error = nil
        do {
            _ = try await env.gateway.createFilteredDeck(name: name, search: search, limit: limit)
            onCreated()
            dismiss()
        } catch {
            self.error = "\(error)"
        }
        creating = false
    }
}
