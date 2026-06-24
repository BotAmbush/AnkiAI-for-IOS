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

                Section("Budget") {
                    LabeledContent("Spent", value: String(format: "$%.4f", spent))
                    LabeledContent("Limit", value: String(format: "$%.2f", env.settings.budgetLimitUSD))
                    Button("Reset spending") { env.settings.totalSpentUSD = 0; spent = 0 }
                }
            }
            .navigationTitle("AI Assistant")
            .onAppear {
                hasKey = env.settings.hasAPIKey
                spent = env.settings.totalSpentUSD
            }
        }
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
