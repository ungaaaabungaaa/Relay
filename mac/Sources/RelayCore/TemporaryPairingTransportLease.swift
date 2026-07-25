import Foundation

public actor TemporaryPairingTransportLease {
    public typealias CloseOperation = @Sendable () async -> Void

    private var closeOperation: CloseOperation?
    private var expiryTask: Task<Void, Never>?

    public init() {}

    public func start(
        for duration: Duration,
        close: @escaping CloseOperation
    ) {
        expiryTask?.cancel()
        expiryTask = nil
        closeOperation = close
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
                await self?.finish()
            } catch is CancellationError {
                return
            } catch {
                await self?.finish()
            }
        }
    }

    public func finish() async {
        expiryTask?.cancel()
        expiryTask = nil
        guard let closeOperation else {
            return
        }
        self.closeOperation = nil
        await closeOperation()
    }

    public func promote() {
        expiryTask?.cancel()
        expiryTask = nil
        closeOperation = nil
    }
}
