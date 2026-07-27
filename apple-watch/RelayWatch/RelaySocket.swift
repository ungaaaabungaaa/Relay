import Foundation

protocol RelaySocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

protocol RelaySocketFactory: Sendable {
    func connect(_ request: URLRequest) async throws -> any RelaySocket
}

enum RelaySocketError: Error, Equatable, Sendable {
    case handshakeRejected(Int)
    case network
    case closed
}

struct RelayWebSocketHandshakeFailure: Error, Equatable, Sendable {
    let statusCode: Int?
}

protocol RelayWebSocketHandshakeDriving: Sendable {
    func open(_ request: URLRequest) async throws -> any RelaySocket
}

final class URLSessionRelaySocketFactory: RelaySocketFactory, @unchecked Sendable {
    private let handshakeDriver: any RelayWebSocketHandshakeDriving

    init(session: URLSession = .shared) {
        self.handshakeDriver = URLSessionWebSocketHandshakeDriver(
            configuration: session.configuration
        )
    }

    init(handshakeDriver: any RelayWebSocketHandshakeDriving) {
        self.handshakeDriver = handshakeDriver
    }

    func connect(_ request: URLRequest) async throws -> any RelaySocket {
        do {
            return try await handshakeDriver.open(request)
        } catch let failure as RelayWebSocketHandshakeFailure {
            if let status = failure.statusCode, status == 401 || status == 403 {
                throw RelaySocketError.handshakeRejected(status)
            }
            throw RelaySocketError.network
        } catch let error as RelaySocketError {
            throw error
        } catch is CancellationError {
            throw RelaySocketError.closed
        } catch {
            throw RelaySocketError.network
        }
    }
}

private actor URLSessionWebSocketHandshakeDriver: RelayWebSocketHandshakeDriving {
    private let delegate: URLSessionRelaySocketDelegate
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        let delegate = URLSessionRelaySocketDelegate()
        self.delegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func open(_ request: URLRequest) async throws -> any RelaySocket {
        let task = session.webSocketTask(with: request)
        try await delegate.waitUntilOpen(task)
        return URLSessionRelaySocket(task: task)
    }
}

private final class URLSessionRelaySocketDelegate: NSObject,
    URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var openings: [Int: CheckedContinuation<Void, Error>] = [:]

    func waitUntilOpen(_ task: URLSessionWebSocketTask) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    openings[task.taskIdentifier] = continuation
                }
                task.resume()
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        finish(webSocketTask, result: .success(()))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        finish(
            webSocketTask,
            result: .failure(
                RelayWebSocketHandshakeFailure(
                    statusCode: (webSocketTask.response as? HTTPURLResponse)?.statusCode
                )
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let task = task as? URLSessionWebSocketTask else { return }
        finish(
            task,
            result: .failure(
                RelayWebSocketHandshakeFailure(
                    statusCode: (task.response as? HTTPURLResponse)?.statusCode
                )
            )
        )
    }

    private func finish(
        _ task: URLSessionWebSocketTask,
        result: Result<Void, Error>
    ) {
        let continuation = lock.withLock {
            openings.removeValue(forKey: task.taskIdentifier)
        }
        continuation?.resume(with: result)
    }
}

private final class URLSessionRelaySocket: RelaySocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        do {
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
        } catch {
            throw mapped(error)
        }
    }

    func receive() async throws -> Data {
        do {
            switch try await task.receive() {
            case let .data(data):
                return data
            case let .string(value):
                return Data(value.utf8)
            @unknown default:
                throw RelaySocketError.network
            }
        } catch {
            throw mapped(error)
        }
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }

    private func mapped(_ error: Error) -> Error {
        if let status = (task.response as? HTTPURLResponse)?.statusCode,
           status == 401 || status == 403 {
            return RelaySocketError.handshakeRejected(status)
        }
        if let relayError = error as? RelaySocketError {
            return relayError
        }
        if (error as? URLError)?.code == .cancelled {
            return RelaySocketError.closed
        }
        return RelaySocketError.network
    }
}
