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

    func canAdvance(from step: RelayNewTaskStep, models: [RelayModel]) -> Bool {
        switch step {
        case .workspace:
            return !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

struct RelayTaskSummary: Equatable, Sendable {
    let statusTitle: String
    let workspaceName: String
    let latestActivityTitle: String
    let canStop: Bool
}

enum RelayTaskPresentation {
    static func summary(_ detail: RelayTaskDetail) -> RelayTaskSummary {
        let latestActivity = detail.activity.enumerated().max { lhs, rhs in
            let lhsDate = lhs.element.occurredAt ?? detail.updatedAt
            let rhsDate = rhs.element.occurredAt ?? detail.updatedAt
            return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
        }?.element
        return RelayTaskSummary(
            statusTitle: detail.status.rawValue.capitalized,
            workspaceName: URL(fileURLWithPath: detail.cwd).lastPathComponent,
            latestActivityTitle: latestActivity?.title ?? detail.preview,
            canStop: detail.activeTurnId != nil
        )
    }
}
