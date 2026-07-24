package dev.ungaaaabungaaa.relay.domain

enum class Screen {
    Pairing,
    Offline,
    Inbox,
    Approval,
    Question,
    Tasks,
    TaskDetail,
    Voice,
    Transcript,
    Folders,
    Models,
    NewTask,
    Settings,
    History,
}

enum class RelayConnectionState {
    Unpaired,
    Connecting,
    Live,
    Reconnecting,
    Offline,
    Revoked,
    UpdateRequired,
}

data class RelayState(
    val screen: Screen = Screen.Pairing,
    val connectionState: RelayConnectionState = RelayConnectionState.Unpaired,
    val connected: Boolean = false,
    val stale: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
    val tasks: List<RelayTask> = emptyList(),
    val approvals: List<RelayApproval> = emptyList(),
    val questions: List<RelayQuestion> = emptyList(),
    val models: List<RelayModel> = emptyList(),
    val folders: List<RelayFolder> = emptyList(),
    val history: List<ApprovalHistoryItem> = emptyList(),
    val selectedTask: RelayTask? = null,
    val selectedApproval: RelayApproval? = null,
    val selectedQuestion: RelayQuestion? = null,
    val selectedFolder: String = "",
    val selectedModel: String = "",
    val selectedEffort: String = "",
    val draftPrompt: String = "",
    val transcript: String = "",
    val lastEventId: Long = 0,
    val appliedEventCount: Int = 0,
    val snapshotRequired: Boolean = false,
    val snapshotEventId: Long = 0,
)

sealed interface RelayAction {
    data object Connected : RelayAction
    data object Disconnected : RelayAction
    data class Navigate(val screen: Screen) : RelayAction
    data class TasksLoaded(val tasks: List<RelayTask>) : RelayAction
    data class InboxLoaded(
        val approvals: List<RelayApproval>,
        val questions: List<RelayQuestion>,
    ) : RelayAction
    data class ApprovalResolved(val id: String) : RelayAction
    data class Failure(val message: String) : RelayAction
    data class ConnectionChanged(
        val connectionState: RelayConnectionState,
    ) : RelayAction
    data object ClearError : RelayAction
    data object Unpaired : RelayAction
}

fun reduce(state: RelayState, action: RelayAction): RelayState = when (action) {
    RelayAction.Connected -> state.copy(
        screen = if (state.screen == Screen.Pairing || state.screen == Screen.Offline) {
            Screen.Inbox
        } else {
            state.screen
        },
        connectionState = RelayConnectionState.Live,
        connected = true,
        stale = false,
        error = null,
    )
    RelayAction.Disconnected -> state.copy(
        screen = Screen.Offline,
        connectionState = RelayConnectionState.Offline,
        connected = false,
        stale = true,
    )
    is RelayAction.Navigate -> state.copy(screen = action.screen)
    is RelayAction.TasksLoaded -> state.copy(tasks = action.tasks, loading = false)
    is RelayAction.InboxLoaded -> state.copy(
        approvals = action.approvals,
        questions = action.questions,
        loading = false,
    )
    is RelayAction.ApprovalResolved -> state.copy(
        approvals = state.approvals.filterNot { it.id == action.id },
        selectedApproval = null,
        screen = Screen.Inbox,
    )
    is RelayAction.ConnectionChanged -> when (action.connectionState) {
        RelayConnectionState.Unpaired -> RelayState()
        RelayConnectionState.Connecting -> state.copy(
            connectionState = action.connectionState,
            connected = false,
        )
        RelayConnectionState.Live -> state.copy(
            screen = if (state.screen == Screen.Pairing || state.screen == Screen.Offline) {
                Screen.Inbox
            } else {
                state.screen
            },
            connectionState = action.connectionState,
            connected = true,
            stale = false,
            error = null,
        )
        RelayConnectionState.Reconnecting -> state.copy(
            connectionState = action.connectionState,
            connected = false,
            stale = true,
        )
        RelayConnectionState.Offline -> state.copy(
            screen = Screen.Offline,
            connectionState = action.connectionState,
            connected = false,
            stale = true,
        )
        RelayConnectionState.Revoked -> state.copy(
            screen = Screen.Pairing,
            connectionState = action.connectionState,
            connected = false,
            stale = true,
            error = "Pairing was revoked on the Mac",
        )
        RelayConnectionState.UpdateRequired -> state.copy(
            screen = Screen.Offline,
            connectionState = action.connectionState,
            connected = false,
            stale = true,
            error = "Relay must be updated before reconnecting",
        )
    }
    is RelayAction.Failure -> state.copy(error = action.message, loading = false)
    RelayAction.ClearError -> state.copy(error = null)
    RelayAction.Unpaired -> RelayState()
}
