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
