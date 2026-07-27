import SwiftUI

struct RelayPairingFlowView: View {
    @ObservedObject var model: RelayWatchModel

    var body: some View {
        switch model.pairingPhase {
        case .codeEntry, .failed:
            codeEntry
        case .submitting:
            ProgressView("Checking code…")
        case let .confirmMac(name, fingerprint, _):
            fingerprintReview(name: name, fingerprint: fingerprint)
        case .awaitingMacApproval:
            awaitingApproval
        case .paired:
            ProgressView("Opening encrypted session…")
        }
    }

    private var codeEntry: some View {
        RelayAdaptiveContainer {
            codeEntryContent
        } scrolling: {
            codeEntryContent.padding(.horizontal, 4)
        }
    }

    private var codeEntryContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                RelayWatchMark()
                    .frame(width: 30, height: 22)
                    .accessibilityHidden(true)
                Text("Pair with Mac").font(.headline)
            }
            Text("Enter the six-character code from Relay on your Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("6-character code", text: $model.pairingCode)
                .textInputAutocapitalization(.characters)
            Button("Find Mac", action: model.pair)
                .buttonStyle(.borderedProminent)
                .disabled(model.pairingCode.count != 6)
            Text("Watch \(model.watchFingerprint.prefix(8))…")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Watch \(model.watchFingerprint)")
            error
        }
    }

    private func fingerprintReview(name: String, fingerprint: String) -> some View {
        RelayAdaptiveContainer {
            fingerprintContent(name: name, fingerprint: fingerprint)
        } scrolling: {
            fingerprintContent(name: name, fingerprint: fingerprint)
                .padding(.horizontal, 4)
        }
    }

    private func fingerprintContent(name: String, fingerprint: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.title)
                .foregroundStyle(RelayWatchStyle.accent)
            Text(name).font(.headline)
            Text("Mac \(fingerprint)").font(.caption2.monospaced())
            Text("Watch \(model.watchFingerprint)").font(.caption2.monospaced())
            Text("Compare both fingerprints with the Mac before continuing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Fingerprints match") { model.confirmMac() }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Confirms the displayed Mac before Relay begins approval polling")
            Button("Cancel", role: .cancel, action: model.cancelPairing)
        }
    }

    private var awaitingApproval: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Approve this watch on the Mac").font(.headline)
            Text("No actions are available until the Mac accepts the confirmed fingerprints.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel, action: model.cancelPairing)
        }
    }

    @ViewBuilder
    private var error: some View {
        if let error = model.error {
            Text(error).font(.caption2).foregroundStyle(.orange)
        }
    }
}

struct RelayPairingProblemView: View {
    let title: String
    let detail: String
    let action: String
    let callback: () -> Void

    var body: some View {
        RelayAdaptiveContainer {
            content
        } scrolling: {
            content.padding(.horizontal, 4)
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.slash").font(.title).foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action, action: callback)
        }
    }
}
