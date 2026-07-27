import SwiftUI

struct RelayWatchRootView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        Group {
            switch model.connection {
            case .unpaired, .pairing:
                pairing
            case .revoked:
                problem(
                    title: "Access revoked",
                    detail: "The Mac removed this watch. Cached Relay data and credentials were erased.",
                    action: "Pair again",
                    callback: model.pairAgain
                )
            case .incompatible:
                problem(
                    title: "Update required",
                    detail: "This watch and the Mac bridge do not share a safe API version.",
                    action: "Pair again",
                    callback: model.pairAgain
                )
            case .live, .offline:
                destination
            }
        }
        .tint(RelayWatchStyle.accent)
    }

    @ViewBuilder
    private var pairing: some View {
        switch model.pairingPhase {
        case .codeEntry, .failed:
            pairingCodeEntry
        case .submitting:
            ProgressView("Checking code…")
        case let .confirmMac(name, fingerprint, _):
            ScrollView {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.title)
                        .foregroundStyle(RelayWatchStyle.accent)
                    Text(name).font(.headline)
                    Text("Mac \(fingerprint)").font(.caption2.monospaced())
                    Text("Watch \(model.watchFingerprint)").font(.caption2.monospaced())
                    Text("Compare both fingerprints with the Mac before continuing.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Fingerprints match") { model.confirmMac() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Confirms the displayed Mac before Relay begins approval polling")
                    Button("Cancel", role: .cancel, action: model.cancelPairing)
                }
            }
        case .awaitingMacApproval:
            VStack(spacing: 10) {
                ProgressView()
                Text("Approve this watch on the Mac").font(.headline)
                Text("No actions are available until the Mac accepts the confirmed fingerprints.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Cancel", role: .cancel, action: model.cancelPairing)
            }
        case .paired:
            ProgressView("Opening encrypted session…")
        }
    }

    private var pairingCodeEntry: some View {
        ScrollView {
            VStack(spacing: 10) {
                RelayWatchMark()
                    .frame(width: 44, height: 32)
                    .accessibilityHidden(true)
                Text("Pair with Mac").font(.headline)
                Text("Enter the six-character code from Relay on your Mac.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TextField("6-character code", text: $model.pairingCode)
                    .textInputAutocapitalization(.characters)
                Button("Find Mac", action: model.pair)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.pairingCode.count != 6)
                Text("Watch \(model.watchFingerprint)")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                error
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch model.screen {
        case .inbox: RelayInboxView(model: model)
        case .approval: RelayApprovalView(model: model)
        case .question: RelayQuestionView(model: model)
        case .tasks: RelayTasksView(model: model)
        case .activity: RelayTaskActivityView(model: model)
        case .instruction: RelayInstructionView(model: model)
        case .newTask: RelayNewTaskView(model: model)
        case .history: RelayHistoryView(model: model)
        case .settings: RelaySettingsView(model: model)
        case .voice:
            RelayVoiceView(model: model, controller: model.voiceController)
        case .onboarding, .pairing, .revoked:
            RelayInboxView(model: model)
        }
    }

    private func problem(
        title: String,
        detail: String,
        action: String,
        callback: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.slash").font(.title).foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action, action: callback)
        }
    }

    @ViewBuilder
    private var error: some View {
        if let error = model.error {
            Text(error).font(.caption2).foregroundStyle(.orange)
        }
    }
}
