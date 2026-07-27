import AppKit
import SwiftUI
import RelayCore

struct MenuContent: View {
    @ObservedObject var model: RelayAppModel
    @ObservedObject private var updater: RelayUpdateController

    init(model: RelayAppModel) {
        self.model = model
        updater = model.updateController
    }

    var body: some View {
        Group {
            statusRows
            Divider()
            pendingActionsMenu
            watchMenu
            workspacesMenu
            Divider()
            cloudMenu
            voiceMenu
            Toggle("Start Relay at Login", isOn: Binding(
                get: { model.startAtLogin },
                set: { model.setStartAtLogin($0) }
            ))
            Divider()
            diagnosticsMenu
            Button("Check for Updates…") { updater.checkForUpdates() }
            aboutMenu
            Divider()
            Button("Emergency Stop…", role: .destructive) {
                guard RelayMenuDialogs.confirm(.emergencyStop) else { return }
                Task { await model.emergencyStop() }
            }
            Button("Quit Relay") {
                Task {
                    await model.quit()
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        ForEach(
            RelayMenuPresentation.statusRows(
                bridgeState: model.bridgeState,
                codexStatus: model.codexStatus,
                cloudPhase: model.cloudTunnelPhase,
                activeDeviceCount: model.activeDeviceCount
            ),
            id: \.self
        ) { row in
            Text(row).disabled(true)
        }
        if let error = model.lastError {
            Text(error).disabled(true)
        }
    }

    private var pendingActionsMenu: some View {
        Menu("Pending Actions") {
            Text("\(model.pendingActionCount) waiting actions").disabled(true)
            Text("Review on Apple Watch").disabled(true)
        }
    }

    private var watchMenu: some View {
        Menu("Apple Watch") {
            Button("Start Secure Pairing") {
                Task { await model.createSecurePairingSession() }
            }
            .disabled(
                !RelayMenuPresentation.canStartSecurePairing(
                    cloudConnected: model.cloudConnected,
                    bridgeState: model.bridgeState
                )
            )
            Text("Mac fingerprint \(pairingMacFingerprint)").disabled(true)
            if let session = model.cloudPairingSession {
                Text("Code \(session.code)").disabled(true)
                Text(
                    RelayMenuPresentation.pairingExpiryLabel(
                        expiresAt: session.expiresAt
                    )
                ).disabled(true)
                Button("Copy Pairing Code") {
                    RelayMenuDialogs.copyText(session.code)
                }
            }
            Button("Refresh Pending Requests") {
                Task { await model.refreshPendingPairings() }
            }
            if model.pendingPairings.isEmpty {
                Text("No pending requests").disabled(true)
            } else {
                ForEach(model.pendingPairings) { pairing in
                    Menu(pairing.name) {
                        Text("Fingerprint \(pairing.fingerprint)").disabled(true)
                        Text(
                            RelayMenuPresentation.pairingExpiryLabel(
                                expiresAt: pairing.expiresAt
                            )
                        ).disabled(true)
                        Button("Approve") {
                            Task { await model.approvePairing(pairing) }
                        }
                        .disabled(
                            !RelayMenuPresentation.canResolvePairing(
                                cloudPhase: model.cloudTunnelPhase,
                                bridgeState: model.bridgeState
                            )
                        )
                        Button("Deny", role: .destructive) {
                            guard RelayMenuDialogs.confirm(
                                title: "Deny \(pairing.name)?",
                                message: "This pending watch request will not receive Relay access.",
                                confirmationLabel: "Deny request"
                            ) else { return }
                            Task { await model.denyPairing(pairing) }
                        }
                        .disabled(
                            !RelayMenuPresentation.canResolvePairing(
                                cloudPhase: model.cloudTunnelPhase,
                                bridgeState: model.bridgeState
                            )
                        )
                    }
                }
            }
            if model.devices.isEmpty {
                Text("No paired watches").disabled(true)
            } else {
                Divider()
                ForEach(model.devices.filter { $0.revokedAt == nil }) { device in
                    Menu(device.name) {
                        Text("Fingerprint \(device.fingerprint)").disabled(true)
                        Button("Revoke…", role: .destructive) {
                            guard RelayMenuDialogs.confirm(.revokeWatch(device)) else { return }
                            Task { await model.revoke(device) }
                        }
                    }
                }
            }
        }
    }

    private var workspacesMenu: some View {
        Menu("Workspaces") {
            if model.workspaces.isEmpty {
                Text("No allowed folders").disabled(true)
            } else {
                ForEach(model.workspaces, id: \.self) { root in
                    Menu(RelayMenuPresentation.workspaceDisplayName(root)) {
                        Button("Reveal in Finder") {
                            RelayMenuDialogs.revealInFinder(root)
                        }
                        Button("Copy Path") {
                            RelayMenuDialogs.copyText(root)
                        }
                        Button("Remove…", role: .destructive) {
                            guard RelayMenuDialogs.confirm(
                                title: "Remove \(RelayMenuPresentation.workspaceDisplayName(root))?",
                                message: "Relay will no longer offer this folder for new work.",
                                confirmationLabel: "Remove folder"
                            ) else { return }
                            Task {
                                await model.replaceWorkspaces(
                                    model.workspaces.filter { $0 != root }
                                )
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Add Folder…") {
                guard let root = RelayMenuDialogs.chooseWorkspace() else { return }
                Task {
                    await model.replaceWorkspaces(
                        Array(Set(model.workspaces + [root])).sorted()
                    )
                }
            }
        }
    }

    private var pairingMacFingerprint: String {
        RelayMenuPresentation.pairingMacFingerprint(
            sessionFingerprint: model.cloudPairingSession?.macFingerprint,
            hostFingerprint: model.hostFingerprint
        )
    }

    private var cloudMenu: some View {
        Menu("Relay Cloud") {
            Text(RelayMenuPresentation.cloudLabel(model.cloudTunnelPhase)).disabled(true)
            Text("Environment \(model.cloudEnvironmentName)").disabled(true)
            if model.cloudSignedIn {
                Button("Reconnect") {
                    Task { await model.reconnectRelay() }
                }
                Button("Sign Out") {
                    Task { await model.signOutOfRelayCloud() }
                }
                Button("Delete Relay Cloud Account…", role: .destructive) {
                    guard RelayMenuDialogs.confirm(.deleteAccount) else { return }
                    Task { await model.deleteRelayAccount() }
                }
            } else {
                Button("Sign In…") {
                    guard let email = RelayMenuDialogs.requestEmail() else { return }
                    model.signInToRelayCloud(email: email)
                }
            }
            if model.cloudLoginInProgress {
                Button("Cancel Sign-In") { model.cancelRelayCloudLogin() }
            }
        }
    }

    private var voiceMenu: some View {
        Menu("Voice and Transcription") {
            Text(
                model.voiceConfigured
                    ? "OpenAI key configured in Keychain"
                    : "OpenAI key not configured"
            ).disabled(true)
            if model.voiceConfigured {
                Button("Remove OpenAI API Key", role: .destructive) {
                    guard RelayMenuDialogs.confirm(
                        title: "Remove OpenAI API key?",
                        message: "Voice transcription will be unavailable until you set a new key.",
                        confirmationLabel: "Remove key"
                    ) else { return }
                    Task { await model.saveOpenAIKey("") }
                }
            } else {
                Button("Set OpenAI API Key…") {
                    guard let key = RelayMenuDialogs.requestOpenAIKey() else { return }
                    Task { await model.saveOpenAIKey(key) }
                }
            }
        }
    }

    private var diagnosticsMenu: some View {
        Menu("Diagnostics") {
            Text("Only redacted operational status is copied.").disabled(true)
            Button("Refresh") { Task { await model.refresh() } }
            Button("Copy Safe Diagnostics") {
                RelayMenuDialogs.copyText(
                    RelayMenuPresentation.safeDiagnostic(
                        bridgeState: model.bridgeState,
                        cloudPhase: model.cloudTunnelPhase,
                        diagnostic: model.diagnostic
                    )
                )
            }
        }
    }

    private var aboutMenu: some View {
        Menu("About") {
            Text("Relay for Apple Watch").disabled(true)
            Text("Relay Mac 1.0.0").disabled(true)
            Text("Watch client requires Relay Mac 1.0.0+").disabled(true)
            Button("Open Relay Website") {
                RelayMenuDialogs.openURL(URL(string: "https://relayforcodex.com")!)
            }
        }
    }
}
