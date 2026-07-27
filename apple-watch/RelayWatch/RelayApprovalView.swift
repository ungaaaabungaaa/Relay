import SwiftUI
import WatchKit

struct RelayApprovalView: View {
    @ObservedObject var model: RelayWatchModel
    @State private var confirmNormal = false
    @State private var confirmDangerous = false

    var body: some View {
        List {
            RelayConnectionBanner(model: model)
            if let approval = model.selectedApproval {
                Section(approval.kind.rawValue.capitalized) {
                    if let command = approval.command {
                        Text(command).font(.caption.monospaced())
                    }
                    if let cwd = approval.cwd {
                        Label(cwd, systemImage: "folder").font(.caption2)
                    }
                    if let reason = approval.reason { Text(reason).font(.caption2) }
                }
                Section(approval.risk == .dangerous ? "Dangerous action" : "Consequence") {
                    ForEach(consequences(for: approval), id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                    }
                }
                Button("Deny", role: .destructive) { deny(approval) }
                    .disabled(!canMutate)
                    .accessibilityHint("Rejects this exact Mac action without running it")
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
            } else {
                Text("This approval is no longer pending.")
            }
            RelayBackButton(model: model)
        }
    }

    private var canMutate: Bool { model.actionsEnabled && !model.mutationPending }

    private func consequences(for approval: RelayApproval) -> [String] {
        if !approval.riskReasons.isEmpty { return approval.riskReasons }
        switch approval.kind {
        case .command: return ["Runs the exact command shown above."]
        case .file: return ["Allows the displayed file operation."]
        case .permission: return ["Grants the displayed permission to Codex."]
        }
    }

    private func deny(_ approval: RelayApproval) {
        Task {
            do {
                try await model.deny(approval.id)
                model.reportActionSuccess()
                model.show(.inbox)
            } catch { model.reportActionFailure(error) }
        }
    }

    private func approve(_ approval: RelayApproval, dangerous: Bool) {
        Task {
            do {
                try await model.approve(approval.id, dangerousConfirmation: dangerous)
                model.reportActionSuccess()
                model.show(.inbox)
            } catch { model.reportActionFailure(error) }
        }
    }
}
