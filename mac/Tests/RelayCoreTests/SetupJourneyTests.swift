import Testing
@testable import RelayCore

@Test
func setupJourneyResumesAtTheFirstIncompleteReleaseStep() {
    let journey = SetupJourney(
        codexAndIntegrityReady: true,
        signedIn: true,
        cloudConnected: true,
        watchPaired: false,
        workspacesSelected: false,
        startAtLoginEnabled: false
    )

    #expect(journey.steps.count == 6)
    #expect(journey.completedCount == 3)
    #expect(journey.current?.id == .watchPairing)
    #expect(journey.steps.last?.id == .startAtLogin)
}

@Test
func setupJourneyIsCompleteOnlyAfterWorkspaceAndLoginItemChoice() {
    var journey = SetupJourney.complete
    #expect(journey.isComplete)

    journey = SetupJourney(
        codexAndIntegrityReady: true,
        signedIn: true,
        cloudConnected: true,
        watchPaired: true,
        workspacesSelected: false,
        startAtLoginEnabled: true
    )

    #expect(!journey.isComplete)
    #expect(journey.current?.id == .workspaces)
}

@Test
func watchPairingStepUsesAppleDistribution() throws {
    let step = try #require(
        SetupJourney.complete.steps.first(where: { $0.id == .watchPairing })
    )

    #expect(step.detail.contains("Apple Watch"))
    #expect(step.detail.contains("TestFlight or the App Store"))
}
