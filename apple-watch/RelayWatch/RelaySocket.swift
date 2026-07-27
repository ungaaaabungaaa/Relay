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

final class URLSessionRelaySocketFactory: RelaySocketFactory, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(_ request: URLRequest) async throws -> any RelaySocket {
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionRelaySocket(task: task)
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
