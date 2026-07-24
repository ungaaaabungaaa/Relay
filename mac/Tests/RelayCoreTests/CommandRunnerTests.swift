import Foundation
import Testing
@testable import RelayCore

@Test
func processCommandRunnerUsesExecutableAndArgumentArrays() async throws {
    let runner = ProcessCommandRunner()
    let result = try await runner.run(
        CommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["Relay %s", "ready"]
        )
    )

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == "Relay ready")
    #expect(result.standardError.isEmpty)
}
