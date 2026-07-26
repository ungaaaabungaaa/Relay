import Foundation
import Testing
@testable import RelayCore

@Test
func cloudHostTunnelAuthenticatesInHeadersAndDecodesControlAndEnvelope() async throws {
    let recorder = TunnelConnectorRecorder(messages: [
        Data(
            #"""
            {"type":"pairing_request","requestId":"request-1","fingerprint":"WATCH FP","signingPublicKey":"signing","agreementPublicKey":"agreement","expiresAt":120000,"metadata":{"platform":"watch-os","manufacturer":"Apple","model":"Apple Watch","osVersion":"10","appVersion":"0.2.0","screenShape":"rounded-rect"}}
            """#.utf8
        ),
        Data(
            #"""
            {"version":1,"messageId":"message-1","accountId":"account-1","hostId":"host-1","senderId":"watch-1","recipientId":"host-1","sentAt":1000,"sequence":1,"nonce":"nonce","ciphertext":"ciphertext"}
            """#.utf8
        ),
    ])
    let tunnel = RelayCloudHostTunnel(connector: recorder.connect)
    var events: [RelayCloudTunnelEvent] = []

    for try await event in await tunnel.events(
        hostID: "host-1",
        credential: "host-secret-with-entropy"
    ) {
        events.append(event)
    }

    #expect(events.count == 3)
    #expect(events[0] == .connected)
    guard case .pairingRequest(let pairing) = events[1] else {
        Issue.record("Expected pairing request")
        return
    }
    #expect(pairing.id == "request-1")
    #expect(pairing.metadata.model == "Apple Watch")
    guard case .envelope(let envelope) = events[2] else {
        Issue.record("Expected encrypted envelope")
        return
    }
    #expect(envelope.messageID == "message-1")
    try await tunnel.send(envelope)
    #expect(
        try JSONDecoder()
            .decode(
                RelayTunnelEnvelope.self,
                from: #require(recorder.sentMessages.first)
            )
            .messageID == "message-1"
    )

    let request = try #require(recorder.request)
    #expect(request.url?.absoluteString == "wss://api.relayforcodex.com/cloud/v1/connect/host")
    #expect(request.url?.query == nil)
    #expect(
        request.value(forHTTPHeaderField: "authorization")
            == "Bearer host-secret-with-entropy"
    )
    #expect(
        request.value(forHTTPHeaderField: "x-relay-host-id")
            == "host-1"
    )
}

private final class TunnelConnectorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let messages: [Data]
    private var recordedRequest: URLRequest?
    private var sent: [Data] = []

    init(messages: [Data]) {
        self.messages = messages
    }

    var request: URLRequest? {
        lock.withLock { recordedRequest }
    }

    var sentMessages: [Data] {
        lock.withLock { sent }
    }

    func connect(_ request: URLRequest) -> any RelayCloudSocket {
        lock.withLock {
            recordedRequest = request
        }
        return RecordedRelayCloudSocket(
            messages: messages,
            onSend: { [weak self] data in
                self?.lock.withLock {
                    self?.sent.append(data)
                }
            }
        )
    }
}

private final class RecordedRelayCloudSocket: RelayCloudSocket, @unchecked Sendable {
    let messages: AsyncThrowingStream<Data, Error>
    private let onSend: @Sendable (Data) -> Void

    init(
        messages: [Data],
        onSend: @escaping @Sendable (Data) -> Void
    ) {
        self.messages = AsyncThrowingStream { continuation in
            for message in messages {
                continuation.yield(message)
            }
            continuation.finish()
        }
        self.onSend = onSend
    }

    func send(_ data: Data) async throws {
        onSend(data)
    }

    func cancel() {}
}
