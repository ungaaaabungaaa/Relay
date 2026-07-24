import CryptoKit
import Foundation
import Testing
@testable import RelayCore

@Test
func platformToolsRejectsWrongDigestAndDeletesTheDownload() async throws {
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let archive = temporary.appendingPathComponent("platform-tools.zip")
    try Data("changed archive".utf8).write(to: archive)
    let downloader = FakeArtifactDownloader(
        downloaded: DownloadedArtifact(
            fileURL: archive,
            finalURL: URL(string: "https://dl.google.com/android/repository/platform-tools.zip")!
        )
    )
    let extractor = FakeArchiveExtractor()
    let manager = PlatformToolsManager(
        downloader: downloader,
        extractor: extractor
    )
    let artifact = PlatformToolsArtifact(
        version: "test",
        downloadURL: URL(string: "https://dl.google.com/android/repository/platform-tools.zip")!,
        sha256: String(repeating: "0", count: 64),
        allowedHost: "dl.google.com"
    )

    await #expect(throws: PlatformToolsError.digestMismatch) {
        try await manager.install(
            artifact: artifact,
            installationRoot: temporary.appendingPathComponent("installed")
        )
    }
    #expect(!FileManager.default.fileExists(atPath: archive.path))
    #expect(extractor.callCount == 0)
}

@Test
func platformToolsRejectsAnUnapprovedRedirectAndKeepsTheOldInstall() async throws {
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let installationRoot = temporary.appendingPathComponent("installed")
    let oldADB = installationRoot.appendingPathComponent("platform-tools/adb")
    try FileManager.default.createDirectory(
        at: oldADB.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("old adb".utf8).write(to: oldADB)
    let archive = temporary.appendingPathComponent("redirected.zip")
    try Data("archive".utf8).write(to: archive)
    let downloader = FakeArtifactDownloader(
        downloaded: DownloadedArtifact(
            fileURL: archive,
            finalURL: URL(string: "https://example.com/platform-tools.zip")!
        )
    )
    let manager = PlatformToolsManager(
        downloader: downloader,
        extractor: FakeArchiveExtractor()
    )
    let digest = SHA256.hash(data: Data("archive".utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    let artifact = PlatformToolsArtifact(
        version: "test",
        downloadURL: URL(string: "https://dl.google.com/android/repository/platform-tools.zip")!,
        sha256: digest,
        allowedHost: "dl.google.com"
    )

    await #expect(throws: PlatformToolsError.unapprovedSource) {
        try await manager.install(
            artifact: artifact,
            installationRoot: installationRoot
        )
    }
    #expect(String(data: try Data(contentsOf: oldADB), encoding: .utf8) == "old adb")
    #expect(!FileManager.default.fileExists(atPath: archive.path))
}

@Test
func platformToolsInstallsOnlyAfterDigestAndADBVerification() async throws {
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let archive = temporary.appendingPathComponent("platform-tools.zip")
    let archiveData = Data("verified archive".utf8)
    try archiveData.write(to: archive)
    let digest = SHA256.hash(data: archiveData)
        .map { String(format: "%02x", $0) }
        .joined()
    let manager = PlatformToolsManager(
        downloader: FakeArtifactDownloader(
            downloaded: DownloadedArtifact(
                fileURL: archive,
                finalURL: URL(string: "https://dl.google.com/android/repository/platform-tools.zip")!
            )
        ),
        extractor: FakeArchiveExtractor(createADB: true)
    )

    let adb = try await manager.install(
        artifact: PlatformToolsArtifact(
            version: "test",
            downloadURL: URL(string: "https://dl.google.com/android/repository/platform-tools.zip")!,
            sha256: digest,
            allowedHost: "dl.google.com"
        ),
        installationRoot: temporary.appendingPathComponent("installed")
    )

    #expect(FileManager.default.isExecutableFile(atPath: adb.path))
    #expect(!FileManager.default.fileExists(atPath: archive.path))
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("relay-platform-tools-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class FakeArtifactDownloader: ArtifactDownloading, @unchecked Sendable {
    let downloaded: DownloadedArtifact

    init(downloaded: DownloadedArtifact) {
        self.downloaded = downloaded
    }

    func download(from url: URL, allowedHost: String) async throws -> DownloadedArtifact {
        downloaded
    }
}

private final class FakeArchiveExtractor: ArchiveExtracting, @unchecked Sendable {
    private let createADB: Bool
    private(set) var callCount = 0

    init(createADB: Bool = false) {
        self.createADB = createADB
    }

    func extract(archive: URL, to destination: URL) async throws {
        callCount += 1
        if createADB {
            let adb = destination.appendingPathComponent("platform-tools/adb")
            try FileManager.default.createDirectory(
                at: adb.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("adb".utf8).write(to: adb)
        }
    }
}
