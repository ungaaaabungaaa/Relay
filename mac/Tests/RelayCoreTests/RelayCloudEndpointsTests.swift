import Foundation
import Testing
@testable import RelayCore

@Test
func cloudEndpointsDeriveOneMatchedHTTPAndWebSocketConfiguration() throws {
    let production = try RelayCloudEndpoints.resolve(
        processEnvironment: [:], isDebugBuild: false
    )
    #expect(production.environment == .production)
    #expect(production.apiOrigin.absoluteString == "https://api.relayforcodex.com")
    #expect(production.hostWebSocketURL.absoluteString ==
        "wss://api.relayforcodex.com/cloud/v1/connect/host")

    let local = try RelayCloudEndpoints.resolve(
        processEnvironment: ["RELAY_CLOUD_ORIGIN": "http://127.0.0.1:8787"],
        isDebugBuild: true
    )
    #expect(local.environment == .localDevelopment)
    #expect(local.apiOrigin.absoluteString == "http://127.0.0.1:8787")
    #expect(local.hostWebSocketURL.absoluteString ==
        "ws://127.0.0.1:8787/cloud/v1/connect/host")
}

@Test(arguments: [
    "http://api.example.com",
    "https://user@example.com",
    "https://api.example.com/relay",
    "https://api.example.com?mode=test",
])
func cloudEndpointsRejectUnsafeDebugOrigins(_ origin: String) {
    #expect(throws: RelayCloudEndpointError.invalidDevelopmentOrigin) {
        try RelayCloudEndpoints.resolve(
            processEnvironment: ["RELAY_CLOUD_ORIGIN": origin],
            isDebugBuild: true
        )
    }
}

@Test
func cloudEndpointsRejectEveryReleaseOverrideInsteadOfFallingBack() {
    #expect(throws: RelayCloudEndpointError.releaseOverrideForbidden) {
        try RelayCloudEndpoints.resolve(
            processEnvironment: ["RELAY_CLOUD_ORIGIN": "https://staging-api.relayforcodex.com"],
            isDebugBuild: false
        )
    }
}
