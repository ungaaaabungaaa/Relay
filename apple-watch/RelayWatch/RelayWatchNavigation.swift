import Foundation

enum RelayWatchRoute: Hashable {
    case approval(String)
    case question(String)
    case tasks
    case task(String)
    case activity(String)
    case instruction(String?)
    case newTask
    case voice
    case more
    case history
    case settings
    case identity
    case about
}

struct RelayHomeItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let route: RelayWatchRoute
}

struct RelayHomeAction: Identifiable, Hashable {
    let title: String
    let systemImage: String
    let route: RelayWatchRoute

    var id: String { title }
}

struct RelayMoreAction: Identifiable, Hashable {
    enum Kind: Hashable {
        case voice, refresh, history, settings
    }

    let title: String
    let systemImage: String
    let kind: Kind

    var id: String { title }
}

enum RelayHomePresentation {
    static let clearActions = [
        RelayHomeAction(title: "Tasks", systemImage: "terminal", route: .tasks),
        RelayHomeAction(title: "New task", systemImage: "plus.circle", route: .newTask),
        RelayHomeAction(title: "Voice", systemImage: "mic", route: .voice),
        RelayHomeAction(title: "More", systemImage: "ellipsis.circle", route: .more),
    ]

    static func items(
        approvals: [RelayApproval],
        questions: [RelayQuestion],
        limit: Int
    ) -> [RelayHomeItem] {
        let approvalItems = approvals.map { approval in
            RelayHomeItem(
                id: approval.id,
                title: approval.command ?? approval.reason ?? "Codex approval",
                systemImage: approval.risk == .dangerous
                    ? "exclamationmark.triangle.fill" : "checkmark.shield",
                route: .approval(approval.id)
            )
        }
        let questionItems = questions.map { question in
            RelayHomeItem(
                id: question.id,
                title: question.questions.first?.question ?? "Codex question",
                systemImage: "questionmark.bubble",
                route: .question(question.id)
            )
        }
        return Array((approvalItems + questionItems).prefix(max(0, limit)))
    }

    static func remainingCount(total: Int, visible: Int) -> Int {
        max(0, total - visible)
    }
}

enum RelayMorePresentation {
    static let actions = [
        RelayMoreAction(title: "Voice", systemImage: "mic", kind: .voice),
        RelayMoreAction(title: "Refresh", systemImage: "arrow.clockwise", kind: .refresh),
        RelayMoreAction(title: "History", systemImage: "clock.arrow.circlepath", kind: .history),
        RelayMoreAction(title: "Settings", systemImage: "gearshape", kind: .settings),
    ]
}
