import SwiftUI

/// AI Assistant settings. Mirrors `AiSettingsFragment` — API key entry (now
/// Keychain-backed), test connection, model info, and budget/spend tracking.
struct AISettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var apiKey = ""
    @State private var hasKey = false
    @State private var testResult: String?
    @State private var testing = false
    @State private var spent: Double = 0
    @State private var limitText = ""
    @State private var ankiUser = ""
    @State private var ankiPass = ""
    @State private var syncing = false
    @State private var syncStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Claude API Key") {
                    if hasKey {
                        Label("Connected", systemImage: "checkmark.seal.fill").foregroundColor(.green)
                        Button("Remove key", role: .destructive) {
                            env.settings.apiKey = nil
                            hasKey = false
                        }
                    } else {
                        SecureField("sk-ant-…", text: $apiKey)
                        Button("Connect") {
                            env.settings.apiKey = apiKey
                            hasKey = env.settings.hasAPIKey
                            apiKey = ""
                        }
                        .disabled(apiKey.isEmpty)
                    }
                    Text("Your key is stored in the device Keychain only. Get a key at console.anthropic.com")
                        .font(.caption).foregroundColor(.secondary)
                }

                if hasKey {
                    Section("Test connection") {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack { Text("Test connection"); if testing { Spacer(); ProgressView() } }
                        }
                        .disabled(testing)
                        if let testResult { Text(testResult).font(.caption) }
                    }
                }

                Section("Models") {
                    LabeledContent("Reviewer chat", value: "Claude Haiku 4.5")
                    LabeledContent("Card creator", value: "Claude Sonnet 4.6")
                }

                Section {
                    TextField("AnkiWeb email", text: $ankiUser)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("AnkiWeb password", text: $ankiPass)
                    Button {
                        Task { await syncDownload() }
                    } label: {
                        HStack {
                            Text("Log in & download collection")
                            if syncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(syncing || ankiUser.isEmpty || ankiPass.isEmpty)
                    if let syncStatus { Text(syncStatus).font(.caption) }
                } header: {
                    Text("AnkiWeb sync")
                } footer: {
                    Text("Downloads your AnkiWeb collection and REPLACES the local one. Your password is sent only to AnkiWeb; only the session key is stored (Keychain). Card import from files is not finished yet — use this to load your real cards.")
                }

                Section {
                    LabeledContent("Spent", value: String(format: "$%.4f", spent))
                    LabeledContent("Remaining", value: String(format: "$%.4f", max(0, env.settings.budgetLimitUSD - spent)))
                    HStack {
                        Text("Limit")
                        Spacer()
                        Text("$").foregroundColor(.secondary)
                        TextField("20.00", text: $limitText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .onSubmit { saveLimit() }
                        Button("Set") { saveLimit() }
                            .buttonStyle(.bordered)
                            .disabled(Double(limitText) == nil)
                    }
                    Button("Reset spending") { env.settings.totalSpentUSD = 0; spent = 0 }
                } header: {
                    Text("Budget")
                } footer: {
                    Text("Spend is estimated from token usage. Editing the limit updates the remaining amount.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI Assistant")
            .onAppear {
                hasKey = env.settings.hasAPIKey
                spent = env.settings.totalSpentUSD
                limitText = String(format: "%.2f", env.settings.budgetLimitUSD)
            }
        }
    }

    private func syncDownload() async {
        syncing = true
        syncStatus = "Logging in to AnkiWeb…"
        do {
            let hkey = try await env.gateway.syncLogin(username: ankiUser, password: ankiPass)
            env.settings.ankiWebHKey = hkey
            env.settings.ankiWebUsername = ankiUser
            ankiPass = ""
            syncStatus = "Downloading collection…"
            try await env.gateway.downloadFromAnkiWeb(hkey: hkey)
            syncStatus = "✓ Collection downloaded. Open the Decks tab."
        } catch {
            syncStatus = "✗ \(error)"
        }
        syncing = false
    }

    private func saveLimit() {
        guard let value = Double(limitText), value >= 0 else { return }
        env.settings.budgetLimitUSD = value
        limitText = String(format: "%.2f", value)
    }

    private func testConnection() async {
        guard let key = env.settings.apiKey else { return }
        testing = true; testResult = nil
        let client = ClaudeAPIClient(apiKey: key)
        let result = await client.chat(
            systemPrompt: "Reply with the single word: OK",
            history: [ChatTurn(role: "user", content: "ping")])
        switch result {
        case .success: testResult = "✓ Connection works."
        case .failure(let e): testResult = "✗ " + AIErrorPresenter.message(for: e)
        }
        testing = false
    }
}
