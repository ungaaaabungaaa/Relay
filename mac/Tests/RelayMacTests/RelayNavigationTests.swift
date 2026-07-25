import Testing
@testable import RelayMac

@Test
func dashboardExposesEveryReleaseControlSection() {
    #expect(
        DashboardSection.allCases.map(\.title) == [
            "Setup",
            "Watches",
            "Relay Cloud",
            "Workspaces",
            "Voice",
            "Updates",
            "Diagnostics",
            "About",
        ]
    )
}
