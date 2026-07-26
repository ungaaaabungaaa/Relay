import Foundation
import Testing
@testable import RelayCore

@Test
func adminClientAuthenticatesAndDecodesFocusedStatus() async throws {
    let transport = RecordingAdminTransport(
        statusCode: 200,
        body: """
        {
          "bridge":"running",
          "codex":"ready",
          "watch":{"host":"127.0.0.1","port":43117},
          "activeDevices":1
        }
        """
    )
    let client = AdminClient(
        baseURL: URL(string: "http://127.0.0.1:43118")!,
        token: { "admin-secret" },
        transport: transport
    )

    let status = try await client.status()
    #expect(status.bridge == "running")
    #expect(status.codex == "ready")
    #expect(status.watch.host == "127.0.0.1")
    #expect(status.activeDevices == 1)

    let request = await transport.lastRequest
    #expect(request?.httpMethod == "GET")
    #expect(request?.url?.path == "/v1/status")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer admin-secret")
}

@Test
func adminClientReturnsGenericErrorsWithoutResponseSecrets() async {
    let transport = RecordingAdminTransport(
        statusCode: 401,
        body: #"{"error":"private-server-detail"}"#
    )
    let client = AdminClient(
        baseURL: URL(string: "http://127.0.0.1:43118")!,
        token: { "admin-secret" },
        transport: transport
    )

    do {
        _ = try await client.status()
        Issue.record("Expected an authorization failure")
    } catch {
        #expect(error as? AdminClientError == .unauthorized)
        #expect(!String(describing: error).contains("private-server-detail"))
        #expect(!String(describing: error).contains("admin-secret"))
    }
}

@Test
func adminClientCreatesATokenizedPairingSession() async throws {
    let transport = RecordingAdminTransport(
        statusCode: 201,
        body: """
        {
          "id":"session-1",
          "discoveryToken":"0123456789abcdef0123456789abcdef",
          "code":"A7K9Q2",
          "expiresAt":310000,
          "macFingerprint":"ABCD:1234",
          "origin":"https://relay.example.ts.net"
        }
        """
    )
    let client = AdminClient(
        baseURL: URL(string: "http://127.0.0.1:43118")!,
        token: { "admin-secret" },
        transport: transport
    )

    let session = try await client.createPairingSession(
        origin: URL(string: "https://relay.example.ts.net")!,
        macName: "Studio Mac",
        macFingerprint: "ABCD:1234"
    )

    #expect(session.code == "A7K9Q2")
    #expect(session.discoveryToken == "0123456789abcdef0123456789abcdef")
    #expect(session.origin == URL(string: "https://relay.example.ts.net")!)
    let request = await transport.lastRequest
    #expect(request?.httpMethod == "POST")
    #expect(request?.url?.path == "/v1/pairing-sessions")
    let body = try #require(request?.httpBody)
    let document = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: String]
    )
    #expect(document == [
        "origin": "https://relay.example.ts.net",
        "macName": "Studio Mac",
        "macFingerprint": "ABCD:1234",
    ])
}

@Test
func adminClientListsAndApprovesPendingWatchMetadata() async throws {
    let transport = SequencedAdminTransport(
        responses: [
            (
                200,
                """
                {
                  "pairings":[{
                    "id":"pending-1",
                    "name":"Pixel Watch",
                    "fingerprint":"ABCD:1234",
                    "metadata":{
                      "platform":"wear-os",
                      "manufacturer":"Google",
                      "model":"Pixel Watch",
                      "osVersion":"4",
                      "appVersion":"0.2.0",
                      "screenShape":"round"
                    },
                    "expiresAt":310000
                  }]
                }
                """
            ),
            (
                200,
                """
                {
                  "device":{
                    "id":"device-1",
                    "name":"Pixel Watch",
                    "fingerprint":"ABCD:1234",
                    "createdAt":10000,
                    "revokedAt":null
                  }
                }
                """
            ),
        ]
    )
    let client = AdminClient(
        baseURL: URL(string: "http://127.0.0.1:43118")!,
        token: { "admin-secret" },
        transport: transport
    )

    let pending = try await client.pendingPairings()
    #expect(pending.first?.metadata.platform == "wear-os")
    #expect(pending.first?.metadata.model == "Pixel Watch")
    let device = try await client.approvePairing(id: "pending-1")
    #expect(device.id == "device-1")
    #expect(await transport.requests.map(\.url?.path) == [
        "/v1/pairing-sessions/pending",
        "/v1/pairing-sessions/pending-1/approve",
    ])
}

@Test
func adminClientRegistersCloudKeyAndProcessesOpaqueEnvelope() async throws {
    let transport = SequencedAdminTransport(
        responses: [
            (200, #"{"ok":true}"#),
            (
                200,
                #"{"version":1,"messageId":"response-1","accountId":"account-1","hostId":"host-1","senderId":"host-1","recipientId":"watch-1","sentAt":1000,"sequence":1,"nonce":"nonce","ciphertext":"ciphertext"}"#
            ),
        ]
    )
    let client = AdminClient(
        token: { "admin-secret" },
        transport: transport
    )
    try await client.registerCloudDevice(
        AdminCloudDeviceRegistration(
            hostId: "host-1",
            deviceId: "watch-1",
            name: "Watch6",
            signingPublicKey: "signing",
            rootKey: "root-key",
            metadata: AdminDeviceMetadata(
                platform: "wear-os",
                manufacturer: "Samsung",
                model: "Watch6",
                osVersion: "5",
                appVersion: "1",
                screenShape: "round"
            )
        )
    )
    let outgoing = try await client.processCloudEnvelope(
        RelayTunnelEnvelope(
            version: 1,
            messageID: "request-1",
            accountID: "account-1",
            hostID: "host-1",
            senderID: "watch-1",
            recipientID: "host-1",
            sentAt: 900,
            sequence: 1,
            nonce: "nonce",
            ciphertext: "ciphertext"
        )
    )

    #expect(outgoing.senderID == "host-1")
    #expect(await transport.requests.map(\.url?.path) == [
        "/v1/cloud/devices",
        "/v1/cloud/envelopes",
    ])
}

private actor RecordingAdminTransport: AdminTransport {
    private let statusCode: Int
    private let body: Data
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = Data(body.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"]
        )!
        return (body, response)
    }
}

private actor SequencedAdminTransport: AdminTransport {
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) {
        self.responses = responses.map { ($0.0, Data($0.1.utf8)) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (
            response.1,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.0,
                httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "application/json"]
            )!
        )
    }
}
