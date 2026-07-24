package dev.ungaaaabungaaa.relay.ui.screens

import androidx.compose.runtime.Composable
import dev.ungaaaabungaaa.relay.domain.RelayState
import dev.ungaaaabungaaa.relay.ui.components.RelayCard
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.components.RelayList
import dev.ungaaaabungaaa.relay.ui.components.RelayStatusPill
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun HomeScreen(
    state: RelayState,
    onInbox: () -> Unit,
    onTasks: () -> Unit,
    onNewTask: () -> Unit,
    onSettings: () -> Unit,
) {
    val waitingCount = state.approvals.size + state.questions.size
    val running = state.tasks.firstOrNull { it.status == "running" }
    RelayList(
        title = "Relay",
        status = if (state.stale) "Cached · Mac unreachable" else null,
    ) {
        item {
            RelayStatusPill(
                text = if (state.connected) "LIVE" else "OFFLINE",
                color = if (state.connected) RelayColors.Green else RelayColors.Amber,
            )
        }
        if (waitingCount > 0) {
            item {
                RelayCard(
                    title = "$waitingCount waiting",
                    detail = "Approvals and questions need you",
                    tone = RelayColors.Red.copy(alpha = 0.16f),
                    enabled = !state.stale,
                    onClick = onInbox,
                )
            }
        } else {
            item {
                RelayCard(
                    title = "Inbox clear",
                    detail = if (state.connected) {
                        "Nothing is blocking Codex"
                    } else {
                        "Reconnect to check for new actions"
                    },
                    enabled = true,
                    onClick = onInbox,
                )
            }
        }
        running?.let { task ->
            item {
                RelayCard(
                    title = task.title,
                    detail = "Running · ${task.cwd}",
                    enabled = true,
                    tone = RelayColors.Green.copy(alpha = 0.12f),
                    onClick = onTasks,
                )
            }
        }
        item {
            RelayCard(
                title = "Tasks",
                detail = "${state.tasks.size} recent Codex sessions",
                onClick = onTasks,
            )
        }
        item {
            RelayCard(
                title = "New task",
                detail = "Workspace · model · effort · review",
                enabled = state.connected && !state.stale,
                onClick = onNewTask,
            )
        }
        item {
            RelayCard(
                title = "Settings",
                detail = "Connection, monitoring, pairing, and about",
                onClick = onSettings,
            )
        }
        if (state.tasks.isEmpty() && waitingCount == 0) {
            item {
                RelayLabel(
                    if (state.connected) {
                        "Start a Codex task on your Mac or create one here."
                    } else {
                        "Your cached summaries will appear here when available."
                    },
                    color = RelayColors.Muted,
                    size = 9,
                )
            }
        }
    }
}
