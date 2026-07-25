import SwiftUI

struct WatchesView: View {
    @ObservedObject var model: RelayAppModel
    @State private var pairingAddress = ""
    @State private var connectionAddress = ""
    @State private var pairingCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Devices",
                    title: "Your watches",
                    detail: "Pairing grants one watch its own signing identity. Revoking a watch blocks it immediately."
                )
                RelayPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Wireless ADB installer", systemImage: "wifi")
                                .font(.headline)
                            Spacer()
                            StatusPill(
                                text: model.platformToolsReady ? "Tools ready" : "Tools missing",
                                ready: model.platformToolsReady
                            )
                        }
                        Text(
                            "On the watch: Developer options → Wireless debugging → Pair new device. Pairing and connection ports are different."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        HStack {
                            TextField("IP: pairing port", text: $pairingAddress)
                            SecureField("6-digit code", text: $pairingCode)
                                .frame(maxWidth: 140)
                        }
                        TextField("IP: connection port", text: $connectionAddress)
                        HStack {
                            Button("Discover") {
                                Task { await model.discoverWatch() }
                            }
                            Button("Pair and connect") {
                                Task {
                                    await model.pairWatch(
                                        pairingAddress: pairingAddress,
                                        code: pairingCode,
                                        connectionAddress: connectionAddress
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(RelayPalette.accent)
                            Button("Install Relay") {
                                Task { await model.installWatchApp() }
                            }
                            .disabled({
                                if case .ready = model.adbWizardState { return false }
                                return true
                            }())
                        }
                        Text(wizardDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let pairing = model.pairingSession {
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
                .disabled(!model.funnelEnabled)
                if !model.funnelEnabled {
                    Text("Enable secure remote access first so the watch receives a valid HTTPS address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.adbWizardState) { _, state in
            if case .readyToPair(let services) = state {
                pairingAddress = services.pairing.first ?? pairingAddress
                connectionAddress = services.connection.first ?? connectionAddress
            }
        }
    }

    private var wizardDescription: String {
        switch model.adbWizardState {
        case .idle: "Ready to discover a watch or enter the addresses manually."
        case .discovering: "Looking for Wireless debugging services…"
        case .manualEntry: "No service found. Manual addresses work just as well."
        case .readyToPair(let services):
            "Found \(services.pairing.count) pairing and \(services.connection.count) connection service(s)."
        case .pairing: "Pairing with the short-lived watch code…"
        case .connecting: "Connecting to the watch…"
        case .verifyingWatch: "Verifying the Wear OS hardware feature…"
        case .installing: "Installing or updating Relay…"
        case .verifyingInstall: "Verifying the installed package version…"
        case .ready(let serial): "Wear OS watch ready at \(serial)."
        case .failed(let message): message
        }
    }
}
