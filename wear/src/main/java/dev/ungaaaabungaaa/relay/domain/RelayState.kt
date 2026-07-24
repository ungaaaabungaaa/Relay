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

data class RelayState(
    val screen: Screen = Screen.Pairing,
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
    data object ClearError : RelayAction
    data object Unpaired : RelayAction
}

fun reduce(state: RelayState, action: RelayAction): RelayState = when (action) {
    RelayAction.Connected -> state.copy(
        screen = Screen.Inbox,
        connected = true,
        stale = false,
        error = null,
    )
    RelayAction.Disconnected -> state.copy(
        screen = Screen.Offline,
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
    is RelayAction.Failure -> state.copy(error = action.message, loading = false)
    RelayAction.ClearError -> state.copy(error = null)
    RelayAction.Unpaired -> RelayState()
}
