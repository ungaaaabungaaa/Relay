import SwiftUI

struct WatchesView: View {
    @ObservedObject var model: RelayAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Devices",
                    title: "Your watches",
                    detail: "Pairing grants one watch its own signing identity. Revoking a watch blocks it immediately."
                )
                RelayPanel {
                    HStack(spacing: 12) {
                        Image(systemName: "storefront")
                            .foregroundStyle(RelayPalette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Install Relay on Apple Watch")
                                .font(.headline)
                            Text("Use TestFlight during development and the App Store after release. Relay needs no VPN or port forwarding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let pairing = model.cloudPairingSession {
                    RelayPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Enter on the watch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(pairing.code)
                                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                                        .tracking(4)
                                }
                                Spacer()
                                StatusPill(text: "Valid 5 minutes", ready: true)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Compare this Mac fingerprint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    Text(pairing.macFingerprint)
                                    .font(.callout.monospaced())
                            }
                            Button("Check for watch request") {
                                Task { await model.refreshPendingPairings() }
                            }
                        }
                    }
                }
                ForEach(model.pendingPairings) { pairing in
                    RelayPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "applewatch.radiowaves.left.and.right")
                                    .font(.title2)
                                    .foregroundStyle(RelayPalette.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pairing.name).font(.headline)
                                    Text(
                                        "\(pairing.metadata.manufacturer) \(pairing.metadata.model) · \(pairing.metadata.screenShape)"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusPill(text: "Approval needed", ready: false)
                            }
                            Text(pairing.fingerprint)
                                .font(.callout.monospaced())
                            Text("Only approve if this fingerprint matches the watch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Deny", role: .destructive) {
                                    Task { await model.denyPairing(pairing) }
                                }
                                Button("Approve watch") {
                                    Task { await model.approvePairing(pairing) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(RelayPalette.accent)
                            }
                        }
                    }
                }
                if model.devices.isEmpty {
                    EmptyPanel(
                        icon: "applewatch",
                        title: "No paired watch yet",
                        detail: "Create a short code here, then enter it in Relay on the watch."
                    )
                } else {
                    ForEach(model.devices) { device in
                        RelayPanel {
                            HStack(spacing: 14) {
                                Image(systemName: "applewatch")
                                    .font(.title2)
                                    .foregroundStyle(RelayPalette.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name).font(.headline)
                                    Text(device.fingerprint)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusPill(
                                    text: device.revokedAt == nil ? "Active" : "Revoked",
                                    ready: device.revokedAt == nil
                                )
                                if device.revokedAt == nil {
                                    Button("Revoke", role: .destructive) {
                                        Task { await model.revoke(device) }
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Start secure pairing") {
                    Task { await model.createSecurePairingSession() }
                }
                .buttonStyle(.borderedProminent)
                .tint(RelayPalette.accent)
                .disabled(!model.cloudConnected || model.bridgeState != .running)
                if !model.cloudConnected {
                    Text("Connect Relay Cloud first. The watch enters this Mac’s six-character pairing code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.bridgeState != .running {
                    Text("Start the local Relay bridge before pairing a watch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
