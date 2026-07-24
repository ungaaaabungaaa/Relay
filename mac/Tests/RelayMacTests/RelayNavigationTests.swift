import Testing
@testable import RelayMac

@Test
func dashboardExposesEveryReleaseControlSection() {
    #expect(
        DashboardSection.allCases.map(\.title) == [
            "Setup",
            "Watches",
            "Remote Access",
            "Workspaces",
            "Voice",
            "Updates",
            "Diagnostics",
            "About",
        ]
    )
}
