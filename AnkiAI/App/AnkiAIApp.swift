import SwiftUI

@main
struct AnkiAIApp: App {
    @StateObject private var env = AppEnvironment()
    @StateObject private var forcedStudy = ForcedStudyManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(forcedStudy)
        }
    }
}
