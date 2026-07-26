import CryptoKit
import Foundation
import Testing
@testable import RelayCore

@Test
func bundledReleaseMetadataProvidesTheExpectedVersion() throws {
    let data = Data(#"{"version":"0.2.0-beta.1","apiVersion":1}"#.utf8)

    let metadata = try BundledReleaseMetadata.decode(data)

    #expect(metadata.version == "0.2.0-beta.1")
    #expect(metadata.apiVersion == 1)
    #expect(throws: BundledReleaseMetadataError.invalid) {
        try BundledReleaseMetadata.decode(
            Data(#"{"version":"","apiVersion":2}"#.utf8)
        )
    }
}

@Test
func releaseClientVerifiesSignedManifestAndRejectsDowngrades() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let client = ReleaseClient(publicKey: signingKey.publicKey.rawRepresentation)
    let payload = validReleasePayload(version: "1.1.0")
    let signature = try signingKey.signature(
        for: ReleaseClient.signingData(for: payload)
    )
    let manifest = SignedReleaseManifest(
        payload: payload,
        signature: signature.base64EncodedString()
    )
    let data = try JSONEncoder().encode(manifest)

    #expect(try client.verifyManifest(data, currentVersion: "1.0.0") == payload)
    var legacyPayload = payload
    legacyPayload.schemaVersion = 1
    let legacySignature = try signingKey.signature(
        for: ReleaseClient.signingData(for: legacyPayload)
    )
    let legacyManifest = SignedReleaseManifest(
        payload: legacyPayload,
        signature: legacySignature.base64EncodedString()
    )
    #expect(throws: ReleaseClientError.invalidManifest) {
        try client.verifyManifest(
            JSONEncoder().encode(legacyManifest),
            currentVersion: "1.0.0"
        )
    }
    #expect(throws: ReleaseClientError.notNewer) {
        try client.verifyManifest(data, currentVersion: "1.1.0")
    }
}

@Test
func releaseClientRejectsUnknownRawPayloadProperties() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let client = ReleaseClient(publicKey: signingKey.publicKey.rawRepresentation)
    let payload = validReleasePayload(version: "1.1.0")
    let signature = try signingKey.signature(
        for: ReleaseClient.signingData(for: payload)
    )
    let manifest = SignedReleaseManifest(
        payload: payload,
        signature: signature.base64EncodedString()
    )
    var document = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(manifest)
        ) as? [String: Any]
    )
    var rawPayload = try #require(document["payload"] as? [String: Any])
    rawPayload["watch"] = ["artifact": "retired-watch-package"]
    document["payload"] = rawPayload
    let data = try JSONSerialization.data(
        withJSONObject: document,
        options: [.sortedKeys]
    )

    #expect(throws: ReleaseClientError.invalidManifest) {
        try client.verifyManifest(data, currentVersion: "1.0.0")
    }
}

@Test
func releaseClientRequiresTheExactSixReleaseArtifacts() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let client = ReleaseClient(publicKey: signingKey.publicKey.rawRepresentation)
    let validPayload = validReleasePayload(version: "1.1.0")
    #expect(
        validPayload.artifacts.map(\.name) == [
            "Relay.dmg",
            "Relay-1.1.0.tar.gz",
            "LICENSE",
            "NOTICE",
            "THIRD_PARTY_NOTICES.md",
            "COMPATIBILITY.md",
        ]
    )

    let missing = Array(validPayload.artifacts.dropLast())
    let extra = validPayload.artifacts + [
        ReleaseArtifact(
            name: "unexpected.txt",
            version: "1.1.0",
            architecture: "text",
            sha256: String(repeating: "f", count: 64),
            signed: false
        ),
    ]
    var duplicate = validPayload.artifacts
    duplicate[duplicate.count - 1] = duplicate[2]
    var wrongName = validPayload.artifacts
    wrongName[wrongName.count - 1].name = "README.md"

    for artifacts in [missing, extra, duplicate, wrongName] {
        var payload = validPayload
        payload.artifacts = artifacts
        let signature = try signingKey.signature(
            for: ReleaseClient.signingData(for: payload)
        )
        let manifest = SignedReleaseManifest(
            payload: payload,
            signature: signature.base64EncodedString()
        )

        #expect(throws: ReleaseClientError.invalidManifest) {
            try client.verifyManifest(
                JSONEncoder().encode(manifest),
                currentVersion: "1.0.0"
            )
        }
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
        schemaVersion: 2,
        tag: "v2.0.0",
        version: "2.0.0",
        license: "Apache-2.0",
        mac: ReleaseMac(
            version: "2.0.0",
            artifact: "Relay.dmg",
            architecture: "arm64"
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
            schemaVersion: 2,
            tag: "v2.0.1",
            version: "2.0.1",
            license: originalPayload.license,
            mac: originalPayload.mac,
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

private func validReleasePayload(version: String) -> ReleaseManifestPayload {
    ReleaseManifestPayload(
        schemaVersion: 2,
        tag: "v\(version)",
        version: version,
        license: "Apache-2.0",
        mac: ReleaseMac(
            version: version,
            artifact: "Relay.dmg",
            architecture: "arm64"
        ),
        codex: CodexCompatibility(
            minimumVersion: "0.144.0",
            maximumVersion: "0.144.x"
        ),
        artifacts: [
            ReleaseArtifact(
                name: "Relay.dmg",
                version: version,
                architecture: "arm64",
                sha256: String(repeating: "a", count: 64),
                signed: true
            ),
            ReleaseArtifact(
                name: "Relay-\(version).tar.gz",
                version: version,
                architecture: "source",
                sha256: String(repeating: "b", count: 64),
                signed: false
            ),
            ReleaseArtifact(
                name: "LICENSE",
                version: version,
                architecture: "text",
                sha256: String(repeating: "c", count: 64),
                signed: false
            ),
            ReleaseArtifact(
                name: "NOTICE",
                version: version,
                architecture: "text",
                sha256: String(repeating: "d", count: 64),
                signed: false
            ),
            ReleaseArtifact(
                name: "THIRD_PARTY_NOTICES.md",
                version: version,
                architecture: "text",
                sha256: String(repeating: "e", count: 64),
                signed: false
            ),
            ReleaseArtifact(
                name: "COMPATIBILITY.md",
                version: version,
                architecture: "text",
                sha256: String(repeating: "f", count: 64),
                signed: false
            ),
        ]
    )
}
