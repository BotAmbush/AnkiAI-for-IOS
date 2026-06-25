import SwiftUI

/// Forced-study configuration (M2.28), mirroring `ForcedStudySettingsFragment`.
struct ForcedStudySettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var forced: ForcedStudyManager

    @State private var enabled = false
    @State private var interval = 60
    @State private var required = 10
    @State private var deckName = ""
    @State private var snooze = false
    @State private var maxSnoozes = 2
    @State private var snoozeDuration = 5
    @State private var decks: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle("Enable forced study", isOn: $enabled)
            } footer: {
                Text("iOS can't draw over other apps, so AnkiAI sends a repeating reminder and requires the session when you open the app.")
            }

            if enabled {
                Section("Schedule") {
                    Stepper("Every \(interval) min", value: $interval, in: 5...720, step: 5)
                    Stepper("Require \(required) cards", value: $required, in: 1...100, step: 1)
                    Picker("Deck", selection: $deckName) {
                        Text("Due across all decks").tag("")
                        ForEach(decks, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Snooze") {
                    Toggle("Allow snooze", isOn: $snooze)
                    if snooze {
                        Stepper("Max \(maxSnoozes) snoozes", value: $maxSnoozes, in: 1...10)
                        Stepper("\(snoozeDuration) min each", value: $snoozeDuration, in: 1...60, step: 1)
                    }
                }
                Section {
                    Button("Start a session now") { forced.triggerNow() }
                }
            }
        }
        .navigationTitle("Forced Study")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            load()
            decks = (try? await env.gateway.allDecks().map { $0.name }) ?? []
        }
        .onDisappear { save() }
    }

    private func load() {
        let s = forced.store
        enabled = s.isEnabled; interval = s.intervalMinutes; required = s.requiredCards
        deckName = s.deckName ?? ""; snooze = s.snoozeEnabled
        maxSnoozes = s.maxSnoozes; snoozeDuration = s.snoozeDurationMin
    }

    private func save() {
        let s = forced.store
        s.isEnabled = enabled; s.intervalMinutes = interval; s.requiredCards = required
        s.deckName = deckName.isEmpty ? nil : deckName; s.snoozeEnabled = snooze
        s.maxSnoozes = maxSnoozes; s.snoozeDurationMin = snoozeDuration
        Task { await forced.apply() }
    }
}
