import SwiftUI

@main
struct OpenAdventureApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = GameEngine.shared
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(settings)
                .onAppear { engine.launch() }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS may end a backgrounded app at any time; keep the cave safe.
            if phase != .active { engine.autosave() }
        }
    }
}
