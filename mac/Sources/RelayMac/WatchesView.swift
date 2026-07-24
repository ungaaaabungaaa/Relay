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
                if let pairing = model.pairingCode {
                    RelayPanel {
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
                Button("Create pairing code") {
                    Task { await model.createPairingCode() }
                }
                .buttonStyle(.borderedProminent)
                .tint(RelayPalette.accent)
            }
        }
    }
}
