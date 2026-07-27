import SwiftUI
import WatchKit

struct RelayApprovalView: View {
    @ObservedObject var model: RelayWatchModel
    let approvalID: String?
    @State private var confirmNormal = false
    @State private var confirmDangerous = false

    var body: some View {
        RelayAdaptiveContainer {
            VStack(alignment: .leading, spacing: 10) {
                RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
                if let approval {
                    approvalContent(approval)
                    compactActions(for: approval)
                } else {
                    Text("This approval is no longer pending.")
                }
                RelayBackButton(model: model)
            }
        } scrolling: {
            VStack(alignment: .leading, spacing: 12) {
                RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
                if let approval {
                    approvalContent(approval)
                    scrollingActions(for: approval)
                } else {
                    Text("This approval is no longer pending.")
                }
                RelayBackButton(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func approvalContent(_ approval: RelayApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "\(approval.kind.rawValue.capitalized) review",
                systemImage: approval.kind == .command ? "terminal" : "checklist"
            )
            .font(.headline)

            Label(
                "Risk: \(approval.risk.rawValue.capitalized)",
                systemImage: approval.risk == .dangerous
                    ? "exclamationmark.triangle.fill"
                    : "checkmark.shield"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(approval.risk == .dangerous ? .orange : .secondary)

            if let command = approval.command {
                Text("Command")
                    .font(.caption.weight(.semibold))
                Text(command)
                    .font(.caption.monospaced())
            }

            if let reason = approval.reason {
                Text("Reason")
                    .font(.caption.weight(.semibold))
                Text(reason)
                    .font(.body)
            }

            if let cwd = approval.cwd {
                Text("Working directory")
                    .font(.caption.weight(.semibold))
                Label(cwd, systemImage: "folder")
                    .font(.caption2)
            }

            Text(approval.risk == .dangerous ? "Dangerous consequences" : "Consequences")
                .font(.caption.weight(.semibold))
            ForEach(consequences(for: approval), id: \.self) { consequence in
                Label(
                    consequence,
                    systemImage: approval.risk == .dangerous
                        ? "exclamationmark.triangle.fill"
                        : "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(approval.risk == .dangerous ? .orange : .primary)
            }
        }
    }

    @ViewBuilder
    private func compactActions(for approval: RelayApproval) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                denyButton(for: approval)
                approveButton(for: approval)
            }
            VStack(spacing: 8) {
                denyButton(for: approval)
                    .frame(maxWidth: .infinity)
                approveButton(for: approval)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func scrollingActions(for approval: RelayApproval) -> some View {
        VStack(spacing: 8) {
            denyButton(for: approval)
                .frame(maxWidth: .infinity)
            approveButton(for: approval)
                .frame(maxWidth: .infinity)
        }
    }

    private func denyButton(for approval: RelayApproval) -> some View {
        Button("Deny", role: .destructive) { deny(approval) }
            .disabled(!canMutate)
            .accessibilityHint("Rejects this exact Mac action without running it")
    }

    private func approveButton(for approval: RelayApproval) -> some View {
        Button("Approve this action") {
            if approval.risk == .dangerous {
                WKInterfaceDevice.current().play(.notification)
                confirmDangerous = true
            } else {
                confirmNormal = true
            }
        }
        .disabled(!canMutate)
        .accessibilityHint("Allows the displayed action and its listed consequences")
        .confirmationDialog(
            "Approve the displayed action?",
            isPresented: $confirmNormal,
            titleVisibility: .visible
        ) {
            Button("Approve") { approve(approval, dangerous: false) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "This dangerous action can change external state. Approve it?",
            isPresented: $confirmDangerous,
            titleVisibility: .visible
        ) {
            Button("Approve dangerous action", role: .destructive) {
                approve(approval, dangerous: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var canMutate: Bool { model.actionsEnabled && !model.mutationPending }

    private var approval: RelayApproval? {
        guard let approvalID else { return model.selectedApproval }
        return model.inbox.approvals.first { $0.id == approvalID }
    }

    private func consequences(for approval: RelayApproval) -> [String] {
        if !approval.riskReasons.isEmpty { return approval.riskReasons }
        switch approval.kind {
        case .command: return ["Runs the exact command shown above."]
        case .file: return ["Allows the displayed file operation."]
        case .permission: return ["Grants the displayed permission to Codex."]
        }
    }

    private func deny(_ approval: RelayApproval) {
        guard canMutate else { return }
        Task {
            do {
                try await model.deny(approval.id)
                model.reportActionSuccess()
                model.show(.inbox)
            } catch { model.reportActionFailure(error) }
        }
    }

    private func approve(_ approval: RelayApproval, dangerous: Bool) {
        guard canMutate else { return }
        Task {
            do {
                try await model.approve(approval.id, dangerousConfirmation: dangerous)
                model.reportActionSuccess()
                model.show(.inbox)
            } catch { model.reportActionFailure(error) }
        }
    }
}
