package dev.ungaaaabungaaa.relay.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily
import dev.ungaaaabungaaa.relay.domain.ApprovalHistoryItem
import dev.ungaaaabungaaa.relay.domain.RelayConnectionState
import dev.ungaaaabungaaa.relay.ui.components.RelayActionButton
import dev.ungaaaabungaaa.relay.ui.components.RelayCard
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.components.RelayList
import dev.ungaaaabungaaa.relay.ui.components.RelayStatusPill
import dev.ungaaaabungaaa.relay.ui.components.RelayTextButton
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun HistoryScreen(
    history: List<ApprovalHistoryItem>,
    onBack: () -> Unit,
) {
    RelayList(title = "Approval history") {
        if (history.isEmpty()) {
            item {
                RelayLabel(
                    "Decisions made on this watch will appear here.",
                    color = RelayColors.Muted,
                    size = 10,
                )
            }
        }
        items(history.size) { index ->
            val item = history[index]
            RelayCard(
                title = item.decision,
                detail = item.summary,
                enabled = false,
                onClick = {},
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun SettingsScreen(
    bridgeUrl: String,
    connectionState: RelayConnectionState,
    onRefresh: () -> Unit,
    onHistory: () -> Unit,
    onAbout: () -> Unit,
    onUnpair: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Settings") {
        item {
            RelayStatusPill(
                text = connectionState.name.uppercase(),
                color = if (connectionState == RelayConnectionState.Live) {
                    RelayColors.Green
                } else {
                    RelayColors.Amber
                },
            )
        }
        item {
            RelayLabel(
                bridgeUrl,
                color = RelayColors.Muted,
                size = 9,
                family = FontFamily.Monospace,
            )
        }
        item { RelayCard("Refresh now", "Fetch a new authenticated snapshot", onClick = onRefresh) }
        item {
            RelayCard(
                "Live monitoring",
                "Off · optional four-hour battery-visible mode",
                enabled = false,
                onClick = {},
            )
        }
        item { RelayCard("Approval history", "Decisions made on this watch", onClick = onHistory) }
        item { RelayCard("About", "License, versions, and update state", onClick = onAbout) }
        item {
            RelayActionButton(
                "Unpair watch",
                color = RelayColors.Red,
                onClick = onUnpair,
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun AboutScreen(
    onBack: () -> Unit,
) {
    RelayList(title = "About Relay") {
        item { RelayLabel("Relay 0.1.0", size = 14) }
        item {
            RelayLabel(
                "Wear OS companion for Mac-hosted Codex sessions",
                color = RelayColors.Muted,
                size = 10,
            )
        }
        item { RelayCard("License", "Apache License 2.0", enabled = false, onClick = {}) }
        item {
            RelayCard(
                "Update state",
                "GitHub release build · manual updates",
                enabled = false,
                onClick = {},
            )
        }
        item {
            RelayLabel(
                "No Codex credential or Mac password is stored on the watch.",
                color = RelayColors.Green,
                size = 9,
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}
