import Foundation

public enum UpdateChannel {
    public static func feedURL(
        version: String,
        stable: URL,
        beta: URL,
        betaOptIn: Bool
    ) -> URL {
        version.contains("-beta.") || betaOptIn ? beta : stable
    }
}
