import SwiftUI

@main
struct RelayMacApp: App {
    @StateObject private var model = RelayAppModel()

    var body: some Scene {
        MenuBarExtra("Relay", systemImage: model.menuBarSymbol) {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Relay", id: "dashboard") {
            DashboardView(model: model)
        }
        .defaultSize(width: 1_020, height: 680)
        .windowResizability(.contentMinSize)
    }
}
