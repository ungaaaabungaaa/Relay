import SwiftUI

struct VoiceView: View {
    @ObservedObject var model: RelayAppModel
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DashboardHeader(
                    eyebrow: "Optional",
                    title: "Voice instructions",
                    detail: "Wear OS system input needs no key. Custom hold-to-record uses an OpenAI key stored only in macOS Keychain."
                )
                RelayPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("System watch input", systemImage: "keyboard")
                                .font(.headline)
                            Spacer()
                            StatusPill(text: "Always available", ready: true)
                        }
                        Text("The watch returns editable text to Relay before anything is sent to Codex.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                RelayPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Custom recording", systemImage: "waveform.badge.mic")
                                .font(.headline)
                            Spacer()
                            StatusPill(
                                text: model.voiceConfigured ? "Configured" : "Off",
                                ready: model.voiceConfigured
                            )
                        }
                        SecureField("OpenAI API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Save in Keychain") {
                                let value = apiKey
                                apiKey = ""
                                Task { await model.saveOpenAIKey(value) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(RelayPalette.accent)
                            if model.voiceConfigured {
                                Button("Remove key", role: .destructive) {
                                    Task { await model.saveOpenAIKey("") }
                                }
                            }
                        }
                        Text("Recordings are capped at 30 seconds and deleted on every success or failure path.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
