import CryptoKit
import Foundation
import Testing
@testable import RelayCore

@Test
func cloudDeviceLoginUsesPKCEAndNeverPlacesEmailInURL() async throws {
    let recorder = RequestRecorder(
        response: HTTPURLResponse(
            url: URL(string: "https://api.relayforcodex.com/cloud/v1/auth/device-sessions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!,
        data: Data(#"{"id":"login-1","verificationURL":"https://relayforcodex.com/verify","expiresAt":600000}"#.utf8)
    )
    let client = RelayCloudClient(transport: recorder.send)
    let session = try await client.startDeviceLogin(email: "owner@example.com")

    #expect(session.id == "login-1")
    let request = try #require(await recorder.lastRequest)
    #expect(request.url?.absoluteString == "https://api.relayforcodex.com/cloud/v1/auth/device-sessions")
    #expect(request.url?.absoluteString.contains("owner@example.com") == false)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["email"] == "owner@example.com")
    #expect((json["pkceChallenge"]?.count ?? 0) >= 43)
    #expect((session.pkceVerifier.count) >= 43)
}

@Test
func cloudTokenPollingSendsVerifierAndStoresNoPassword() async throws {
    let recorder = RequestRecorder(
        response: HTTPURLResponse(
            url: URL(string: "https://api.relayforcodex.com/cloud/v1/auth/device-sessions/login-1/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!,
        data: Data(#"{"accessToken":"access","accessExpiresAt":901000,"refreshToken":"refresh","refreshExpiresAt":2592001000}"#.utf8)
    )
    let client = RelayCloudClient(transport: recorder.send)
    let tokens = try await client.pollForToken(
        sessionID: "login-1",
        pkceVerifier: "verifier"
    )

    #expect(tokens?.refreshToken == "refresh")
    let request = try #require(await recorder.lastRequest)
    #expect(String(data: try #require(request.httpBody), encoding: .utf8)?.contains("verifier") == true)
    #expect(String(data: try #require(request.httpBody), encoding: .utf8)?.contains("password") == false)
}

@Test
func cloudClientRegistersOneHostAndCreatesItsPairingSession() async throws {
    let recorder = SequenceRequestRecorder(responses: [
        Data(#"{"id":"host-1","credential":"host-secret"}"#.utf8),
        Data(#"{"token":"pair-token","code":"ABC123","accountId":"account-1","expiresAt":301000,"sessionNonce":"c2Vzc2lvbi1ub25jZS0xMjM0NTY","macFingerprint":"MAC FP"}"#.utf8),
    ])
    let client = RelayCloudClient(transport: recorder.send)
    let host = try await client.registerHost(
        accessToken: "access",
        name: "My Mac",
        signingPublicKey: "signing-key",
        agreementPublicKey: "agreement-key"
    )
    let pairing = try await client.createPairingSession(
        accessToken: "access",
        hostID: host.id,
        macFingerprint: "MAC FP"
    )

    #expect(host.id == "host-1")
    #expect(pairing.code == "ABC123")
    let requests = await recorder.requests
    #expect(requests.map(\.url?.path) == [
        "/cloud/v1/hosts",
        "/cloud/v1/hosts/host-1/pairing-sessions",
    ])
    #expect(requests.allSatisfy {
        $0.value(forHTTPHeaderField: "authorization") == "Bearer access"
    })
}

@Test
func cloudClientRecoversPendingRequestsAndDerivesTheWatchFingerprint() async throws {
    let signingKey = "-----BEGIN PUBLIC KEY-----\nAQID\n-----END PUBLIC KEY-----\n"
    let agreementKey = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        .base64EncodedString()
    let response = try JSONSerialization.data(withJSONObject: [
        "requests": [[
            "requestId": "request-1",
            "signingPublicKey": signingKey,
            "agreementPublicKey": agreementKey,
            "expiresAt": 301_000,
            "metadata": [
                "platform": "watch-os", "manufacturer": "Apple",
                "model": "Apple Watch", "osVersion": "10",
                "appVersion": "0.2.0", "screenShape": "rounded-rect",
            ],
        ]],
    ])
    let recorder = SequenceRequestRecorder(responses: [response])
    let client = RelayCloudClient(transport: recorder.send)

    let requests = try await client.pendingPairingRequests(
        accessToken: "access", pairingToken: "pair-token"
    )
    #expect(requests.count == 1)
    #expect(requests[0].fingerprint.split(separator: ":").count == 8)
    #expect(requests[0].signingPublicKey == signingKey)
    let sent = try #require(await recorder.requests.first)
    #expect(sent.httpMethod == "GET")
    #expect(sent.url?.path == "/cloud/v1/pairing-sessions/pair-token/requests")
    #expect(sent.value(forHTTPHeaderField: "authorization") == "Bearer access")
    #expect(sent.url?.query == nil)
}

@Test
func cloudClientApprovesDeniesRevokesAndDeletesWithoutURLSecrets() async throws {
    let recorder = SequenceRequestRecorder(responses: [
        Data(#"{"id":"watch-1","hostId":"host-1","sessionNonce":"bm9uY2U"}"#.utf8),
        Data(#"{"ok":true}"#.utf8),
        Data(#"{"ok":true}"#.utf8),
        Data(#"{"hostId":"host-1","hostCredential":"rotated-host-secret","revokedDeviceCount":1}"#.utf8),
        Data(#"{"ok":true}"#.utf8),
    ])
    let client = RelayCloudClient(transport: recorder.send)
    let approved = try await client.approvePairing(
        accessToken: "access",
        pairingToken: "pair-token",
        requestID: "request-1",
        deviceID: "watch-1",
        credentialHash: "credential-hash",
        approvedPayload: RelayCloudPairingPayloadEnvelope(
            version: 1,
            nonce: "payload-nonce",
            ciphertext: "opaque-ciphertext"
        )
    )
    try await client.denyPairing(
        accessToken: "access",
        pairingToken: "other-pair-token",
        requestID: "request-2"
    )
    try await client.revokeDevice(
        accessToken: "access",
        deviceID: "watch-1"
    )
    let stopped = try await client.emergencyStop(accessToken: "access")
    try await client.deleteAccount(accessToken: "access")

    #expect(approved.id == "watch-1")
    #expect(stopped.hostCredential == "rotated-host-secret")
    let requests = await recorder.requests
    let approvalBody = try #require(requests.first?.httpBody)
    let approvalObject = try #require(
        JSONSerialization.jsonObject(with: approvalBody) as? [String: Any]
    )
    #expect(approvalObject["credentialHash"] as? String == "credential-hash")
    #expect(approvalObject["credential"] == nil)
    #expect(
        (approvalObject["approvedPayload"] as? [String: Any])?["ciphertext"]
            as? String == "opaque-ciphertext"
    )
    #expect(requests.map(\.url?.path) == [
        "/cloud/v1/pairing-sessions/pair-token/approve",
        "/cloud/v1/pairing-sessions/other-pair-token/deny",
        "/cloud/v1/devices/watch-1/revoke",
        "/cloud/v1/emergency-stop",
        "/cloud/v1/account",
    ])
    #expect(requests.allSatisfy { $0.url?.query == nil })
}

private actor RequestRecorder {
    let response: HTTPURLResponse
    let data: Data
    private(set) var lastRequest: URLRequest?

    init(response: HTTPURLResponse, data: Data) {
        self.response = response
        self.data = data
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (data, response)
    }
}

private actor SequenceRequestRecorder {
    private var responses: [Data]
    private(set) var requests: [URLRequest] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = responses.removeFirst()
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
