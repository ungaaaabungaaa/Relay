package dev.ungaaaabungaaa.relay.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.ungaaaabungaaa.relay.data.RelayApi
import dev.ungaaaabungaaa.relay.data.RelayLiveEvent
import dev.ungaaaabungaaa.relay.data.RelayPreferences
import dev.ungaaaabungaaa.relay.data.RelaySocket
import dev.ungaaaabungaaa.relay.data.applyEvents
import dev.ungaaaabungaaa.relay.domain.ApprovalHistoryItem
import dev.ungaaaabungaaa.relay.domain.RelayAction
import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayConnectionState
import dev.ungaaaabungaaa.relay.domain.RelayState
import dev.ungaaaabungaaa.relay.domain.RelayTask
import dev.ungaaaabungaaa.relay.domain.Screen
import dev.ungaaaabungaaa.relay.domain.reduce
import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import kotlinx.coroutines.launch

class RelayViewModel(application: Application) : AndroidViewModel(application) {
    private val preferences = RelayPreferences(application)
    private val identity = DeviceIdentity()
    private val api = RelayApi(preferences, identity)

    var state by mutableStateOf(
        RelayState(
            screen = if (preferences.deviceId == null) Screen.Pairing else Screen.Offline,
            connectionState = if (preferences.deviceId == null) {
                RelayConnectionState.Unpaired
            } else {
                RelayConnectionState.Offline
            },
            lastEventId = preferences.lastEventId,
        ),
    )
        private set
    var pairingCode by mutableStateOf("")
    var bridgeUrl by mutableStateOf(preferences.bridgeUrl)
    var instruction by mutableStateOf("")

    private val socket by lazy {
        RelaySocket(
            preferences = preferences,
            identity = identity,
            scope = viewModelScope,
            onEvent = ::receiveLiveEvent,
            onConnectionChanged = { connectionState ->
                viewModelScope.launch {
                    dispatch(RelayAction.ConnectionChanged(connectionState))
                }
            },
        )
    }

    init {
        if (preferences.deviceId != null) {
            refresh(startLiveAfter = true)
        }
    }

    fun navigate(screen: Screen) {
        dispatch(RelayAction.Navigate(screen))
        when (screen) {
            Screen.Tasks -> loadTasks()
            Screen.Inbox -> refresh()
            else -> Unit
        }
    }

    fun pair() {
        viewModelScope.launch {
            runCatching {
                preferences.bridgeUrl = bridgeUrl
                api.pair(pairingCode)
            }.onSuccess {
                dispatch(RelayAction.Connected)
                refresh(startLiveAfter = true)
            }.onFailure { dispatch(RelayAction.Failure(it.message ?: "Pairing failed")) }
        }
    }

    fun refresh(
        silent: Boolean = false,
        startLiveAfter: Boolean = false,
    ) {
        viewModelScope.launch {
            if (!silent) state = state.copy(loading = true)
            runCatching {
                val inbox = api.inbox()
                val tasks = api.tasks()
                inbox to tasks
            }.onSuccess { (inbox, tasks) ->
                val needsSnapshot = state.snapshotRequired
                dispatch(RelayAction.Connected)
                dispatch(RelayAction.InboxLoaded(inbox.first, inbox.second))
                dispatch(RelayAction.TasksLoaded(tasks))
                if (needsSnapshot) {
                    val snapshotCursor = maxOf(state.lastEventId, state.snapshotEventId)
                    preferences.lastEventId = snapshotCursor
                    state = state.copy(
                        lastEventId = snapshotCursor,
                        snapshotRequired = false,
                        snapshotEventId = 0,
                    )
                }
                if (startLiveAfter || needsSnapshot) {
                    socket.start(preferences.lastEventId)
                }
            }.onFailure {
                if (!silent || state.connected) dispatch(RelayAction.Disconnected)
            }
        }
    }

    fun loadTasks() {
        viewModelScope.launch {
            runCatching { api.tasks() }
                .onSuccess { dispatch(RelayAction.TasksLoaded(it)) }
                .onFailure { dispatch(RelayAction.Failure(it.message ?: "Unable to load tasks")) }
        }
    }

    fun selectTask(task: RelayTask) {
        state = state.copy(selectedTask = task, screen = Screen.TaskDetail)
    }

    fun selectApproval(approval: RelayApproval) {
        state = state.copy(selectedApproval = approval, screen = Screen.Approval)
    }

    fun decide(approve: Boolean) {
        val approval = state.selectedApproval ?: return
        viewModelScope.launch {
            runCatching { api.decideApproval(approval.id, approve) }
                .onSuccess {
                    state = state.copy(
                        history = listOf(
                            ApprovalHistoryItem(
                                approval.id,
                                if (approve) "Approved" else "Denied",
                                approval.command ?: approval.kind,
                                System.currentTimeMillis(),
                            ),
                        ) + state.history,
                    )
                    dispatch(RelayAction.ApprovalResolved(approval.id))
                }
                .onFailure { dispatch(RelayAction.Failure(it.message ?: "Decision failed")) }
        }
    }

    fun sendInstruction() {
        val task = state.selectedTask ?: return
        val text = instruction.trim()
        if (text.isEmpty()) return
        viewModelScope.launch {
            runCatching { api.send(task.id, text) }
                .onSuccess { instruction = "" }
                .onFailure { dispatch(RelayAction.Failure(it.message ?: "Send failed")) }
        }
    }

    fun unpair() {
        socket.close()
        preferences.clear()
        identity.delete()
        dispatch(RelayAction.Unpaired)
    }

    fun clearError() = dispatch(RelayAction.ClearError)

    private fun dispatch(action: RelayAction) {
        state = reduce(state, action)
    }

    private fun receiveLiveEvent(event: RelayLiveEvent) {
        viewModelScope.launch {
            val previous = state
            val updated = applyEvents(previous, listOf(event))
            if (updated.lastEventId > previous.lastEventId) {
                preferences.lastEventId = updated.lastEventId
            }
            state = updated
            if (!previous.snapshotRequired && updated.snapshotRequired) {
                refresh(silent = true, startLiveAfter = true)
            }
        }
    }

    override fun onCleared() {
        socket.close()
        super.onCleared()
    }
}
