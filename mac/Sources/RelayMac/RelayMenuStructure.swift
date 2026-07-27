enum RelayMenuItem: String, CaseIterable {
    case status
    case pendingActions
    case appleWatch
    case workspaces
    case relayCloud
    case voiceAndTranscription
    case startAtLogin
    case diagnostics
    case updates
    case about
    case emergencyStop
    case quit

    var title: String {
        switch self {
        case .status: "Status"
        case .pendingActions: "Pending Actions"
        case .appleWatch: "Apple Watch"
        case .workspaces: "Workspaces"
        case .relayCloud: "Relay Cloud"
        case .voiceAndTranscription: "Voice and Transcription"
        case .startAtLogin: "Start at Login"
        case .diagnostics: "Diagnostics"
        case .updates: "Updates"
        case .about: "About"
        case .emergencyStop: "Emergency Stop"
        case .quit: "Quit"
        }
    }
}

enum RelayMenuGroup: String, CaseIterable {
    case status
    case actions
    case connection
    case maintenance
    case lifecycle

    var items: [RelayMenuItem] {
        switch self {
        case .status: [.status]
        case .actions: [.pendingActions, .appleWatch, .workspaces]
        case .connection: [.relayCloud, .voiceAndTranscription]
        case .maintenance: [.startAtLogin, .diagnostics, .updates, .about]
        case .lifecycle: [.emergencyStop, .quit]
        }
    }
}

enum RelayMenuStructure {
    static let root: [RelayMenuGroup] = [
        .status,
        .actions,
        .connection,
        .maintenance,
        .lifecycle,
    ]
}
