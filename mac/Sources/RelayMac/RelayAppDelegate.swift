import AppKit

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    private let model = RelayAppModel()
    private var statusItemController: RelayStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = RelayStatusItemController(model: model)
    }
}
