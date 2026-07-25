import Foundation
import RelayCore

@MainActor
final class PairingDiscoveryAdvertiser {
    private var service: NetService?

    func publish(session: AdminPairingSession) {
        stop()
        let service = NetService(
            domain: "local.",
            type: "_relay-pair._tcp.",
            name: "Relay",
            port: 43_117
        )
        service.setTXTRecord(
            NetService.data(
                fromTXTRecord: [
                    "token": Data(session.discoveryToken.utf8),
                    "origin": Data(session.origin.absoluteString.utf8),
                    "api": Data("1".utf8),
                ]
            )
        )
        service.publish()
        self.service = service
    }

    func stop() {
        service?.stop()
        service = nil
    }
}
