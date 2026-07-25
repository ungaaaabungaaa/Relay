import Foundation
import Testing
@testable import RelayCore

@Test
func betaBuildsUseTheBetaFeedWhileStableBuildsStayStable() {
    let stable = URL(string: "https://ungaaaabungaaa.github.io/Relay/appcast.xml")!
    let beta = URL(string: "https://ungaaaabungaaa.github.io/Relay/appcast-beta.xml")!

    #expect(
        UpdateChannel.feedURL(
            version: "1.0.0",
            stable: stable,
            beta: beta,
            betaOptIn: false
        ) == stable
    )
    #expect(
        UpdateChannel.feedURL(
            version: "0.2.0-beta.1",
            stable: stable,
            beta: beta,
            betaOptIn: false
        ) == beta
    )
    #expect(
        UpdateChannel.feedURL(
            version: "1.0.0",
            stable: stable,
            beta: beta,
            betaOptIn: true
        ) == beta
    )
}
