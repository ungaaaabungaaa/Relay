import CryptoKit
import Foundation

public enum PlatformToolsError: Error, Equatable, Sendable {
    case unapprovedSource
    case digestMismatch
    case extractionFailed
    case missingADB
}

public struct PlatformToolsArtifact: Equatable, Sendable {
    public var version: String
    public var downloadURL: URL
    public var sha256: String
    public var allowedHost: String

    public init(
        version: String,
        downloadURL: URL,
        sha256: String,
        allowedHost: String
    ) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256.lowercased()
        self.allowedHost = allowedHost.lowercased()
    }

    public static let stableDarwin = PlatformToolsArtifact(
        version: "37.0.0",
        downloadURL: URL(
            string: "https://dl.google.com/android/repository/platform-tools_r37.0.0-darwin.zip"
        )!,
        sha256: "094a1395683c509fd4d48667da0d8b5ef4d42b2abfcd29f2e8149e2f989357c7",
        allowedHost: "dl.google.com"
    )
}

public struct DownloadedArtifact: Equatable, Sendable {
    public var fileURL: URL
    public var finalURL: URL

    public init(fileURL: URL, finalURL: URL) {
        self.fileURL = fileURL
        self.finalURL = finalURL
    }
}

public protocol ArtifactDownloading: Sendable {
    func download(from url: URL, allowedHost: String) async throws -> DownloadedArtifact
}

public protocol ArchiveExtracting: Sendable {
    func extract(archive: URL, to destination: URL) async throws
}

public struct PlatformToolsManager: Sendable {
    private let downloader: any ArtifactDownloading
    private let extractor: any ArchiveExtracting

    public init(
        downloader: any ArtifactDownloading = URLSessionArtifactDownloader(),
        extractor: any ArchiveExtracting = DittoArchiveExtractor()
    ) {
        self.downloader = downloader
        self.extractor = extractor
    }

    public func install(
        artifact: PlatformToolsArtifact = .stableDarwin,
        installationRoot: URL
    ) async throws -> URL {
        let fileManager = FileManager.default
        guard
            artifact.downloadURL.scheme == "https",
            artifact.downloadURL.host?.lowercased() == artifact.allowedHost
        else {
            throw PlatformToolsError.unapprovedSource
        }
        let downloaded = try await downloader.download(
            from: artifact.downloadURL,
            allowedHost: artifact.allowedHost
        )
        defer {
            try? fileManager.removeItem(at: downloaded.fileURL)
        }
        guard
            downloaded.finalURL.scheme == "https",
            downloaded.finalURL.host?.lowercased() == artifact.allowedHost
        else {
            throw PlatformToolsError.unapprovedSource
        }
        let archiveData = try Data(contentsOf: downloaded.fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == artifact.sha256 else {
            throw PlatformToolsError.digestMismatch
        }

        try fileManager.createDirectory(
            at: installationRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let staging = installationRoot.appendingPathComponent(
            ".platform-tools-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let backup = installationRoot.appendingPathComponent(
            ".platform-tools-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let installed = installationRoot.appendingPathComponent(
            "platform-tools",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try await extractor.extract(archive: downloaded.fileURL, to: staging)
        } catch {
            throw PlatformToolsError.extractionFailed
        }
        let stagedTools = staging.appendingPathComponent(
            "platform-tools",
            isDirectory: true
        )
        let stagedADB = stagedTools.appendingPathComponent("adb")
        guard fileManager.fileExists(atPath: stagedADB.path) else {
            throw PlatformToolsError.missingADB
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stagedADB.path
        )

        let hadExisting = fileManager.fileExists(atPath: installed.path)
        if hadExisting {
            try fileManager.moveItem(at: installed, to: backup)
        }
        do {
            try fileManager.moveItem(at: stagedTools, to: installed)
        } catch {
            if hadExisting, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: installed)
            }
            throw error
        }
        return installed.appendingPathComponent("adb")
    }
}

public struct DittoArchiveExtractor: ArchiveExtracting {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func extract(archive: URL, to destination: URL) async throws {
        let result = try await runner.run(
            CommandInvocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archive.path, destination.path]
            )
        )
        guard result.exitCode == 0 else {
            throw PlatformToolsError.extractionFailed
        }
    }
}

public struct URLSessionArtifactDownloader: ArtifactDownloading {
    public init() {}

    public func download(
        from url: URL,
        allowedHost: String
    ) async throws -> DownloadedArtifact {
        let redirectGuard = RedirectGuard(allowedHost: allowedHost)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: redirectGuard,
            delegateQueue: nil
        )
        defer {
            session.finishTasksAndInvalidate()
        }
        let (temporary, response) = try await session.download(from: url)
        guard
            !redirectGuard.blockedRedirect,
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let finalURL = response.url
        else {
            try? FileManager.default.removeItem(at: temporary)
            throw PlatformToolsError.unapprovedSource
        }
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent(
            "relay-platform-tools-\(UUID().uuidString).zip"
        )
        try FileManager.default.moveItem(at: temporary, to: owned)
        return DownloadedArtifact(fileURL: owned, finalURL: finalURL)
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHost: String
    private let lock = NSLock()
    private var blocked = false

    init(allowedHost: String) {
        self.allowedHost = allowedHost.lowercased()
    }

    var blockedRedirect: Bool {
        lock.withLock { blocked }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard
            request.url?.scheme == "https",
            request.url?.host?.lowercased() == allowedHost
        else {
            lock.withLock {
                blocked = true
            }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
