import RelayCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Start here",
                    title: "Set up Relay",
                    detail: "\(model.setupJourney.completedCount) of 9 steps complete. Relay resumes at the first unfinished step."
                )
                ForEach(Array(model.setupJourney.steps.enumerated()), id: \.element.id) { index, step in
                    RelayPanel {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(step.complete ? RelayPalette.accent : Color.secondary.opacity(0.2))
                                    .frame(width: 30, height: 30)
                                if step.complete {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.black)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text(step.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                if model.setupJourney.current?.id == step.id {
                                    stepAction(for: step.id)
                                        .padding(.top, 6)
                                }
                            }
                            Spacer()
                            StatusPill(
                                text: step.complete ? "Done" : "Waiting",
                                ready: step.complete
                            )
                        }
                    }
                }
                RelayPanel {
                    Toggle(
                        "Start Relay at login",
                        isOn: Binding(
                            get: { model.startAtLogin },
                            set: { enabled in
                                model.setStartAtLogin(enabled)
                            }
                        )
                    )
                    Text("Off by default. macOS keeps this setting under Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(RelayPalette.amber)
                }
            }
        }
    }

    @ViewBuilder
    private func stepAction(for step: SetupJourneyStepID) -> some View {
        switch step {
        case .integrityAndCodex, .bridgePreflight:
            Button("Run checks") {
                Task { await model.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(RelayPalette.accent)
        case .tailscaleInstall:
            Link(
                "Download official Tailscale",
                destination: URL(string: "https://tailscale.com/download/mac")!
            )
        case .tailscaleLogin:
            HStack {
                Button(model.tailscaleLoginInProgress ? "Waiting for browser…" : "Sign in securely") {
                    model.signInToTailscale()
                }
                .disabled(model.tailscaleLoginInProgress)
                if model.tailscaleLoginInProgress {
                    Button("Cancel", role: .cancel) {
                        model.cancelTailscaleLogin()
                    }
                }
            }
        case .platformTools:
            Button("Install verified tools") {
                Task { await model.installPlatformTools() }
            }
        case .watchInstall:
            Text("Open Watches to discover and install the APK.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .watchPairing:
            Text("Open Watches, start pairing, then compare both fingerprints.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .workspaces:
            Text("Open Workspaces and add at least one allowed folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .remoteAccess:
            Button("Enable secure remote access") {
                Task { await model.enableRemoteAccess() }
            }
            .disabled(!model.tailscaleSignedIn || model.bridgeState != .running)
        }
    }
}
