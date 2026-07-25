package dev.ungaaaabungaaa.relay.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.ungaaaabungaaa.relay.ui.components.RelayActionButton
import dev.ungaaaabungaaa.relay.ui.components.RelayInput
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.components.RelayList
import dev.ungaaaabungaaa.relay.ui.components.RelayScreen
import dev.ungaaaabungaaa.relay.ui.components.RelayTextButton
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    RelayScreen {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            RelayLabel(
                "RELAY",
                size = 24,
                weight = FontWeight.Bold,
                family = FontFamily.Monospace,
            )
            RelayLabel("Your Codex sessions, from your wrist", color = RelayColors.Muted, size = 10)
            Spacer(Modifier.height(14.dp))
            RelayActionButton("Get started", color = RelayColors.Green, onClick = onContinue)
        }
    }
}

@Composable
fun PairingCodeScreen(
    bridgeUrl: String,
    pairingCode: String,
    macName: String?,
    discovering: Boolean,
    showManualOrigin: Boolean,
    onBridgeUrlChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onPair: () -> Unit,
    onRetryDiscovery: () -> Unit,
    onAbout: () -> Unit,
) {
    RelayList(title = "Pair with Mac") {
        item {
            RelayLabel(
                when {
                    macName != null -> "Found $macName. Enter the code shown on the Mac."
                    discovering -> "Looking for Relay on this Wi-Fi…"
                    else -> "Open Relay on the Mac and start secure pairing."
                },
                color = RelayColors.Muted,
                size = 10,
            )
        }
        if (showManualOrigin) {
            item {
                RelayInput(
                    value = bridgeUrl,
                    hint = "Debug recovery URL",
                    onChange = onBridgeUrlChange,
                )
            }
        }
        item {
            RelayInput(
                value = pairingCode,
                hint = "6-character code",
                onChange = { onPairingCodeChange(it.uppercase().take(6)) },
            )
        }
        item {
            RelayActionButton(
                "Pair watch",
                enabled = pairingCode.length == 6 && (macName != null || showManualOrigin),
                color = RelayColors.Green,
                onClick = onPair,
            )
        }
        if (macName == null) {
            item { RelayTextButton("Search again", onClick = onRetryDiscovery) }
        }
        item { RelayTextButton("About Relay", onClick = onAbout) }
    }
}

@Composable
fun MacIdentityScreen(
    macName: String,
    fingerprint: String,
    watchFingerprint: String,
    onConfirm: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Confirm Mac") {
        item { RelayLabel(macName, size = 15, weight = FontWeight.Bold) }
        item {
            RelayLabel(
                fingerprint,
                color = RelayColors.Muted,
                size = 9,
                family = FontFamily.Monospace,
            )
        }
        item {
            RelayLabel("This watch", color = RelayColors.Muted, size = 9)
            RelayLabel(
                watchFingerprint,
                color = RelayColors.Muted,
                size = 8,
                family = FontFamily.Monospace,
            )
        }
        item {
            RelayLabel(
                "Confirm the same identity is shown on your Mac.",
                color = RelayColors.Amber,
                size = 10,
            )
        }
        item { RelayActionButton("It matches", color = RelayColors.Green, onClick = onConfirm) }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun ConnectingScreen() {
    RelayScreen {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            RelayLabel("CONNECTING", color = RelayColors.Blue, size = 11, family = FontFamily.Monospace)
            Spacer(Modifier.height(8.dp))
            RelayLabel("Opening a private session with your Mac", size = 12)
        }
    }
}

@Composable
fun ConnectionProblemScreen(
    title: String,
    body: String,
    actionLabel: String,
    onAction: () -> Unit,
    onSettings: (() -> Unit)? = null,
) {
    RelayList(title = title) {
        item { RelayLabel(body, color = RelayColors.Muted, size = 10) }
        item { RelayActionButton(actionLabel, onClick = onAction) }
        onSettings?.let { callback ->
            item { RelayTextButton("Settings", onClick = callback) }
        }
    }
}
