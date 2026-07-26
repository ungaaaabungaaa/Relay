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
    public var codex: CodexCompatibility
    public var artifacts: [ReleaseArtifact]

    public init(
        schemaVersion: Int,
        tag: String,
        version: String,
        license: String,
        mac: ReleaseMac,
        codex: CodexCompatibility,
        artifacts: [ReleaseArtifact]
    ) {
        self.schemaVersion = schemaVersion
        self.tag = tag
        self.version = version
        self.license = license
        self.mac = mac
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
        do {
            guard
                let document = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                Set(document.keys) == ["payload", "signature"],
                let rawPayload = document["payload"] as? [String: Any],
                Set(rawPayload.keys) == [
                    "schemaVersion",
                    "tag",
                    "version",
                    "license",
                    "mac",
                    "codex",
                    "artifacts",
                ],
                let rawMac = rawPayload["mac"] as? [String: Any],
                Set(rawMac.keys) == [
                    "version",
                    "artifact",
                    "architecture",
                ],
                let rawCodex = rawPayload["codex"] as? [String: Any],
                Set(rawCodex.keys) == [
                    "minimumVersion",
                    "maximumVersion",
                ],
                let rawArtifacts = rawPayload["artifacts"]
                    as? [[String: Any]],
                rawArtifacts.allSatisfy({
                    Set($0.keys) == [
                        "name",
                        "version",
                        "architecture",
                        "sha256",
                        "signed",
                    ]
                })
            else {
                throw ReleaseClientError.invalidManifest
            }
        } catch {
            throw ReleaseClientError.invalidManifest
        }

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
        let requiredArtifacts: [String: (architecture: String, signed: Bool)] = [
            "Relay.dmg": ("arm64", true),
            "Relay-\(manifest.payload.version).tar.gz": ("source", false),
            "LICENSE": ("text", false),
            "NOTICE": ("text", false),
            "THIRD_PARTY_NOTICES.md": ("text", false),
            "COMPATIBILITY.md": ("text", false),
        ]
        let artifactNames = manifest.payload.artifacts.map(\.name)
        guard
            manifest.payload.schemaVersion == 2,
            manifest.payload.tag == "v\(manifest.payload.version)",
            manifest.payload.license == "Apache-2.0",
            manifest.payload.mac.version == manifest.payload.version,
            manifest.payload.mac.artifact == "Relay.dmg",
            manifest.payload.mac.architecture == "arm64",
            Self.isCodexVersion(manifest.payload.codex.minimumVersion),
            Self.isCodexVersion(manifest.payload.codex.maximumVersion),
            let available = SemanticVersion(manifest.payload.version),
            let current = SemanticVersion(currentVersion),
            manifest.payload.artifacts.count == requiredArtifacts.count,
            Set(artifactNames).count == artifactNames.count,
            Set(artifactNames) == Set(requiredArtifacts.keys),
            manifest.payload.artifacts.allSatisfy({
                guard let required = requiredArtifacts[$0.name] else {
                    return false
                }
                return $0.version == manifest.payload.version
                    && $0.architecture == required.architecture
                    && $0.signed == required.signed
                    && $0.sha256.range(
                        of: #"^[a-f0-9]{64}$"#,
                        options: .regularExpression
                    ) != nil
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

private enum SemanticVersionIdentifier: Equatable {
    case numeric(String)
    case nonnumeric(String)
}

private struct SemanticVersion: Comparable {
    let core: [String]
    let prerelease: [SemanticVersionIdentifier]?

    init?(_ value: String) {
        let sections = value.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let rawCoreSection = sections.first else {
            return nil
        }
        let rawCore = rawCoreSection.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard
            rawCore.count == 3,
            rawCore.allSatisfy(Self.isValidNumericIdentifier)
        else {
            return nil
        }
        core = rawCore.map(String.init)

        guard sections.count == 2 else {
            prerelease = nil
            return
        }
        let rawPrerelease = sections[1].split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard
            !sections[1].isEmpty,
            rawPrerelease.allSatisfy(Self.isValidPrereleaseIdentifier)
        else {
            return nil
        }
        prerelease = rawPrerelease.map { identifier in
            let value = String(identifier)
            if identifier.utf8.allSatisfy(Self.isASCIIDigit) {
                return .numeric(value)
            }
            return .nonnumeric(value)
        }
    }

    static func < (left: SemanticVersion, right: SemanticVersion) -> Bool {
        for (leftCore, rightCore) in zip(left.core, right.core) {
            if leftCore != rightCore {
                return numericIdentifierLess(leftCore, rightCore)
            }
        }
        return switch (left.prerelease, right.prerelease) {
        case (.some, .none): true
        case (.none, .some): false
        case let (.some(leftIdentifiers), .some(rightIdentifiers)):
            prereleaseLess(leftIdentifiers, rightIdentifiers)
        case (.none, .none): false
        }
    }

    private static func prereleaseLess(
        _ left: [SemanticVersionIdentifier],
        _ right: [SemanticVersionIdentifier]
    ) -> Bool {
        for (leftIdentifier, rightIdentifier) in zip(left, right) {
            guard leftIdentifier != rightIdentifier else {
                continue
            }
            return switch (leftIdentifier, rightIdentifier) {
            case let (.numeric(left), .numeric(right)):
                numericIdentifierLess(left, right)
            case (.numeric, .nonnumeric): true
            case (.nonnumeric, .numeric): false
            case let (.nonnumeric(left), .nonnumeric(right)): left < right
            }
        }
        return left.count < right.count
    }

    private static func numericIdentifierLess(
        _ left: String,
        _ right: String
    ) -> Bool {
        if left.utf8.count != right.utf8.count {
            return left.utf8.count < right.utf8.count
        }
        return left < right
    }

    private static func isValidNumericIdentifier(
        _ value: Substring
    ) -> Bool {
        !value.isEmpty
            && value.utf8.allSatisfy(Self.isASCIIDigit)
            && (value == "0" || value.first != "0")
    }

    private static func isValidPrereleaseIdentifier(
        _ value: Substring
    ) -> Bool {
        guard
            !value.isEmpty,
            value.utf8.allSatisfy(Self.isASCIIAlphaNumericOrHyphen)
        else {
            return false
        }
        return !value.utf8.allSatisfy(Self.isASCIIDigit)
            || value == "0"
            || value.first != "0"
    }

    private static func isASCIIDigit(_ character: UInt8) -> Bool {
        character >= 0x30 && character <= 0x39
    }

    private static func isASCIIAlphaNumericOrHyphen(
        _ character: UInt8
    ) -> Bool {
        isASCIIDigit(character)
            || (character >= 0x41 && character <= 0x5A)
            || (character >= 0x61 && character <= 0x7A)
            || character == 0x2D
    }
}
