import SwiftUI

/// Top-level navigation shell. Mirrors the Android entry points: deck picker,
/// AI insights, and settings. The reviewer/creator chats open from here.
struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var forcedStudy: ForcedStudyManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DeckListView()
                .tabItem { Label("Decks", systemImage: "rectangle.stack") }
            CardBrowserView()
                .tabItem { Label("Browse", systemImage: "magnifyingglass") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "lightbulb") }
            AISettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(get: { forcedStudy.sessionDue }, set: { _ in })) {
            ForcedStudySessionView()
                .environmentObject(env)
                .environmentObject(forcedStudy)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { forcedStudy.refresh() }
        }
    }
}
