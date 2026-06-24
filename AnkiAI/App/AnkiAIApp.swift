import SwiftUI

@main
struct AnkiAIApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
        }
    }
}
