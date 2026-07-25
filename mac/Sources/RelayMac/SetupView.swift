import RelayCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: RelayAppModel
    @State private var email = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Start here",
                    title: "Set up Relay",
                    detail: "\(model.setupJourney.completedCount) of 6 steps complete. Relay resumes at the first unfinished step."
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
        case .integrityAndCodex:
            Button("Run checks") {
                Task { await model.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(RelayPalette.accent)
        case .emailSignIn:
            VStack(alignment: .leading, spacing: 8) {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                HStack {
                    Button(model.cloudLoginInProgress ? "Check your browser…" : "Email me a sign-in link") {
                        model.signInToRelayCloud(email: email)
                    }
                    .disabled(model.cloudLoginInProgress || !email.contains("@"))
                    if model.cloudLoginInProgress {
                        Button("Cancel", role: .cancel) {
                            model.cancelRelayCloudLogin()
                        }
                    }
                }
            }
        case .relayCloud:
            Text(model.cloudConnected ? "Encrypted tunnel connected." : "Relay connects automatically after sign-in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .watchPairing:
            Text("Install Relay from Google Play, open Watches, and enter the six-character code.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .workspaces:
            Text("Open Workspaces and add at least one allowed folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .startAtLogin:
            Toggle(
                "Start Relay at login",
                isOn: Binding(
                    get: { model.startAtLogin },
                    set: { enabled in model.setStartAtLogin(enabled) }
                )
            )
        }
    }
}
