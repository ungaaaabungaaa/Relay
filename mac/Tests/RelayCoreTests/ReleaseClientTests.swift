import CryptoKit
import Foundation
import Testing
@testable import RelayCore

@Test
func releaseClientVerifiesSignedManifestAndRejectsDowngrades() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let client = ReleaseClient(publicKey: signingKey.publicKey.rawRepresentation)
    let payload = ReleaseManifestPayload(
        schemaVersion: 1,
        tag: "v1.1.0",
        version: "1.1.0",
        artifacts: [
            ReleaseArtifact(
                name: "Relay.dmg",
                version: "1.1.0",
                architecture: "arm64",
                sha256: String(repeating: "a", count: 64)
            ),
        ]
    )
    let signature = try signingKey.signature(
        for: ReleaseClient.signingData(for: payload)
    )
    let manifest = SignedReleaseManifest(
        payload: payload,
        signature: signature.base64EncodedString()
    )
    let data = try JSONEncoder().encode(manifest)

    #expect(try client.verifyManifest(data, currentVersion: "1.0.0") == payload)
    #expect(throws: ReleaseClientError.notNewer) {
        try client.verifyManifest(data, currentVersion: "1.1.0")
    }
}

@Test
func releaseClientRejectsTamperingAndPreservesTheInstalledArtifact() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("relay-release-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let signingKey = Curve25519.Signing.PrivateKey()
    let client = ReleaseClient(publicKey: signingKey.publicKey.rawRepresentation)
    let originalPayload = ReleaseManifestPayload(
        schemaVersion: 1,
        tag: "v2.0.0",
        version: "2.0.0",
        artifacts: []
    )
    let signature = try signingKey.signature(
        for: ReleaseClient.signingData(for: originalPayload)
    )
    let changed = SignedReleaseManifest(
        payload: ReleaseManifestPayload(
            schemaVersion: 1,
            tag: "v2.0.1",
            version: "2.0.1",
            artifacts: []
        ),
        signature: signature.base64EncodedString()
    )
    #expect(throws: ReleaseClientError.invalidSignature) {
        try client.verifyManifest(
            JSONEncoder().encode(changed),
            currentVersion: "1.0.0"
        )
    }

    let destination = temporary.appendingPathComponent("Relay.dmg")
    let downloaded = temporary.appendingPathComponent("download.dmg")
    try Data("working release".utf8).write(to: destination)
    try Data("changed byte".utf8).write(to: downloaded)
    let expected = ReleaseArtifact(
        name: "Relay.dmg",
        version: "2.0.0",
        architecture: "arm64",
        sha256: String(repeating: "0", count: 64)
    )

    #expect(throws: ReleaseClientError.digestMismatch) {
        try client.installVerifiedArtifact(
            downloaded,
            as: expected,
            at: destination
        )
    }
    #expect(
        String(data: try Data(contentsOf: destination), encoding: .utf8)
            == "working release"
    )
}
