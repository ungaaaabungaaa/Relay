import SwiftUI

@main
struct RelayMacApp: App {
    @NSApplicationDelegateAdaptor(RelayAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
