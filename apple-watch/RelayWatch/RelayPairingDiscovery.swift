import Foundation
import Network

final class RelayPairingDiscovery: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "dev.relay.watch.pairing-discovery"
    )
    private var browser: NWBrowser?
    var onRecord: (@Sendable (RelayPairingRecord) -> Void)?
    var onFailure: (@Sendable () -> Void)?

    func start() {
        guard browser == nil else {
            return
        }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(
                type: "_relay-pair._tcp",
                domain: "local."
            ),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else {
                return
            }
            self?.onFailure?()
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                self?.inspect(result)
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private func inspect(_ result: NWBrowser.Result) {
        guard case let .bonjour(txtRecord) = result.metadata else {
            return
        }
        let values = txtRecord.dictionary.mapValues { Data($0.utf8) }
        guard let record = RelayPairingRecord.decode(values) else {
            return
        }
        onRecord?(record)
    }
}
