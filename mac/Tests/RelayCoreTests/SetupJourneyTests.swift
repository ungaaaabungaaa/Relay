import Testing
@testable import RelayCore

@Test
func setupJourneyResumesAtTheFirstIncompleteReleaseStep() {
    let journey = SetupJourney(
        codexAndIntegrityReady: true,
        tailscaleInstalled: true,
        tailscaleSignedIn: true,
        bridgePreflightPassed: true,
        platformToolsReady: false,
        watchInstalled: false,
        watchPaired: false,
        workspacesSelected: false,
        remoteAccessEnabled: false
    )

    #expect(journey.steps.count == 9)
    #expect(journey.completedCount == 4)
    #expect(journey.current?.id == .platformTools)
    #expect(journey.steps.last?.id == .remoteAccess)
}

@Test
func setupJourneyIsCompleteOnlyAfterWorkspaceAndRemoteAccess() {
    var journey = SetupJourney.complete
    #expect(journey.isComplete)

    journey = SetupJourney(
        codexAndIntegrityReady: true,
        tailscaleInstalled: true,
        tailscaleSignedIn: true,
        bridgePreflightPassed: true,
        platformToolsReady: true,
        watchInstalled: true,
        watchPaired: true,
        workspacesSelected: false,
        remoteAccessEnabled: true
    )

    #expect(!journey.isComplete)
    #expect(journey.current?.id == .workspaces)
}
