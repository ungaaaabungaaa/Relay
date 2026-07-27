import Foundation
import Sparkle

enum RelayUpdateFailure: Equatable {
    case unavailable
}

enum RelayUpdateState: Equatable {
    case unknown
    case checking
    case current
    case available(version: String)
    case failed(RelayUpdateFailure)
}

@MainActor
final class RelayUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var state: RelayUpdateState = .unknown
    private let startUpdater: Bool
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: startUpdater,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(startUpdater: Bool = true) {
        self.startUpdater = startUpdater
        super.init()
        if startUpdater { _ = controller }
    }

    func checkForUpdates() {
        state = .checking
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordAvailable(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        recordCurrent()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        recordFailure(code: (error as NSError).code)
    }

    func recordChecking() { state = .checking }
    func recordCurrent() { state = .current }
    func recordAvailable(version: String) { state = .available(version: version) }
    func recordFailure(code: Int) {
        if code == 1_001 {
            state = .current
        } else if code == 4_007 {
            if case .available = state {} else { state = .unknown }
        } else {
            state = .failed(.unavailable)
        }
    }
}
