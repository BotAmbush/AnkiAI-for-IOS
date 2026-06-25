import SwiftUI
import UniformTypeIdentifiers

/// AI Assistant settings. Mirrors `AiSettingsFragment` — API key entry (now
/// Keychain-backed), test connection, model info, and budget/spend tracking.
struct AISettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var forcedStudy: ForcedStudyManager
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
    @State private var backupStatus: String?
    @State private var backingUp = false
    @State private var showRestoreImporter = false
    @State private var lastBackup: BackupInfo?
    @State private var exportPickerURL: URL?
    @State private var loggedIn = false
    @State private var showUploadConfirm = false
    @State private var collectionCounts: (cards: Int, decks: Int)?

    private var provenanceLabel: String {
        switch env.settings.collectionProvenance {
        case .seededSample: return "Demo / sample (not your data)"
        case .downloadedFromAnkiWeb: return "From AnkiWeb"
        case .importedFromPackage: return "Imported from a package"
        case .createdLocally: return "Created on this phone"
        case .restoredFromBackup: return "Restored from a backup"
        case .unknown: return "Unknown origin"
        }
    }

    private var colpkgTypes: [UTType] {
        [UTType(filenameExtension: "colpkg") ?? .data, .data]
    }

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
                    if loggedIn, let hkey = env.settings.ankiWebHKey {
                        Label(env.settings.ankiWebUsername ?? "Logged in", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.green)
                        LabeledContent("This phone's collection", value: provenanceLabel)
                        if let c = collectionCounts {
                            Text("\(c.cards) cards · \(c.decks) decks").font(.caption).foregroundColor(.secondary)
                        }
                        if let bg = env.settings.lastBackgroundSyncResult, !bg.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                Text("Last background sync: \(bg)").font(.caption)
                                Button("Dismiss") { env.settings.lastBackgroundSyncResult = nil }.font(.caption)
                            }
                        }
                        Button { Task { await syncNow(hkey) } } label: {
                            HStack { Text("Sync now"); if syncing { Spacer(); ProgressView() } }
                        }.disabled(syncing)
                        if fullSyncNeeded {
                            Text("A one-way full sync is required. Choose a direction:").font(.caption).foregroundColor(.orange)
                            Button("⬇︎ Download from AnkiWeb (replace this phone)") { Task { await runDownload(hkey) } }.disabled(syncing)
                            if env.settings.isUploadForbidden {
                                Text("⬆︎ Upload is BLOCKED: this phone holds the demo/sample collection (or its origin is unknown), so it must not overwrite your AnkiWeb data. Choose Download, or restore a real backup / import first.")
                                    .font(.caption).foregroundColor(.red)
                            } else {
                                Button("⬆︎ Upload to AnkiWeb (replace remote)…", role: .destructive) { showUploadConfirm = true }
                                    .disabled(syncing)
                            }
                        }
                        Button("Log out", role: .destructive) { logOut() }
                    } else {
                        if env.settings.collectionProvenance == .seededSample {
                            Text("Not signed in. This phone has the demo/sample collection.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        TextField("AnkiWeb email", text: $ankiUser)
                            .textContentType(.username).keyboardType(.emailAddress)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        SecureField("AnkiWeb password", text: $ankiPass)
                        Button { Task { await loginAndSync() } } label: {
                            HStack { Text("Log in"); if syncing { Spacer(); ProgressView() } }
                        }.disabled(syncing || ankiUser.isEmpty || ankiPass.isEmpty)
                    }
                    if let syncStatus { Text(syncStatus).font(.caption) }
                } header: {
                    Text("AnkiWeb sync")
                } footer: {
                    Text("After logging in, AnkiAI syncs. If your phone and AnkiWeb differ you choose a direction. Upload (replacing your AnkiWeb data) is BLOCKED for the demo/sample collection and for collections of unknown origin, and otherwise requires a local backup + explicit confirmation — it is never automatic. Your password is sent only to AnkiWeb; only the session key is stored (Keychain).")
                }

                Section("Study reminders") {
                    NavigationLink {
                        ForcedStudySettingsView()
                            .environmentObject(env)
                            .environmentObject(forcedStudy)
                    } label: {
                        Label("Forced study & reminders", systemImage: "bell.badge")
                    }
                }

                Section {
                    Button { Task { await exportBackup() } } label: {
                        HStack { Text("Back up collection (.colpkg)"); if backingUp { Spacer(); ProgressView() } }
                    }.disabled(backingUp)
                    NavigationLink {
                        BackupsListView().environmentObject(env)
                    } label: { Label("Show backups", systemImage: "externaldrive") }
                    Button(role: .destructive) { showRestoreImporter = true } label: {
                        Text("Restore from .colpkg (replaces all)")
                    }.disabled(backingUp)
                    if let info = lastBackup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("✓ Saved \(info.name)").font(.caption).foregroundColor(.green)
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file)) · On My iPhone/AnkiAI/Backups")
                                .font(.caption2).foregroundColor(.secondary)
                            HStack {
                                ShareLink("Share backup", item: info.url)
                                Button("Save to Files") { exportPickerURL = info.url }
                            }.font(.caption)
                        }
                    } else if let backupStatus { Text(backupStatus).font(.caption) }
                } header: {
                    Text("Backup & restore")
                } footer: {
                    Text("Back up saves a validated .colpkg (collection + media) to On My iPhone/AnkiAI/Backups (visible in the Files app). Restore REPLACES your whole collection from a .colpkg exported by AnkiAI or Anki Desktop, or one chosen from Files/iCloud Drive.")
                }
                .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: colpkgTypes) { result in
                    guard case .success(let url) = result else { return }
                    Task { await restoreBackup(url) }
                }
                .fileExporter(isPresented: Binding(get: { exportPickerURL != nil }, set: { if !$0 { exportPickerURL = nil } }),
                              document: exportPickerURL.map { ColpkgFile(url: $0) },
                              contentType: colpkgTypes.first ?? .data,
                              defaultFilename: exportPickerURL?.deletingPathExtension().lastPathComponent) { _ in
                    exportPickerURL = nil
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
            .alert("Replace your AnkiWeb collection?", isPresented: $showUploadConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Back up & upload (replace remote)", role: .destructive) {
                    if let hkey = env.settings.ankiWebHKey { Task { await guardedUpload(hkey) } }
                }
            } message: {
                let c = collectionCounts.map { "\($0.cards) cards · \($0.decks) decks" } ?? "this phone's collection"
                Text("This OVERWRITES your entire AnkiWeb collection with this phone's (\(provenanceLabel): \(c)). Your remote data will be replaced and this cannot be undone. A local backup (.colpkg) is saved first.")
            }
            .onAppear {
                hasKey = env.settings.hasAPIKey
                spent = env.settings.totalSpentUSD
                limitText = String(format: "%.2f", env.settings.budgetLimitUSD)
                loggedIn = env.settings.isAnkiWebLoggedIn   // only a real persisted session
            }
            .task { await loadCounts() }
        }
    }

    /// Log out immediately: invalidate the session, cancel pending sync work, clear
    /// the displayed account and update the UI. Never touches the local collection.
    private func logOut() {
        env.settings.logOutAnkiWeb()
        syncing = false
        fullSyncNeeded = false
        ankiUser = ""
        ankiPass = ""
        loggedIn = false
        syncStatus = "Logged out. Your cards on this phone are unchanged."
    }

    private func loginAndSync() async {
        syncing = true
        syncStatus = "Logging in to AnkiWeb…"
        do {
            let hkey = try await env.gateway.syncLogin(username: ankiUser, password: ankiPass)
            env.settings.ankiWebHKey = hkey
            env.settings.ankiWebUsername = ankiUser
            ankiPass = ""
            loggedIn = true
            syncing = false
            // Two-way sync; if the phone and AnkiWeb diverge, the user is asked to
            // choose a direction (download vs upload) rather than auto-replacing.
            await syncNow(hkey)
        } catch {
            syncStatus = "✗ \(error)"
            syncing = false
        }
    }

    private func loadCounts() async {
        let cards = (try? await env.gateway.searchCardIds(query: "").count) ?? 0
        let decks = (try? await env.gateway.deckTree().count) ?? 0
        collectionCounts = (cards, decks)
    }

    private func syncNow(_ hkey: String) async {
        syncing = true; syncStatus = "Syncing…"; fullSyncNeeded = false
        do {
            let needsFull = try await env.gateway.sync(hkey: hkey)
            if needsFull {
                fullSyncNeeded = true
                syncStatus = "Full sync required — choose a direction below."
            } else {
                // A successful normal two-way sync means this phone is in sync with
                // AnkiWeb — it is now genuinely the user's collection.
                env.settings.collectionProvenance = .downloadedFromAnkiWeb
                syncStatus = "Syncing media…"
                do { try await env.gateway.syncMedia(hkey: hkey); syncStatus = "✓ Synced (collection + media)." }
                catch { syncStatus = "✓ Synced. ⚠︎ Media sync failed: \(error)" }
            }
        } catch {
            syncStatus = "✗ \(error)"
        }
        await loadCounts()
        syncing = false
    }

    private func runDownload(_ hkey: String) async {
        syncing = true; syncStatus = "Downloading…"
        do {
            try await env.gateway.downloadFromAnkiWeb(hkey: hkey)
            env.settings.collectionProvenance = .downloadedFromAnkiWeb
            syncStatus = "Syncing media…"
            do { try await env.gateway.syncMedia(hkey: hkey); syncStatus = "✓ Downloaded (collection + media). Open the Decks tab." }
            catch { syncStatus = "✓ Downloaded. ⚠︎ Media sync failed: \(error)" }
            fullSyncNeeded = false
        } catch {
            syncStatus = "✗ Download failed (local collection preserved): \(error)"
        }
        await loadCounts()
        syncing = false
    }

    /// Upload is gated: never for seeded/unknown collections; otherwise back up
    /// locally first, then replace the remote. Never an automatic fallback.
    private func guardedUpload(_ hkey: String) async {
        guard !env.settings.isUploadForbidden else {
            syncStatus = "✗ Upload blocked: this collection may not replace your AnkiWeb data."
            return
        }
        syncing = true
        do {
            syncStatus = "Backing up before upload…"
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try await env.gateway.backup(toPath: docs.appendingPathComponent("AnkiAI-preupload-\(stamp).colpkg").path)
            syncStatus = "Uploading (replacing remote)…"
            try await env.gateway.uploadToAnkiWeb(hkey: hkey)
            try? await env.gateway.syncMedia(hkey: hkey)
            fullSyncNeeded = false
            syncStatus = "✓ Uploaded to AnkiWeb (backup saved to Documents)."
        } catch {
            syncStatus = "✗ Upload failed: \(error)"
        }
        await loadCounts()
        syncing = false
    }

    private func exportBackup() async {
        backingUp = true; backupStatus = "Backing up…"; lastBackup = nil
        do {
            // Validated, atomic backup into Documents/Backups (Files-app visible).
            let info = try await BackupService().create { tempPath in
                try await env.gateway.backup(toPath: tempPath)
            }
            lastBackup = info
            backupStatus = nil
        } catch {
            backupStatus = "✗ \(error.localizedDescription)"
        }
        backingUp = false
    }

    private func restoreBackup(_ url: URL) async {
        backingUp = true; backupStatus = "Restoring…"
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try await env.gateway.restore(fromColpkg: url.path)
            env.settings.collectionProvenance = .restoredFromBackup
            await loadCounts()
            backupStatus = "✓ Collection restored. Open the Decks tab."
        } catch {
            backupStatus = "✗ \(error)"
        }
        backingUp = false
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
