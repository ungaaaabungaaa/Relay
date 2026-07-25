import CryptoKit
import Foundation

public enum ReleaseClientError: Error, Equatable, Sendable {
    case invalidManifest
    case invalidSignature
    case notNewer
    case unsupportedArchitecture
    case digestMismatch
    case unapprovedSource
}

public struct ReleaseArtifact: Codable, Equatable, Sendable {
    public var name: String
    public var version: String
    public var architecture: String
    public var sha256: String
    public var signed: Bool

    public init(
        name: String,
        version: String,
        architecture: String,
        sha256: String,
        signed: Bool
    ) {
        self.name = name
        self.version = version
        self.architecture = architecture
        self.sha256 = sha256.lowercased()
        self.signed = signed
    }
}

public struct ReleaseMac: Codable, Equatable, Sendable {
    public var version: String
    public var artifact: String
    public var architecture: String

    public init(version: String, artifact: String, architecture: String) {
        self.version = version
        self.artifact = artifact
        self.architecture = architecture
    }
}

public struct ReleaseWatch: Codable, Equatable, Sendable {
    public var versionName: String
    public var versionCode: Int
    public var artifact: String
    public var minimumWearOS: Int

    public init(
        versionName: String,
        versionCode: Int,
        artifact: String,
        minimumWearOS: Int
    ) {
        self.versionName = versionName
        self.versionCode = versionCode
        self.artifact = artifact
        self.minimumWearOS = minimumWearOS
    }
}

public struct CodexCompatibility: Codable, Equatable, Sendable {
    public var minimumVersion: String
    public var maximumVersion: String

    public init(minimumVersion: String, maximumVersion: String) {
        self.minimumVersion = minimumVersion
        self.maximumVersion = maximumVersion
    }
}

public struct ReleaseManifestPayload: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var tag: String
    public var version: String
    public var license: String
    public var mac: ReleaseMac
    public var watch: ReleaseWatch
    public var codex: CodexCompatibility
    public var artifacts: [ReleaseArtifact]

    public init(
        schemaVersion: Int,
        tag: String,
        version: String,
        license: String,
        mac: ReleaseMac,
        watch: ReleaseWatch,
        codex: CodexCompatibility,
        artifacts: [ReleaseArtifact]
    ) {
        self.schemaVersion = schemaVersion
        self.tag = tag
        self.version = version
        self.license = license
        self.mac = mac
        self.watch = watch
        self.codex = codex
        self.artifacts = artifacts
    }
}

public struct SignedReleaseManifest: Codable, Equatable, Sendable {
    public var payload: ReleaseManifestPayload
    public var signature: String

    public init(payload: ReleaseManifestPayload, signature: String) {
        self.payload = payload
        self.signature = signature
    }
}

public struct ReleaseClient: Sendable {
    private let publicKey: Data

    public init(publicKey: Data) {
        self.publicKey = publicKey
    }

    public func verifyManifest(
        _ data: Data,
        currentVersion: String
    ) throws -> ReleaseManifestPayload {
        let manifest: SignedReleaseManifest
        do {
            manifest = try JSONDecoder().decode(SignedReleaseManifest.self, from: data)
        } catch {
            throw ReleaseClientError.invalidManifest
        }
        guard
            let signature = Data(base64Encoded: manifest.signature),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
            key.isValidSignature(
                signature,
                for: Self.signingData(for: manifest.payload)
            )
        else {
            throw ReleaseClientError.invalidSignature
        }
        guard
            manifest.payload.schemaVersion == 1,
            manifest.payload.tag == "v\(manifest.payload.version)",
            manifest.payload.license == "Apache-2.0",
            manifest.payload.mac.version == manifest.payload.version,
            manifest.payload.mac.artifact == "Relay.dmg",
            manifest.payload.mac.architecture == "arm64",
            manifest.payload.watch.versionName == manifest.payload.version,
            manifest.payload.watch.artifact == "relay-wear.apk",
            manifest.payload.watch.versionCode > 0,
            manifest.payload.watch.minimumWearOS == 3,
            Self.isCodexVersion(manifest.payload.codex.minimumVersion),
            Self.isCodexVersion(manifest.payload.codex.maximumVersion),
            let available = SemanticVersion(manifest.payload.version),
            let current = SemanticVersion(currentVersion),
            manifest.payload.artifacts.allSatisfy({
                $0.version == manifest.payload.version
                    && $0.sha256.range(
                        of: #"^[a-f0-9]{64}$"#,
                        options: .regularExpression
                    ) != nil
            }),
            manifest.payload.artifacts.contains(where: {
                $0.name == "Relay.dmg"
                    && $0.architecture == "arm64"
                    && $0.signed
            }),
            manifest.payload.artifacts.contains(where: {
                $0.name == "relay-wear.apk"
                    && $0.architecture == "universal"
                    && $0.signed
            })
        else {
            if manifest.payload.mac.architecture != "arm64"
                || manifest.payload.artifacts.contains(where: {
                    ($0.name == "Relay.dmg" || $0.name == "relay-bridge-arm64")
                        && $0.architecture != "arm64"
                })
            {
                throw ReleaseClientError.unsupportedArchitecture
            }
            throw ReleaseClientError.invalidManifest
        }
        guard available > current else {
            throw ReleaseClientError.notNewer
        }
        return manifest.payload
    }

    public func fetchManifest(
        from url: URL,
        currentVersion: String,
        session: URLSession = .shared
    ) async throws -> ReleaseManifestPayload {
        let allowedHosts = [
            "github.com",
            "api.github.com",
            "objects.githubusercontent.com",
            "githubusercontent.com",
        ]
        guard
            url.scheme == "https",
            let host = url.host?.lowercased(),
            allowedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
        else {
            throw ReleaseClientError.unapprovedSource
        }
        let (data, response) = try await session.data(from: url)
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            throw ReleaseClientError.invalidManifest
        }
        return try verifyManifest(data, currentVersion: currentVersion)
    }

    public func verifyArtifact(
        at fileURL: URL,
        as artifact: ReleaseArtifact
    ) throws {
        guard artifact.architecture == "arm64" else {
            throw ReleaseClientError.unsupportedArchitecture
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == artifact.sha256 else {
            throw ReleaseClientError.digestMismatch
        }
    }

    public func installVerifiedArtifact(
        _ downloadedURL: URL,
        as artifact: ReleaseArtifact,
        at destinationURL: URL
    ) throws {
        try verifyArtifact(at: downloadedURL, as: artifact)
        let fileManager = FileManager.default
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".relay-update-\(UUID().uuidString)"
        )
        let backup = parent.appendingPathComponent(
            ".relay-backup-\(UUID().uuidString)"
        )
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }
        try fileManager.copyItem(at: downloadedURL, to: staging)
        let hadExisting = fileManager.fileExists(atPath: destinationURL.path)
        if hadExisting {
            try fileManager.moveItem(at: destinationURL, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destinationURL)
        } catch {
            if hadExisting, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destinationURL)
            }
            throw error
        }
    }

    public static func signingData(for payload: ReleaseManifestPayload) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(payload)) ?? Data()
    }

    private static func isCodexVersion(_ value: String) -> Bool {
        value.range(
            of: #"^\d+\.\d+\.(?:\d+|x)$"#,
            options: .regularExpression
        ) != nil
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]
    let prerelease: String?

    init?(_ value: String) {
        let sections = value.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = sections[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2, numbers.count <= 4 else {
            return nil
        }
        components = numbers + Array(
            repeating: 0,
            count: 4 - numbers.count
        )
        prerelease = sections.count == 2 ? sections[1] : nil
    }

    static func < (left: SemanticVersion, right: SemanticVersion) -> Bool {
        if left.components != right.components {
            return left.components.lexicographicallyPrecedes(right.components)
        }
        return switch (left.prerelease, right.prerelease) {
        case (.some, .none): true
        case (.none, .some): false
        case let (.some(left), .some(right)): left < right
        case (.none, .none): false
        }
    }
}
