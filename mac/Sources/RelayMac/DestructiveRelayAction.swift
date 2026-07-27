import RelayCore

enum DestructiveRelayAction: Identifiable, Equatable {
    case revokeWatch(AdminDevice)
    case emergencyStop
    case deleteAccount

    var id: String {
        switch self {
        case let .revokeWatch(device): "revoke-\(device.id)"
        case .emergencyStop: "emergency-stop"
        case .deleteAccount: "delete-account"
        }
    }

    var title: String {
        switch self {
        case let .revokeWatch(device): "Revoke \(device.name)?"
        case .emergencyStop: "Stop all Relay access?"
        case .deleteAccount: "Permanently delete Relay Cloud account?"
        }
    }

    var consequence: String {
        switch self {
        case .revokeWatch:
            "This watch loses Relay access immediately and must pair again. Local Codex tasks and repositories remain on this Mac."
        case .emergencyStop:
            "This disconnects every watch and stops the Relay bridge. Local Codex tasks and repositories remain on this Mac."
        case .deleteAccount:
            "This permanently deletes Relay Cloud account metadata and revokes this Mac and every watch. Local Codex tasks and repositories remain on this Mac."
        }
    }

    var confirmationLabel: String {
        switch self {
        case .revokeWatch: "Revoke watch"
        case .emergencyStop: "Stop Relay access"
        case .deleteAccount: "Delete Relay Cloud account"
        }
    }
}
