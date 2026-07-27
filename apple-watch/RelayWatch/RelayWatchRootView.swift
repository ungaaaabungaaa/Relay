import SwiftUI

struct RelayWatchRootView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        Group {
            switch model.connection {
            case .unpaired, .pairing:
                RelayPairingFlowView(model: model)
            case .revoked:
                RelayPairingProblemView(
                    title: "Access revoked",
                    detail: "The Mac removed this watch. Cached Relay data and credentials were erased.",
                    action: "Pair again",
                    callback: model.pairAgain
                )
            case .incompatible:
                RelayPairingProblemView(
                    title: "Update required",
                    detail: "This watch and the Mac bridge do not share a safe API version.",
                    action: "Pair again",
                    callback: model.pairAgain
                )
            case .live, .offline:
                NavigationStack(path: $model.path) {
                    RelayWatchHomeView(model: model)
                        .navigationDestination(for: RelayWatchRoute.self) { route in
                            destination(for: route)
                        }
                }
            }
        }
        .tint(RelayWatchStyle.accent)
    }

    @ViewBuilder
    private func destination(for route: RelayWatchRoute) -> some View {
        switch route {
        case let .approval(id): RelayApprovalView(model: model, approvalID: id)
        case let .question(id): RelayQuestionView(model: model, questionID: id)
        case .tasks: RelayTasksView(model: model)
        case let .task(id), let .activity(id): RelayTaskActivityView(model: model, taskID: id)
        case let .instruction(id): RelayInstructionView(model: model, taskID: id)
        case .newTask: RelayNewTaskView(model: model)
        case .history: RelayHistoryView(model: model)
        case .settings: RelaySettingsView(model: model)
        case .voice:
            RelayVoiceView(model: model, controller: model.voiceController)
        case .more, .identity, .about:
            RelayFutureRouteView(route: route)
        }
    }

}

private struct RelayFutureRouteView: View {
    let route: RelayWatchRoute

    var body: some View {
        ContentUnavailableView(route.title, systemImage: route.symbol)
    }
}

private extension RelayWatchRoute {
    var title: String {
        switch self {
        case .more: "More"
        case .identity: "Identity"
        case .about: "About Relay"
        default: "Relay"
        }
    }

    var symbol: String {
        switch self {
        case .more: "ellipsis.circle"
        case .identity: "person.text.rectangle"
        case .about: "info.circle"
        default: "relay"
        }
    }
}
