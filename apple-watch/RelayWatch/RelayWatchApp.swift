import SwiftUI

@main
struct RelayWatchApp: App {
    @StateObject private var model = RelayWatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RelayWatchRootView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.appBecameInactive() }
        }
    }
}
