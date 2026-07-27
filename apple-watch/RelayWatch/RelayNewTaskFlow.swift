import Foundation

enum RelayNewTaskStep: Int, CaseIterable, Equatable, Sendable {
    case workspace
    case model
    case prompt
}

struct RelayNewTaskDraft: Equatable, Sendable {
    var cwd = ""
    var modelID = ""
    var effort = ""
    var prompt = ""

    func canAdvance(
        from step: RelayNewTaskStep,
        folders: [RelayFolder],
        models: [RelayModel]
    ) -> Bool {
        switch step {
        case .workspace:
            return folders.contains { $0.path == cwd }
        case .model:
            guard let model = models.first(where: { $0.id == modelID }) else { return false }
            return model.efforts.contains(effort)
        case .prompt:
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func next(after step: RelayNewTaskStep) -> RelayNewTaskStep {
        switch step {
        case .workspace: .model
        case .model, .prompt: .prompt
        }
    }

    mutating func applyDefaults(folders: [RelayFolder], models: [RelayModel]) {
        if cwd.isEmpty { cwd = folders.first?.path ?? "" }
        if modelID.isEmpty {
            modelID = models.first(where: \.isDefault)?.id ?? models.first?.id ?? ""
        }
        if effort.isEmpty {
            effort = models.first(where: { $0.id == modelID })?.defaultEffort ?? ""
        }
    }
}

enum RelayNewTaskPresentation {
    static let finalActionTitle = "Start reviewed task"
}

struct RelayTaskSummary: Equatable, Sendable {
    let statusTitle: String
    let workspaceName: String
    let workspacePath: String
    let latestActivityTitle: String
    let latestActivityStatus: String
    let canStop: Bool
    let canViewActivity: Bool

    var workspaceAccessibilityLabel: String { "Workspace \(workspacePath)" }
}

struct RelayTaskRowPresentation: Equatable, Sendable {
    let systemImage: String
    let statusAndTime: String
}

enum RelayTaskPresentation {
    static func instructionTask(
        routeTaskID: String?,
        selectedTaskID: String?,
        tasks: [RelayTask]
    ) -> RelayTask? {
        if let routeTaskID {
            return tasks.first(where: { $0.id == routeTaskID })
        }
        if let selectedTaskID, let task = tasks.first(where: { $0.id == selectedTaskID }) {
            return task
        }
        return tasks.first(where: { $0.status == .running })
    }

    static func row(
        _ task: RelayTask,
        nowSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> RelayTaskRowPresentation {
        let time = timeContext(updatedAt: task.updatedAt, nowSeconds: nowSeconds)
        return RelayTaskRowPresentation(
            systemImage: symbol(for: task.status),
            statusAndTime: "\(task.status.rawValue.capitalized) · \(time)"
        )
    }

    static func summary(_ detail: RelayTaskDetail) -> RelayTaskSummary {
        let latestActivity = detail.activity.enumerated().max { lhs, rhs in
            let lhsDate = lhs.element.occurredAt ?? detail.updatedAt
            let rhsDate = rhs.element.occurredAt ?? detail.updatedAt
            return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
        }?.element
        return RelayTaskSummary(
            statusTitle: detail.status.rawValue.capitalized,
            workspaceName: URL(fileURLWithPath: detail.cwd).lastPathComponent,
            workspacePath: detail.cwd,
            latestActivityTitle: latestActivity?.title ?? detail.preview,
            latestActivityStatus: (latestActivity?.status.rawValue ?? detail.status.rawValue).capitalized,
            canStop: detail.activeTurnId != nil,
            canViewActivity: true
        )
    }

    static func summary(_ task: RelayTask) -> RelayTaskSummary {
        RelayTaskSummary(
            statusTitle: task.status.rawValue.capitalized,
            workspaceName: URL(fileURLWithPath: task.cwd).lastPathComponent,
            workspacePath: task.cwd,
            latestActivityTitle: task.preview,
            latestActivityStatus: task.status.rawValue.capitalized,
            canStop: false,
            canViewActivity: false
        )
    }

    private static func symbol(for status: RelayTask.Status) -> String {
        switch status {
        case .idle: "pause.circle"
        case .running: "play.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .offline: "wifi.slash"
        }
    }

    private static func timeContext(updatedAt: Int64, nowSeconds: Int64) -> String {
        let elapsed = max(0, nowSeconds - updatedAt)
        if elapsed < 60 { return "now" }
        if elapsed < 3_600 { return "\(elapsed / 60)m ago" }
        if elapsed < 86_400 { return "\(elapsed / 3_600)h ago" }
        return "\(elapsed / 86_400)d ago"
    }
}
