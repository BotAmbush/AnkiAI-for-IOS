import SwiftUI

/// Read-only deck scheduling options (M2.44). Editing is intentionally NOT exposed:
/// writing deck config to a live, AnkiWeb-synced collection is risky (wrong flags
/// can reset scheduling or disable FSRS). These values sync down from AnkiWeb /
/// Anki Desktop; here we only display them.
struct DeckOptionsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let deckId: Int64
    let deckName: String

    @State private var options: DeckOptions?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let o = options {
                    Section("Preset") {
                        LabeledContent("Config", value: o.configName.isEmpty ? "Default" : o.configName)
                    }
                    Section("Daily limits") {
                        LabeledContent("New cards/day", value: "\(o.newPerDay)")
                        LabeledContent("Maximum reviews/day", value: "\(o.reviewsPerDay)")
                    }
                    Section("Scheduling") {
                        LabeledContent("FSRS", value: o.fsrs ? "On" : "Off")
                        if o.fsrs && o.desiredRetention > 0 {
                            LabeledContent("Desired retention",
                                           value: String(format: "%.0f%%", o.desiredRetention * 100))
                        }
                    }
                } else if let error {
                    Text(error).font(.caption).foregroundColor(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(deckName.components(separatedBy: "::").last ?? deckName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                do { options = try await env.gateway.deckOptions(deckId: deckId) }
                catch { self.error = "\(error)" }
            }
        }
    }
}
