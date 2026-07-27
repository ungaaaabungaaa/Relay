import Foundation
import Testing
import RelayCore
@testable import RelayMac

@Test
func destructiveRelayActionsNameTheScopeAndPreserveLocalCodexWork() throws {
    let watch = try JSONDecoder().decode(
        AdminDevice.self,
        from: Data(#"{"id":"watch-1","name":"Office Watch","fingerprint":"AA:BB","createdAt":1,"revokedAt":null}"#.utf8)
    )
    let actions: [DestructiveRelayAction] = [
        .revokeWatch(watch), .emergencyStop, .deleteAccount,
    ]
    for action in actions {
        #expect(action.title.contains("?") || action.title.contains("Permanently"))
        #expect(action.consequence.contains("Local Codex tasks and repositories remain"))
    }
    #expect(actions[0].consequence.contains("watch loses Relay access"))
    #expect(actions[2].consequence.contains("permanently deletes Relay Cloud"))
}

@Test
func destructiveButtonsStageAConfirmationBeforeCallingTheModel() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let macRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let menu = try String(
        contentsOf: macRoot.appendingPathComponent("Sources/RelayMac/RelayStatusItemController.swift"),
        encoding: .utf8
    )
    let dialogs = try String(
        contentsOf: macRoot.appendingPathComponent("Sources/RelayMac/RelayMenuDialogs.swift"),
        encoding: .utf8
    )
    #expect(menu.contains("RelayMenuDialogs.confirm"))
    #expect(
        menu.range(of: "RelayMenuDialogs.confirm(.emergencyStop)")!.lowerBound
            < menu.range(of: "model.emergencyStop()")!.lowerBound
    )
    #expect(
        menu.range(of: "RelayMenuDialogs.confirm(.revokeWatch(device))")!.lowerBound
            < menu.range(of: "model.revoke(device)")!.lowerBound
    )
    #expect(
        menu.range(of: "RelayMenuDialogs.confirm(.deleteAccount)")!.lowerBound
            < menu.range(of: "model.deleteRelayAccount()")!.lowerBound
    )
    #expect(dialogs.contains("action.consequence"))
    #expect(dialogs.contains("alert.runModal()"))
}
