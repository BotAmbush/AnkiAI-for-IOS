import SwiftUI

@main
struct AnkiAIApp: App {
    @StateObject private var env = AppEnvironment()
    @StateObject private var forcedStudy = ForcedStudyManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(forcedStudy)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { BackgroundSync.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundSync.taskId)) {
            await BackgroundSync.run()
        }
    }
}
