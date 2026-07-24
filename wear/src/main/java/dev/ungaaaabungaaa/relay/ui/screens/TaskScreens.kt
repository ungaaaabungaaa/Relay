package dev.ungaaaabungaaa.relay.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import dev.ungaaaabungaaa.relay.domain.RelayTask
import dev.ungaaaabungaaa.relay.ui.components.RelayActionButton
import dev.ungaaaabungaaa.relay.ui.components.RelayCard
import dev.ungaaaabungaaa.relay.ui.components.RelayInput
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.components.RelayList
import dev.ungaaaabungaaa.relay.ui.components.RelayTextButton
import dev.ungaaaabungaaa.relay.ui.components.HoldToRecord
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun TaskListScreen(
    tasks: List<RelayTask>,
    stale: Boolean,
    onTask: (RelayTask) -> Unit,
    onHome: () -> Unit,
) {
    RelayList(
        title = "Codex tasks",
        status = if (stale) "Cached summaries" else null,
    ) {
        if (tasks.isEmpty()) {
            item {
                RelayLabel(
                    "No recent tasks. Start one on your Mac or from Relay.",
                    color = RelayColors.Muted,
                    size = 10,
                )
            }
        }
        items(tasks.size) { index ->
            val task = tasks[index]
            RelayCard(
                title = task.title,
                detail = "${task.status} · ${task.cwd}",
                onClick = { onTask(task) },
            )
        }
        item { RelayTextButton("Home", onClick = onHome) }
    }
}

@Composable
fun TaskDetailScreen(
    task: RelayTask?,
    stale: Boolean,
    onInstruction: () -> Unit,
    onControls: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(
        title = task?.title ?: "Task unavailable",
        status = if (stale) "Cached · controls disabled" else task?.status,
    ) {
        item {
            RelayLabel(
                task?.cwd ?: "Refresh the task list.",
                color = RelayColors.Muted,
                size = 9,
                family = FontFamily.Monospace,
            )
        }
        task?.preview?.takeIf(String::isNotBlank)?.let { preview ->
            item { RelayLabel(preview, size = 10) }
        }
        item {
            RelayCard(
                title = "Activity",
                detail = "Concise task events appear here as Codex works",
                enabled = false,
                onClick = {},
            )
        }
        item {
            RelayActionButton(
                "Send instruction",
                enabled = task != null && !stale,
                onClick = onInstruction,
            )
        }
        item {
            RelayTextButton(
                "Task controls",
                enabled = task != null && !stale,
                onClick = onControls,
            )
        }
        item { RelayTextButton("Back to tasks", onClick = onBack) }
    }
}

@Composable
fun InstructionScreen(
    task: RelayTask?,
    instruction: String,
    canSend: Boolean,
    onInstructionChange: (String) -> Unit,
    onSend: () -> Unit,
    onSystemInput: () -> Unit,
    onVoice: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Instruction") {
        item {
            RelayLabel(
                task?.title ?: "No task selected",
                size = 12,
                weight = FontWeight.Bold,
            )
        }
        item {
            RelayInput(
                value = instruction,
                hint = "Tell Codex what to do next",
                singleLine = false,
                onChange = onInstructionChange,
            )
        }
        item {
            RelayActionButton(
                "Review & send",
                enabled = canSend && instruction.isNotBlank(),
                color = RelayColors.Green,
                onClick = onSend,
            )
        }
        item {
            RelayCard(
                title = "Wear OS input",
                detail = "Keyboard or built-in voice · no API key",
                enabled = canSend,
                onClick = onSystemInput,
            )
        }
        item {
            RelayCard(
                title = "Hold to record",
                detail = "Optional Mac transcription · review required",
                enabled = canSend,
                onClick = onVoice,
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun SystemInputScreen(
    text: String,
    onTextChange: (String) -> Unit,
    onReview: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Wear OS input") {
        item {
            RelayLabel(
                "Use the watch keyboard or microphone, then review the text.",
                color = RelayColors.Muted,
                size = 10,
            )
        }
        item {
            RelayInput(
                value = text,
                hint = "Instruction",
                singleLine = false,
                onChange = onTextChange,
            )
        }
        item {
            RelayActionButton(
                "Review",
                enabled = text.isNotBlank(),
                onClick = onReview,
            )
        }
        item { RelayTextButton("Cancel", onClick = onBack) }
    }
}

@Composable
fun VoiceRecordScreen(
    recording: Boolean,
    transcribing: Boolean,
    canRecord: Boolean,
    microphoneGranted: Boolean,
    onRequestMicrophone: () -> Unit,
    onStartRecording: () -> Unit,
    onStopRecording: () -> Unit,
    onCancelRecording: () -> Unit,
    onSystemInput: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Voice") {
        when {
            transcribing -> {
                item {
                    RelayLabel(
                        "Transcribing on your Mac…",
                        color = RelayColors.Blue,
                        size = 11,
                    )
                }
            }
            else -> {
                item {
                    RelayLabel(
                        if (recording) {
                            "Recording · automatic stop at 30 seconds"
                        } else {
                            "Audio is deleted after transcription or cancellation."
                        },
                        color = if (recording) RelayColors.Red else RelayColors.Muted,
                        size = 9,
                    )
                }
                if (microphoneGranted) {
                    item {
                        HoldToRecord(
                            enabled = canRecord,
                            recording = recording,
                            onStart = onStartRecording,
                            onStop = onStopRecording,
                            onCancel = onCancelRecording,
                        )
                    }
                } else {
                    item {
                        RelayActionButton(
                            "Enable microphone",
                            enabled = canRecord,
                            color = RelayColors.Red,
                            onClick = onRequestMicrophone,
                        )
                    }
                    item {
                        RelayLabel(
                            "Permission is requested only for this custom mode.",
                            color = RelayColors.Muted,
                            size = 9,
                        )
                    }
                }
                item {
                    RelayCard(
                        title = "Use Wear OS voice",
                        detail = "System input · no OpenAI key",
                        enabled = canRecord && !recording,
                        onClick = onSystemInput,
                    )
                }
                item {
                    RelayTextButton(
                        if (recording) "Cancel & delete" else "Back",
                        onClick = if (recording) onCancelRecording else onBack,
                    )
                }
            }
        }
    }
}

@Composable
fun TranscriptReviewScreen(
    transcript: String,
    canSend: Boolean,
    onSend: () -> Unit,
    onRerecord: () -> Unit,
    onCancel: () -> Unit,
) {
    RelayList(title = "Review transcript") {
        item {
            RelayLabel(
                transcript.ifBlank { "Nothing has been transcribed yet." },
                size = 11,
            )
        }
        item {
            RelayActionButton(
                "Send to Codex",
                enabled = canSend && transcript.isNotBlank(),
                color = RelayColors.Green,
                onClick = onSend,
            )
        }
        item { RelayTextButton("Re-record", onClick = onRerecord) }
        item { RelayTextButton("Cancel", onClick = onCancel) }
    }
}

@Composable
fun TaskControlsScreen(
    task: RelayTask?,
    canControl: Boolean,
    onInstruction: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Task controls") {
        item {
            RelayLabel(
                task?.title ?: "No active task",
                size = 12,
                weight = FontWeight.Bold,
            )
        }
        item {
            RelayCard(
                title = "Steer task",
                detail = "Send a follow-up instruction",
                enabled = canControl,
                onClick = onInstruction,
            )
        }
        item {
            RelayCard(
                title = "Stop turn",
                detail = "Unavailable until Codex exposes the active turn ID",
                enabled = false,
                tone = RelayColors.Red.copy(alpha = 0.12f),
                onClick = {},
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}
