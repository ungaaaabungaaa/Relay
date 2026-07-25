import SwiftUI

@main
struct RelayWatchApp: App {
    @StateObject private var model = RelayWatchModel()

    var body: some Scene {
        WindowGroup {
            RelayWatchRootView(model: model)
        }
    }
}
