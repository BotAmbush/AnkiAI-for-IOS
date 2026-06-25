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
    @State private var fullSyncNeeded = false

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
                    if let hkey = env.settings.ankiWebHKey {
                        Label(env.settings.ankiWebUsername ?? "Logged in", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.green)
                        Button { Task { await syncNow(hkey) } } label: {
                            HStack { Text("Sync now"); if syncing { Spacer(); ProgressView() } }
                        }.disabled(syncing)
                        if fullSyncNeeded {
                            Text("A one-way full sync is required. Choose a direction:").font(.caption).foregroundColor(.orange)
                            Button("⬇︎ Download from AnkiWeb (replace local)") { Task { await runFull(hkey, upload: false) } }.disabled(syncing)
                            Button("⬆︎ Upload to AnkiWeb (replace remote)", role: .destructive) { Task { await runFull(hkey, upload: true) } }.disabled(syncing)
                        }
                        Button("Log out", role: .destructive) {
                            env.settings.ankiWebHKey = nil; syncStatus = nil; fullSyncNeeded = false
                        }
                    } else {
                        TextField("AnkiWeb email", text: $ankiUser)
                            .textContentType(.username).keyboardType(.emailAddress)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        SecureField("AnkiWeb password", text: $ankiPass)
                        Button { Task { await loginAndDownload() } } label: {
                            HStack { Text("Log in & download collection"); if syncing { Spacer(); ProgressView() } }
                        }.disabled(syncing || ankiUser.isEmpty || ankiPass.isEmpty)
                    }
                    if let syncStatus { Text(syncStatus).font(.caption) }
                } header: {
                    Text("AnkiWeb sync")
                } footer: {
                    Text("\"Sync now\" is a two-way sync. The first time, download REPLACES the local sample with your collection. Your password is sent only to AnkiWeb; only the session key is stored (Keychain). Media (images) sync is a follow-up.")
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

    private func loginAndDownload() async {
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

    private func syncNow(_ hkey: String) async {
        syncing = true; syncStatus = "Syncing…"; fullSyncNeeded = false
        do {
            let needsFull = try await env.gateway.sync(hkey: hkey)
            if needsFull {
                fullSyncNeeded = true
                syncStatus = "Full sync required — choose a direction below."
            } else {
                syncStatus = "✓ Synced."
            }
        } catch {
            syncStatus = "✗ \(error)"
        }
        syncing = false
    }

    private func runFull(_ hkey: String, upload: Bool) async {
        syncing = true; syncStatus = upload ? "Uploading…" : "Downloading…"
        do {
            if upload { try await env.gateway.uploadToAnkiWeb(hkey: hkey) }
            else { try await env.gateway.downloadFromAnkiWeb(hkey: hkey) }
            fullSyncNeeded = false
            syncStatus = upload ? "✓ Uploaded to AnkiWeb." : "✓ Downloaded. Open the Decks tab."
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
