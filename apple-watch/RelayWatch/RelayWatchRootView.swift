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
                    detail: "The Mac removed this watch. Cached Relay data was erased.",
                    action: "Pair again",
                    callback: model.pairAgain
                )
            case .incompatible:
                problem(
                    title: "Update required",
                    detail: "This watch and the Mac bridge do not share a safe API version.",
                    action: "Try again",
                    callback: model.pairAgain
                )
            case .live, .offline:
                destination
            }
        }
        .tint(.mint)
    }

    private var pairing: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: model.discoveredMac == nil ? "antenna.radiowaves.left.and.right" : "checkmark.shield")
                    .font(.title)
                    .foregroundStyle(.mint)
                    .accessibilityHidden(true)
                Text(model.discoveredMac?.macName ?? "Find Relay Mac")
                    .font(.headline)
                if let mac = model.discoveredMac {
                    Text(mac.macFingerprint)
                        .font(.caption2.monospaced())
                        .multilineTextAlignment(.center)
                    Text("Compare the Mac fingerprint, then enter its code.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("6-character code", text: $model.pairingCode)
                        .textInputAutocapitalization(.characters)
                    Button("Request approval", action: model.pair)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.pairingCode.count != 6)
                    Text("Watch \(model.watchFingerprint)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Start secure pairing on the Mac and keep both devices on the same Wi-Fi.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView()
                }
                if model.connection == .pairing {
                    Text("Waiting for approval on Mac…")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                error
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var destination: some View {
        if model.screen == .inbox {
            home
        } else {
            RelayWatchDestinationView(
                screen: model.screen,
                enabled: model.actionsEnabled,
                stale: model.cacheIsStale,
                onBack: { model.show(.inbox) },
                onRevoke: model.revokeLocally
            )
        }
    }

    private var home: some View {
        List {
            Section {
                if model.connection == .offline {
                    Label("Mac offline · cached data", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                } else {
                    Label("Relay live", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.mint)
                }
            }
            Section("Needs you") {
                Button {
                    model.show(.approval)
                } label: {
                    Label("\(model.cachedInboxCount) approvals or questions", systemImage: "tray.full")
                }
                .disabled(!model.actionsEnabled)
                Button {
                    model.show(.tasks)
                } label: {
                    Label("\(model.cachedTaskCount) Codex tasks", systemImage: "terminal")
                }
            }
            Section("Relay") {
                ForEach(
                    [
                        RelayWatchScreen.question,
                        .activity,
                        .instruction,
                        .voice,
                        .newTask,
                        .history,
                        .settings,
                    ]
                ) { screen in
                    Button {
                        model.show(screen)
                    } label: {
                        Label(screen.title, systemImage: screen.symbol)
                    }
                }
            }
            Button("Refresh") {
                Task { await model.refresh() }
            }
        }
    }

    private func problem(
        title: String,
        detail: String,
        action: String,
        callback: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.slash")
                .font(.title)
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action, action: callback)
        }
    }

    @ViewBuilder
    private var error: some View {
        if let error = model.error {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}

private struct RelayWatchDestinationView: View {
    let screen: RelayWatchScreen
    let enabled: Bool
    let stale: Bool
    let onBack: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        List {
            Section {
                Label(screen.title, systemImage: screen.symbol)
                    .font(.headline)
                if stale {
                    Text("Offline copy · actions disabled")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            content
            Button("Back", action: onBack)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .approval:
            Text("git push origin main").font(.caption.monospaced())
            Text("Consequence: writes commits to the remote repository.")
                .font(.caption2)
            Button("Deny") {}.tint(.red).disabled(!enabled)
            Button("Approve this action") {}.disabled(!enabled)
        case .question:
            Text("Which release channel should Relay use?")
            Button("Stable") {}.disabled(!enabled)
            Button("Beta") {}.disabled(!enabled)
        case .tasks:
            Text("Relay launch readiness")
            Text("Running · ~/Developer/SandBox/codewatch")
                .font(.caption2.monospaced())
        case .activity:
            Text("Tests passed")
            Text("Building signed artifacts")
            Text("Waiting for physical release gates")
        case .instruction:
            TextField("Tell Codex what to do", text: .constant(""))
            Button("Review instruction") {}.disabled(!enabled)
        case .voice:
            Text("Record, transcribe on the Mac, review, then send.")
            Button("Hold to record") {}.disabled(!enabled)
        case .newTask:
            Text("Workspace · Relay")
            Text("Model · Choose from Mac")
            Text("Permissions · Review exact profile")
            Button("Review new task") {}.disabled(!enabled)
        case .history:
            Text("Approved · pnpm test")
            Text("Denied · destructive command")
        case .settings:
            Text("API 1 · Mac 1.0.0+")
            Text("Apple Watch updates use the App Store.")
            Button("Forget this watch", role: .destructive, action: onRevoke)
        case .revoked:
            Text("This watch no longer has Relay access.")
        case .onboarding, .pairing, .inbox:
            EmptyView()
        }
    }
}
