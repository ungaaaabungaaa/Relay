import Foundation

public enum BundledReleaseMetadataError: Error, Equatable, Sendable {
    case invalid
}

public struct BundledReleaseMetadata: Codable, Equatable, Sendable {
    public var version: String
    public var apiVersion: Int

    public static func decode(_ data: Data) throws -> BundledReleaseMetadata {
        guard
            let metadata = try? JSONDecoder().decode(Self.self, from: data),
            !metadata.version.isEmpty,
            metadata.apiVersion == 1
        else {
            throw BundledReleaseMetadataError.invalid
        }
        return metadata
    }
}
