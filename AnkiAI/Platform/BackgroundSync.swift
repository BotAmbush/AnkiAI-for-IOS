import Foundation
import BackgroundTasks

/// Background AnkiWeb sync (M2.31). When the OS grants background app-refresh time
/// and the user is logged in to AnkiWeb, run a two-way collection sync + media
/// sync so cards stay fresh. Registered via SwiftUI's `.backgroundTask` modifier
/// and scheduled when the app backgrounds.
enum BackgroundSync {
    static let taskId = "com.evyatar.ankiai.sync"

    /// Ask the system to run us again later (best-effort; OS decides timing).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Convenience entry used by the app: reads the stored session + collection path.
    static func run() async {
        await run(hkey: AISettingsStore().ankiWebHKey,
                  collectionPath: AppEnvironment.defaultCollectionPath())
        schedule()
    }

    /// Testable core: no-ops when logged out; otherwise syncs collection + media.
    /// Never throws, but NEVER silently discards the outcome — the result (incl.
    /// full-sync-required / auth / media / network failures) is persisted via
    /// `settings` so the app can surface an actionable message on next launch.
    static func run(hkey: String?, collectionPath: String, settings: AISettingsStore = AISettingsStore()) async {
        guard let hkey, !hkey.isEmpty else { return }
        let gateway = BackendCollectionGateway(path: collectionPath)
        settings.lastBackgroundSyncDate = Date()
        do {
            let needsFull = try await gateway.sync(hkey: hkey)
            if needsFull {
                // Do NOT auto-resolve: the user must choose a direction in-app.
                settings.lastBackgroundSyncResult = "Full sync required — open AnkiAI to choose download or upload."
                return
            }
            // A successful normal sync means this phone is in sync with AnkiWeb.
            settings.collectionProvenance = .downloadedFromAnkiWeb
            do {
                try await gateway.syncMedia(hkey: hkey)
                settings.lastBackgroundSyncResult = nil
            } catch {
                settings.lastBackgroundSyncResult = "Background media sync failed: \(error)"
            }
        } catch {
            settings.lastBackgroundSyncResult = "Background sync failed: \(error)"
        }
    }
}
