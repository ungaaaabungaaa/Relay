import Foundation

public struct RelayCloudDeviceMetadata: Codable, Equatable, Sendable {
    public var platform: String
    public var manufacturer: String
    public var model: String
    public var osVersion: String
    public var appVersion: String
    public var screenShape: String
}

public struct RelayCloudPairingRequest: Codable, Equatable, Sendable {
    public var id: String
    public var fingerprint: String
    public var signingPublicKey: String
    public var agreementPublicKey: String
    public var expiresAt: Int64
    public var metadata: RelayCloudDeviceMetadata

    enum CodingKeys: String, CodingKey {
        case id = "requestId"
        case fingerprint
        case signingPublicKey
        case agreementPublicKey
        case expiresAt
        case metadata
    }
}

public enum RelayCloudTunnelEvent: Equatable, Sendable {
    case connected
    case pairingRequest(RelayCloudPairingRequest)
    case envelope(RelayTunnelEnvelope)
}

public enum RelayCloudTunnelError: Error, Equatable, Sendable {
    case invalidMessage
    case disconnected
}

public protocol RelayCloudSocket: Sendable {
    var messages: AsyncThrowingStream<Data, Error> { get }
    func open() async throws
    func send(_ data: Data) async throws
    func cancel()
}

public actor RelayCloudHostTunnel {
    public typealias Connector = @Sendable (
        URLRequest
    ) -> any RelayCloudSocket

    private let origin: URL
    private let connector: Connector
    private var socket: (any RelayCloudSocket)?

    public init(
        origin: URL = URL(
            string: "wss://api.relayforcodex.com/cloud/v1/connect/host"
        )!,
        connector: @escaping Connector = RelayCloudHostTunnel.liveConnector
    ) {
        self.origin = origin
        self.connector = connector
    }

    public init(
        endpoints: RelayCloudEndpoints,
        connector: @escaping Connector = RelayCloudHostTunnel.liveConnector
    ) {
        self.init(origin: endpoints.hostWebSocketURL, connector: connector)
    }

    public func events(
        hostID: String,
        credential: String
    ) -> AsyncThrowingStream<RelayCloudTunnelEvent, Error> {
        var request = URLRequest(url: origin)
        request.setValue(
            "Bearer \(credential)",
            forHTTPHeaderField: "authorization"
        )
        request.setValue(hostID, forHTTPHeaderField: "x-relay-host-id")
        request.setValue("no-store", forHTTPHeaderField: "cache-control")
        let connectedSocket = connector(request)
        socket?.cancel()
        socket = connectedSocket
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await connectedSocket.open()
                    continuation.yield(.connected)
                    for try await data in connectedSocket.messages {
                        continuation.yield(try Self.decode(data))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                connectedSocket.cancel()
            }
        }
    }

    public func send(_ envelope: RelayTunnelEnvelope) async throws {
        guard let socket else {
            throw RelayCloudTunnelError.disconnected
        }
        try await socket.send(try JSONEncoder().encode(envelope))
    }

    public func disconnect() {
        socket?.cancel()
        socket = nil
    }

    private static func decode(_ data: Data) throws -> RelayCloudTunnelEvent {
        if
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            object["type"] as? String == "pairing_request"
        {
            return .pairingRequest(
                try JSONDecoder().decode(
                    RelayCloudPairingRequest.self,
                    from: data
                )
            )
        }
        if let envelope = try? JSONDecoder().decode(
            RelayTunnelEnvelope.self,
            from: data
        ) {
            return .envelope(envelope)
        }
        throw RelayCloudTunnelError.invalidMessage
    }

    public static func liveConnector(
        _ request: URLRequest
    ) -> any RelayCloudSocket {
        LiveRelayCloudSocket(request: request)
    }
}

private final class LiveRelayCloudSocket: RelayCloudSocket, @unchecked Sendable {
    let messages: AsyncThrowingStream<Data, Error>
    private let socket: URLSessionWebSocketTask
    private let session: URLSession
    private let openDelegate: RelayWebSocketOpenDelegate

    init(request: URLRequest) {
        let openDelegate = RelayWebSocketOpenDelegate()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: openDelegate,
            delegateQueue: nil
        )
        let socket = session.webSocketTask(with: request)
        self.socket = socket
        self.session = session
        self.openDelegate = openDelegate
        self.messages = AsyncThrowingStream { continuation in
            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        switch try await socket.receive() {
                        case .data(let data):
                            continuation.yield(data)
                        case .string(let text):
                            continuation.yield(Data(text.utf8))
                        @unknown default:
                            throw RelayCloudTunnelError.invalidMessage
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let heartbeatTask = Task {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(20))
                        try await Self.ping(socket)
                    }
                } catch {
                    socket.cancel(
                        with: .goingAway,
                        reason: Data("Heartbeat failed".utf8)
                    )
                }
            }
            continuation.onTermination = { _ in
                receiveTask.cancel()
                heartbeatTask.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
            socket.resume()
        }
    }

    func open() async throws {
        try await openDelegate.waitUntilOpen()
    }

    func send(_ data: Data) async throws {
        try await socket.send(.data(data))
    }

    func cancel() {
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    private static func ping(
        _ socket: URLSessionWebSocketTask
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class RelayWebSocketOpenDelegate: NSObject,
    URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable
{
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func waitUntilOpen() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let stored = lock.withLock { () -> Result<Void, Error>? in
                if let result { return result }
                waiters.append(continuation)
                return nil
            }
            if let stored { continuation.resume(with: stored) }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        resolve(.success(()))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let status = (webSocketTask.response as? HTTPURLResponse)?.statusCode
        resolve(.failure(status.map(RelayCloudHandshakeError.rejected)
            ?? RelayCloudTunnelError.disconnected))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        resolve(.failure(status.map(RelayCloudHandshakeError.rejected) ?? error))
    }

    private func resolve(_ result: Result<Void, Error>) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            guard self.result == nil else { return [] }
            self.result = result
            defer { waiters.removeAll() }
            return waiters
        }
        continuations.forEach { $0.resume(with: result) }
    }
}
