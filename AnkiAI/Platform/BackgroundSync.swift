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
    /// Never throws (background work must fail quietly and preserve local data).
    static func run(hkey: String?, collectionPath: String) async {
        guard let hkey, !hkey.isEmpty else { return }
        let gateway = BackendCollectionGateway(path: collectionPath)
        _ = try? await gateway.sync(hkey: hkey)
        try? await gateway.syncMedia(hkey: hkey)
    }
}
