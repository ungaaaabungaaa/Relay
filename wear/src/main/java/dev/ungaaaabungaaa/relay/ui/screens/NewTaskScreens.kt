package dev.ungaaaabungaaa.relay.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily
import dev.ungaaaabungaaa.relay.domain.RelayFolder
import dev.ungaaaabungaaa.relay.domain.RelayModel
import dev.ungaaaabungaaa.relay.domain.RelayState
import dev.ungaaaabungaaa.relay.ui.components.RelayActionButton
import dev.ungaaaabungaaa.relay.ui.components.RelayCard
import dev.ungaaaabungaaa.relay.ui.components.RelayInput
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.components.RelayList
import dev.ungaaaabungaaa.relay.ui.components.RelayTextButton
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun WorkspaceScreen(
    folders: List<RelayFolder>,
    loading: Boolean,
    onWorkspace: (RelayFolder) -> Unit,
    onCancel: () -> Unit,
) {
    RelayList(title = "Choose workspace") {
        if (loading) {
            item { RelayLabel("Loading approved roots…", color = RelayColors.Blue, size = 10) }
        }
        if (!loading && folders.isEmpty()) {
            item {
                RelayLabel(
                    "No workspace is approved. Add one in the Mac app first.",
                    color = RelayColors.Amber,
                    size = 10,
                )
            }
        }
        items(folders.size) { index ->
            val folder = folders[index]
            RelayCard(
                title = folder.name,
                detail = folder.path,
                onClick = { onWorkspace(folder) },
            )
        }
        item { RelayTextButton("Cancel", onClick = onCancel) }
    }
}

@Composable
fun FolderScreen(
    currentPath: String,
    folders: List<RelayFolder>,
    loading: Boolean,
    onFolder: (RelayFolder) -> Unit,
    onUseFolder: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Choose folder") {
        item {
            RelayLabel(
                currentPath,
                color = RelayColors.Muted,
                size = 9,
                family = FontFamily.Monospace,
            )
        }
        if (loading) {
            item { RelayLabel("Loading…", color = RelayColors.Blue, size = 10) }
        }
        items(folders.size) { index ->
            val folder = folders[index]
            RelayCard(
                title = folder.name,
                detail = folder.path,
                onClick = { onFolder(folder) },
            )
        }
        item {
            RelayActionButton(
                "Use this folder",
                enabled = currentPath.isNotBlank(),
                color = RelayColors.Green,
                onClick = onUseFolder,
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun ModelScreen(
    models: List<RelayModel>,
    loading: Boolean,
    onModel: (RelayModel) -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Choose model") {
        if (loading) {
            item { RelayLabel("Loading Codex models…", color = RelayColors.Blue, size = 10) }
        }
        items(models.size) { index ->
            val model = models[index]
            RelayCard(
                title = model.name,
                detail = model.description,
                onClick = { onModel(model) },
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun EffortScreen(
    model: RelayModel?,
    selectedEffort: String,
    onEffort: (String) -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Reasoning effort") {
        item {
            RelayLabel(
                model?.name ?: "Choose a model first",
                color = RelayColors.Muted,
                size = 10,
            )
        }
        model?.efforts?.forEach { effort ->
            item {
                RelayCard(
                    title = effort.replaceFirstChar(Char::uppercase),
                    detail = if (effort == selectedEffort) "Selected" else "Use $effort reasoning",
                    tone = if (effort == selectedEffort) {
                        RelayColors.Green.copy(alpha = 0.12f)
                    } else {
                        RelayColors.Surface
                    },
                    onClick = { onEffort(effort) },
                )
            }
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun PermissionProfileScreen(
    selected: String,
    onProfile: (String) -> Unit,
    onBack: () -> Unit,
) {
    val profiles = listOf(
        Triple("On request", "Codex asks before sensitive actions", true),
        Triple("Read only", "Not exposed by the installed Codex adapter", false),
    )
    RelayList(title = "Permission profile") {
        profiles.forEach { (name, detail, supported) ->
            item {
                RelayCard(
                    title = name,
                    detail = if (name == selected) "$detail · Selected" else detail,
                    enabled = supported,
                    tone = if (name == selected) {
                        RelayColors.Green.copy(alpha = 0.12f)
                    } else {
                        RelayColors.Surface
                    },
                    onClick = { if (supported) onProfile(name) },
                )
            }
        }
        item {
            RelayLabel(
                "Relay never auto-approves dangerous actions.",
                color = RelayColors.Amber,
                size = 9,
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun PromptScreen(
    prompt: String,
    onPromptChange: (String) -> Unit,
    onReview: () -> Unit,
    onBack: () -> Unit,
) {
    RelayList(title = "Task prompt") {
        item {
            RelayInput(
                value = prompt,
                hint = "What should Codex do?",
                singleLine = false,
                onChange = onPromptChange,
            )
        }
        item {
            RelayActionButton(
                "Review task",
                enabled = prompt.isNotBlank(),
                color = RelayColors.Green,
                onClick = onReview,
            )
        }
        item { RelayTextButton("Back", onClick = onBack) }
    }
}

@Composable
fun NewTaskReviewScreen(
    state: RelayState,
    canStart: Boolean,
    onStart: () -> Unit,
    onBack: () -> Unit,
    onCancel: () -> Unit,
) {
    val draft = state.newTaskDraft
    RelayList(title = "Review new task") {
        item { RelayCard("Folder", draft.folder, enabled = false, onClick = {}) }
        item {
            RelayCard(
                "Model",
                "${draft.modelName} · ${draft.effort}",
                enabled = false,
                onClick = {},
            )
        }
        item {
            RelayCard(
                "Permissions",
                draft.permissionProfile,
                enabled = false,
                onClick = {},
            )
        }
        item {
            RelayLabel(
                draft.prompt,
                size = 10,
                maxLines = 5,
            )
        }
        item {
            RelayActionButton(
                "Start Codex task",
                enabled = canStart,
                color = RelayColors.Green,
                onClick = onStart,
            )
        }
        item { RelayTextButton("Edit prompt", onClick = onBack) }
        item { RelayTextButton("Cancel", onClick = onCancel) }
    }
}
