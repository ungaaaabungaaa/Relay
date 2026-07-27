import Foundation

struct RelayReconnectPolicy: Equatable, Sendable {
    let maximumDelay: Duration

    init(maximumDelay: Duration = .seconds(30)) {
        self.maximumDelay = maximumDelay
    }

    func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return .seconds(1) }
        guard attempt < 5 else { return maximumDelay }
        return min(.seconds(1 << attempt), maximumDelay)
    }
}
