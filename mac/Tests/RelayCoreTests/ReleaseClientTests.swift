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
        license: "Apache-2.0",
        mac: ReleaseMac(
            version: "1.1.0",
            artifact: "Relay.dmg",
            architecture: "arm64"
        ),
        watch: ReleaseWatch(
            versionName: "1.1.0",
            versionCode: 10100,
            artifact: "relay-wear.apk",
            minimumWearOS: 4
        ),
        codex: CodexCompatibility(
            minimumVersion: "0.144.0",
            maximumVersion: "0.144.x"
        ),
        artifacts: [
            ReleaseArtifact(
                name: "Relay.dmg",
                version: "1.1.0",
                architecture: "arm64",
                sha256: String(repeating: "a", count: 64),
                signed: true
            ),
            ReleaseArtifact(
                name: "relay-wear.apk",
                version: "1.1.0",
                architecture: "universal",
                sha256: String(repeating: "b", count: 64),
                signed: true
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
        license: "Apache-2.0",
        mac: ReleaseMac(
            version: "2.0.0",
            artifact: "Relay.dmg",
            architecture: "arm64"
        ),
        watch: ReleaseWatch(
            versionName: "2.0.0",
            versionCode: 20000,
            artifact: "relay-wear.apk",
            minimumWearOS: 4
        ),
        codex: CodexCompatibility(
            minimumVersion: "0.144.0",
            maximumVersion: "0.144.x"
        ),
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
            license: originalPayload.license,
            mac: originalPayload.mac,
            watch: originalPayload.watch,
            codex: originalPayload.codex,
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
        sha256: String(repeating: "0", count: 64),
        signed: true
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
