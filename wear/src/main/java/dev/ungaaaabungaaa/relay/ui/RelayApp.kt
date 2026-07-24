package dev.ungaaaabungaaa.relay.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.ungaaaabungaaa.relay.domain.Screen
import dev.ungaaaabungaaa.relay.ui.components.RelayLabel
import dev.ungaaaabungaaa.relay.ui.screens.AboutScreen
import dev.ungaaaabungaaa.relay.ui.screens.ApprovalScreen
import dev.ungaaaabungaaa.relay.ui.screens.ConnectingScreen
import dev.ungaaaabungaaa.relay.ui.screens.ConnectionProblemScreen
import dev.ungaaaabungaaa.relay.ui.screens.EffortScreen
import dev.ungaaaabungaaa.relay.ui.screens.FolderScreen
import dev.ungaaaabungaaa.relay.ui.screens.HistoryScreen
import dev.ungaaaabungaaa.relay.ui.screens.HomeScreen
import dev.ungaaaabungaaa.relay.ui.screens.InboxScreen
import dev.ungaaaabungaaa.relay.ui.screens.InstructionScreen
import dev.ungaaaabungaaa.relay.ui.screens.MacIdentityScreen
import dev.ungaaaabungaaa.relay.ui.screens.ModelScreen
import dev.ungaaaabungaaa.relay.ui.screens.NewTaskReviewScreen
import dev.ungaaaabungaaa.relay.ui.screens.PairingCodeScreen
import dev.ungaaaabungaaa.relay.ui.screens.PermissionProfileScreen
import dev.ungaaaabungaaa.relay.ui.screens.PromptScreen
import dev.ungaaaabungaaa.relay.ui.screens.QuestionScreen
import dev.ungaaaabungaaa.relay.ui.screens.SettingsScreen
import dev.ungaaaabungaaa.relay.ui.screens.SystemInputScreen
import dev.ungaaaabungaaa.relay.ui.screens.TaskControlsScreen
import dev.ungaaaabungaaa.relay.ui.screens.TaskDetailScreen
import dev.ungaaaabungaaa.relay.ui.screens.TaskListScreen
import dev.ungaaaabungaaa.relay.ui.screens.TranscriptReviewScreen
import dev.ungaaaabungaaa.relay.ui.screens.VoiceRecordScreen
import dev.ungaaaabungaaa.relay.ui.screens.WelcomeScreen
import dev.ungaaaabungaaa.relay.ui.screens.WorkspaceScreen
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors
import dev.ungaaaabungaaa.relay.ui.theme.RelayTheme

@Composable
fun RelayApp(viewModel: RelayViewModel) {
    val state = viewModel.state
    val canMutate = state.connected && !state.stale
    RelayTheme {
        Box(Modifier.fillMaxSize()) {
            when (state.screen) {
                Screen.Welcome -> WelcomeScreen {
                    viewModel.navigate(Screen.PairingCode)
                }
                Screen.PairingCode -> PairingCodeScreen(
                    bridgeUrl = viewModel.bridgeUrl,
                    pairingCode = viewModel.pairingCode,
                    onBridgeUrlChange = { viewModel.bridgeUrl = it },
                    onPairingCodeChange = { viewModel.pairingCode = it },
                    onPair = viewModel::pair,
                    onAbout = { viewModel.navigate(Screen.About) },
                )
                Screen.MacIdentity -> MacIdentityScreen(
                    macName = "Your Mac",
                    fingerprint = viewModel.bridgeUrl,
                    onConfirm = viewModel::pair,
                    onBack = { viewModel.navigate(Screen.PairingCode) },
                )
                Screen.Connecting -> ConnectingScreen()
                Screen.Offline -> ConnectionProblemScreen(
                    title = "Mac offline",
                    body = "Wake the Mac and confirm Relay and Tailscale are running.",
                    actionLabel = "Reconnect",
                    onAction = { viewModel.refresh(startLiveAfter = true) },
                    onSettings = { viewModel.navigate(Screen.Settings) },
                )
                Screen.Revoked -> ConnectionProblemScreen(
                    title = "Watch revoked",
                    body = "This watch no longer has access. Clear its cached pairing and pair again.",
                    actionLabel = "Pair again",
                    onAction = viewModel::unpair,
                )
                Screen.UpdateRequired -> ConnectionProblemScreen(
                    title = "Update required",
                    body = "This Relay version cannot safely use the Mac bridge protocol.",
                    actionLabel = "About updates",
                    onAction = { viewModel.navigate(Screen.About) },
                )
                Screen.Home -> HomeScreen(
                    state = state,
                    onInbox = { viewModel.navigate(Screen.Inbox) },
                    onTasks = { viewModel.navigate(Screen.Tasks) },
                    onNewTask = viewModel::beginNewTask,
                    onSettings = { viewModel.navigate(Screen.Settings) },
                )
                Screen.Inbox -> InboxScreen(
                    state = state,
                    onApproval = viewModel::selectApproval,
                    onQuestion = viewModel::selectQuestion,
                    onHome = { viewModel.navigate(Screen.Home) },
                    onHistory = { viewModel.navigate(Screen.History) },
                )
                Screen.Approval -> ApprovalScreen(
                    approval = state.selectedApproval?.takeIf { selected ->
                        state.approvals.any { it.id == selected.id }
                    },
                    canRespond = canMutate,
                    onDeny = { viewModel.decide(false) },
                    onApprove = { viewModel.decide(true) },
                    onBack = { viewModel.navigate(Screen.Inbox) },
                )
                Screen.Question -> QuestionScreen(
                    question = state.selectedQuestion?.takeIf { selected ->
                        state.questions.any { it.id == selected.id }
                    },
                    answer = viewModel.questionAnswer,
                    reviewing = viewModel.questionReviewing,
                    canRespond = canMutate,
                    onAnswerChange = { viewModel.questionAnswer = it },
                    onReview = viewModel::reviewQuestion,
                    onSubmit = {
                        viewModel.answerQuestion(listOf(viewModel.questionAnswer.trim()))
                    },
                    onEdit = viewModel::editQuestionAnswer,
                    onBack = { viewModel.navigate(Screen.Inbox) },
                )
                Screen.Tasks -> TaskListScreen(
                    tasks = state.tasks,
                    stale = state.stale,
                    onTask = viewModel::selectTask,
                    onHome = { viewModel.navigate(Screen.Home) },
                )
                Screen.TaskDetail -> TaskDetailScreen(
                    task = state.selectedTask,
                    stale = state.stale,
                    onInstruction = { viewModel.navigate(Screen.Instruction) },
                    onControls = { viewModel.navigate(Screen.TaskControls) },
                    onBack = { viewModel.navigate(Screen.Tasks) },
                )
                Screen.Instruction -> InstructionScreen(
                    task = state.selectedTask,
                    instruction = viewModel.instruction,
                    canSend = canMutate && state.selectedTask != null,
                    onInstructionChange = { viewModel.instruction = it },
                    onSend = viewModel::sendInstruction,
                    onSystemInput = { viewModel.navigate(Screen.SystemInput) },
                    onVoice = { viewModel.navigate(Screen.VoiceRecord) },
                    onBack = { viewModel.navigate(Screen.TaskDetail) },
                )
                Screen.SystemInput -> SystemInputScreen(
                    text = viewModel.instruction,
                    onTextChange = { viewModel.instruction = it },
                    onReview = { viewModel.navigate(Screen.Instruction) },
                    onBack = { viewModel.navigate(Screen.Instruction) },
                )
                Screen.VoiceRecord -> VoiceRecordScreen(
                    onSystemInput = { viewModel.navigate(Screen.SystemInput) },
                    onBack = { viewModel.navigate(Screen.Instruction) },
                )
                Screen.TranscriptReview -> TranscriptReviewScreen(
                    transcript = state.transcript,
                    canSend = canMutate,
                    onSend = viewModel::sendInstruction,
                    onRerecord = { viewModel.navigate(Screen.VoiceRecord) },
                    onCancel = { viewModel.navigate(Screen.Instruction) },
                )
                Screen.TaskControls -> TaskControlsScreen(
                    task = state.selectedTask,
                    canControl = canMutate,
                    onInstruction = { viewModel.navigate(Screen.Instruction) },
                    onBack = { viewModel.navigate(Screen.TaskDetail) },
                )
                Screen.Workspaces -> WorkspaceScreen(
                    folders = state.folders,
                    loading = state.loading,
                    onWorkspace = viewModel::selectWorkspace,
                    onCancel = { viewModel.navigate(Screen.Home) },
                )
                Screen.Folders -> FolderScreen(
                    currentPath = state.newTaskDraft.folder,
                    folders = state.folders,
                    loading = state.loading,
                    onFolder = viewModel::openFolder,
                    onUseFolder = viewModel::useSelectedFolder,
                    onBack = { viewModel.navigate(Screen.Workspaces) },
                )
                Screen.Models -> ModelScreen(
                    models = state.models,
                    loading = state.loading,
                    onModel = viewModel::selectModel,
                    onBack = { viewModel.navigate(Screen.Folders) },
                )
                Screen.Effort -> EffortScreen(
                    model = state.models.firstOrNull { it.id == state.newTaskDraft.modelId },
                    selectedEffort = state.newTaskDraft.effort,
                    onEffort = viewModel::selectEffort,
                    onBack = { viewModel.navigate(Screen.Models) },
                )
                Screen.Permissions -> PermissionProfileScreen(
                    selected = state.newTaskDraft.permissionProfile,
                    onProfile = viewModel::selectPermissionProfile,
                    onBack = { viewModel.navigate(Screen.Effort) },
                )
                Screen.Prompt -> PromptScreen(
                    prompt = state.newTaskDraft.prompt,
                    onPromptChange = viewModel::updateDraftPrompt,
                    onReview = viewModel::reviewNewTask,
                    onBack = { viewModel.navigate(Screen.Permissions) },
                )
                Screen.NewTaskReview -> NewTaskReviewScreen(
                    state = state,
                    canStart = canMutate && !state.loading,
                    onStart = viewModel::startNewTask,
                    onBack = { viewModel.navigate(Screen.Prompt) },
                    onCancel = { viewModel.navigate(Screen.Home) },
                )
                Screen.History -> HistoryScreen(
                    history = state.history,
                    onBack = { viewModel.navigate(Screen.Inbox) },
                )
                Screen.Settings -> SettingsScreen(
                    bridgeUrl = viewModel.bridgeUrl,
                    connectionState = state.connectionState,
                    onRefresh = { viewModel.refresh(startLiveAfter = true) },
                    onHistory = { viewModel.navigate(Screen.History) },
                    onAbout = { viewModel.navigate(Screen.About) },
                    onUnpair = viewModel::unpair,
                    onBack = {
                        viewModel.navigate(
                            if (state.connectionState == dev.ungaaaabungaaa.relay.domain.RelayConnectionState.Unpaired) {
                                Screen.PairingCode
                            } else {
                                Screen.Home
                            },
                        )
                    },
                )
                Screen.About -> AboutScreen(
                    onBack = {
                        viewModel.navigate(
                            if (state.connectionState == dev.ungaaaabungaaa.relay.domain.RelayConnectionState.Unpaired) {
                                Screen.PairingCode
                            } else {
                                Screen.Settings
                            },
                        )
                    },
                )
            }

            state.error?.let { message ->
                Box(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 8.dp)
                        .background(RelayColors.Red, RoundedCornerShape(18.dp))
                        .clickable(onClick = viewModel::clearError)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                ) {
                    RelayLabel(message, color = RelayColors.Ink, size = 9)
                }
            }
        }
    }
}
