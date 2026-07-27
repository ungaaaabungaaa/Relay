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

enum RelayCompactLayout {
    static let materialTileMinimumHeight: CGFloat = 44
    static let materialGridSpacing: CGFloat = 4

    static func gridMinimumHeight(rows: Int) -> CGFloat {
        let count = max(0, rows)
        return CGFloat(count) * materialTileMinimumHeight
            + CGFloat(max(0, count - 1)) * materialGridSpacing
    }
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

struct RelayStatusPresentation: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case normal, attention, destructive
    }

    let title: String
    let systemImage: String
    let detail: String?
    let tone: Tone

    var isAttention: Bool { tone != .normal }

    static func make(
        connection: RelayConnectionState,
        cacheIsStale: Bool,
        error: String?
    ) -> Self {
        let status: (String, String, Tone)
        if connection == .offline || cacheIsStale {
            status = ("Mac offline · cached data", "wifi.slash", .attention)
        } else {
            status = switch connection {
            case .live: ("Relay live", "checkmark.circle.fill", .normal)
            case .unpaired: ("Pair with Mac", "link", .normal)
            case .pairing: ("Pairing with Mac", "link", .normal)
            case .revoked: ("Access revoked", "lock.slash", .destructive)
            case .incompatible: ("Update required", "arrow.triangle.2.circlepath", .attention)
            case .offline: ("Mac offline · cached data", "wifi.slash", .attention)
            }
        }
        let detail = error.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        }
        return Self(
            title: status.0,
            systemImage: status.1,
            detail: detail,
            tone: detail == nil ? status.2 : maxTone(status.2, .attention)
        )
    }

    private static func maxTone(_ lhs: Tone, _ rhs: Tone) -> Tone {
        if lhs == .destructive || rhs == .destructive { return .destructive }
        if lhs == .attention || rhs == .attention { return .attention }
        return .normal
    }
}
