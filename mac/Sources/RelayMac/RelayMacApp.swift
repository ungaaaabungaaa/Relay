import SwiftUI

@main
struct RelayMacApp: App {
    @StateObject private var model = RelayAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            RelayUFOGlyph(size: 18)
                .frame(width: 18, height: 18)
                .accessibilityLabel("Relay")
        }
        .menuBarExtraStyle(.menu)

        Window("Relay", id: "dashboard") {
            DashboardView(model: model)
        }
        .defaultSize(width: 1_020, height: 680)
        .windowResizability(.contentMinSize)
    }
}
