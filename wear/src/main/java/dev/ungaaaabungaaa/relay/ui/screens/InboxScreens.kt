package dev.ungaaaabungaaa.relay.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayQuestion
import dev.ungaaaabungaaa.relay.domain.RelayState
import dev.ungaaaabungaaa.relay.domain.requiresHold
import dev.ungaaaabungaaa.relay.ui.components.HoldToConfirm
import dev.ungaaaabungaaa.relay.ui.components.RelayActionButton
import dev.ungaaaabungaaa.relay.ui.components.RelayCard
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.components.RelayList
import dev.ungaaaabungaaa.relay.ui.components.RelayTextButton
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun InboxScreen(
    state: RelayState,
    onApproval: (RelayApproval) -> Unit,
    onQuestion: (RelayQuestion) -> Unit,
    onHome: () -> Unit,
    onHistory: () -> Unit,
) {
    RelayList(
        title = "Action inbox",
        status = if (state.stale) "Read-only cached state" else null,
    ) {
        if (state.loading) {
            item { RelayLabel("Refreshing…", color = RelayColors.Blue, size = 10) }
        }
        if (state.approvals.isEmpty() && state.questions.isEmpty() && !state.loading) {
            item {
                RelayLabel(
                    "Nothing is blocking Codex",
                    color = RelayColors.Green,
                    size = 11,
                )
            }
        }
        items(state.approvals.size) { index ->
            val approval = state.approvals[index]
            RelayCard(
                title = approval.command ?: approval.kind,
                detail = "${approval.risk.name} · ${approval.cwd ?: "Approval required"}",
                enabled = !state.stale,
                tone = RelayColors.Red.copy(alpha = 0.14f),
                onClick = { onApproval(approval) },
            )
        }
        items(state.questions.size) { index ->
            val question = state.questions[index]
            RelayCard(
                title = "Codex question",
                detail = question.prompt,
                enabled = !state.stale,
                tone = RelayColors.Blue.copy(alpha = 0.12f),
                onClick = { onQuestion(question) },
            )
        }
        item { RelayTextButton("Approval history", onClick = onHistory) }
        item { RelayTextButton("Home", onClick = onHome) }
    }
}

@Composable
fun ApprovalScreen(
    approval: RelayApproval?,
    canRespond: Boolean,
    onDeny: () -> Unit,
    onApprove: () -> Unit,
    onBack: () -> Unit,
) {
    val expired = approval == null
    RelayList(
        title = if (expired) "Approval expired" else "Approval",
        status = when {
            expired -> "Refresh the inbox"
            !canRespond -> "Read-only while disconnected"
            approval?.requiresHold() == true -> "Dangerous · hold to approve"
            else -> "Normal · one-tap approval"
        },
    ) {
        item {
            RelayLabel(
                approval?.command ?: approval?.kind ?: "This request is no longer pending.",
                size = 12,
                family = FontFamily.Monospace,
            )
        }
        approval?.cwd?.let { path ->
            item {
                RelayLabel(path, color = RelayColors.Muted, size = 9, family = FontFamily.Monospace)
            }
        }
        approval?.riskReasons?.forEach { consequence ->
            item { RelayLabel("• $consequence", color = RelayColors.Amber, size = 9) }
        }
        approval?.reason?.let { reason ->
            item { RelayLabel(reason, color = RelayColors.Muted, size = 9) }
        }
        if (!expired) {
            item {
                RelayActionButton(
                    "Deny",
                    enabled = canRespond,
                    color = RelayColors.Red,
                    onClick = onDeny,
                )
            }
            item {
                if (approval?.requiresHold() == true) {
                    HoldToConfirm(
                        label = "Hold 1.5s to approve",
                        enabled = canRespond,
                        onConfirm = onApprove,
                    )
                } else {
                    RelayActionButton(
                        "Approve",
                        enabled = canRespond,
                        color = RelayColors.Green,
                        onClick = onApprove,
                    )
                }
            }
        }
        item { RelayTextButton("Back to inbox", onClick = onBack) }
    }
}

@Composable
fun QuestionScreen(
    question: RelayQuestion?,
    answer: String,
    reviewing: Boolean,
    canRespond: Boolean,
    onAnswerChange: (String) -> Unit,
    onReview: (String) -> Unit,
    onSubmit: () -> Unit,
    onEdit: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(
        title = if (question == null) "Question expired" else "Codex asks",
        status = if (!canRespond) "Read-only while disconnected" else null,
    ) {
        item {
            RelayLabel(
                question?.prompt ?: "This question was already answered or timed out.",
                size = 12,
            )
        }
        if (reviewing) {
            item {
                RelayCard(
                    title = "Your answer",
                    detail = answer,
                    enabled = false,
                    tone = RelayColors.Green.copy(alpha = 0.12f),
                    onClick = {},
                )
            }
            item {
                RelayActionButton(
                    "Submit answer",
                    enabled = canRespond && answer.isNotBlank(),
                    color = RelayColors.Green,
                    onClick = onSubmit,
                )
            }
            item { RelayTextButton("Edit answer", onClick = onEdit) }
        } else {
            question?.options?.forEach { option ->
                item {
                    RelayCard(
                        title = option,
                        detail = "Review this answer before submitting",
                        enabled = canRespond,
                        onClick = { onReview(option) },
                    )
                }
            }
            if (question != null) {
                item {
                    dev.ungaaaabungaaa.relay.ui.components.RelayInput(
                        value = answer,
                        hint = "Short answer",
                        onChange = onAnswerChange,
                    )
                }
                item {
                    RelayActionButton(
                        "Review answer",
                        enabled = canRespond && answer.isNotBlank(),
                        color = RelayColors.Green,
                        onClick = { onReview(answer.trim()) },
                    )
                }
            }
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}
