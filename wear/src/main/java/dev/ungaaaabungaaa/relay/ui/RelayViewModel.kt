package dev.ungaaaabungaaa.relay.ui

import android.app.Application
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.ungaaaabungaaa.relay.audio.VoiceClip
import dev.ungaaaabungaaa.relay.audio.VoiceRecorder
import dev.ungaaaabungaaa.relay.audio.consume
import dev.ungaaaabungaaa.relay.background.LiveMonitoringService
import dev.ungaaaabungaaa.relay.background.RelayRefreshWorker
import dev.ungaaaabungaaa.relay.data.RelayApi
import dev.ungaaaabungaaa.relay.data.RelayLiveEvent
import dev.ungaaaabungaaa.relay.data.RelayPreferences
import dev.ungaaaabungaaa.relay.data.RelaySocket
import dev.ungaaaabungaaa.relay.data.applyEvents
import dev.ungaaaabungaaa.relay.domain.ApprovalHistoryItem
import dev.ungaaaabungaaa.relay.domain.NewTaskDraft
import dev.ungaaaabungaaa.relay.domain.RelayAction
import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayConnectionState
import dev.ungaaaabungaaa.relay.domain.RelayFolder
import dev.ungaaaabungaaa.relay.domain.RelayModel
import dev.ungaaaabungaaa.relay.domain.RelayQuestion
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
            screen = if (preferences.deviceId == null) Screen.PairingCode else Screen.Offline,
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
    var questionAnswer by mutableStateOf("")
    var questionReviewing by mutableStateOf(false)
    var recordingVoice by mutableStateOf(false)
        private set
    var transcribingVoice by mutableStateOf(false)
        private set
    var liveMonitoringEnabled by mutableStateOf(preferences.liveMonitoringEnabled)
        private set

    private val socket by lazy {
        RelaySocket(
            preferences = preferences,
            identity = identity,
            scope = viewModelScope,
            onEvent = ::receiveLiveEvent,
            onConnectionChanged = { connectionState ->
                viewModelScope.launch {
                    dispatch(RelayAction.ConnectionChanged(connectionState))
                    if (connectionState == RelayConnectionState.Revoked) {
                        stopLiveMonitoring()
                    }
                }
            },
        )
    }
    private val voiceRecorder by lazy {
        VoiceRecorder.forContext(application) { clip ->
            recordingVoice = false
            transcribeVoiceClip(clip)
        }
    }

    init {
        if (preferences.deviceId != null) {
            refresh(startLiveAfter = true)
            if (!liveMonitoringEnabled) {
                RelayRefreshWorker.schedule(application)
            }
        }
    }

    fun navigate(screen: Screen) {
        dispatch(RelayAction.Navigate(screen))
        when (screen) {
            Screen.Tasks -> loadTasks()
            Screen.Inbox -> refresh()
            Screen.Workspaces -> loadFolderEntries("", Screen.Workspaces)
            Screen.Models -> loadModels()
            else -> Unit
        }
    }

    fun pair() {
        dispatch(RelayAction.Navigate(Screen.Connecting))
        viewModelScope.launch {
            runCatching {
                preferences.bridgeUrl = bridgeUrl
                api.pair(pairingCode)
            }.onSuccess {
                dispatch(RelayAction.Connected)
                refresh(startLiveAfter = true)
            }.onFailure {
                state = state.copy(screen = Screen.PairingCode)
                dispatch(RelayAction.Failure(it.message ?: "Pairing failed"))
            }
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
                if (startLiveAfter && preferences.liveMonitoringEnabled) {
                    startLiveMonitoring()
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

    fun selectQuestion(question: RelayQuestion) {
        questionAnswer = ""
        questionReviewing = false
        state = state.copy(selectedQuestion = question, screen = Screen.Question)
    }

    fun decide(approve: Boolean) {
        if (!state.connected || state.stale) return
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

    fun answerQuestion(answers: List<String>) {
        if (!state.connected || state.stale) return
        val question = state.selectedQuestion ?: return
        viewModelScope.launch {
            runCatching {
                api.answerQuestion(question.id, question.questionId, answers)
            }.onSuccess {
                questionAnswer = ""
                questionReviewing = false
                state = state.copy(
                    questions = state.questions.filterNot { it.id == question.id },
                    selectedQuestion = null,
                    screen = Screen.Inbox,
                )
            }.onFailure {
                dispatch(RelayAction.Failure(it.message ?: "Unable to answer question"))
            }
        }
    }

    fun reviewQuestion(answer: String) {
        questionAnswer = answer
        questionReviewing = answer.isNotBlank()
    }

    fun editQuestionAnswer() {
        questionReviewing = false
    }

    fun sendInstruction() {
        if (!state.connected || state.stale) return
        val task = state.selectedTask ?: return
        val text = instruction.trim()
        if (text.isEmpty()) return
        viewModelScope.launch {
            runCatching { api.send(task.id, text) }
                .onSuccess {
                    instruction = ""
                    state = state.copy(screen = Screen.TaskDetail)
                }
                .onFailure { dispatch(RelayAction.Failure(it.message ?: "Send failed")) }
        }
    }

    fun startVoiceRecording() {
        if (!state.connected || state.stale || recordingVoice) return
        runCatching {
            voiceRecorder.start()
            recordingVoice = true
        }.onFailure {
            dispatch(RelayAction.Failure(it.message ?: "Unable to start recording"))
        }
    }

    fun stopVoiceRecording() {
        if (!recordingVoice) return
        runCatching { voiceRecorder.stop() }
            .onSuccess { clip ->
                recordingVoice = false
                transcribeVoiceClip(clip)
            }
            .onFailure {
                recordingVoice = false
                dispatch(RelayAction.Failure(it.message ?: "Unable to finish recording"))
            }
    }

    fun cancelVoiceRecording() {
        if (!recordingVoice) return
        voiceRecorder.cancel()
        recordingVoice = false
        state = state.copy(screen = Screen.Instruction)
    }

    fun microphonePermissionDenied() {
        dispatch(RelayAction.Failure("Microphone permission is needed only for custom recording"))
    }

    fun notificationPermissionDenied() {
        dispatch(RelayAction.Failure("Notifications are required while live monitoring is active"))
    }

    fun sendTranscript() {
        if (!state.connected || state.stale) return
        val task = state.selectedTask ?: return
        val transcript = state.transcript.trim()
        if (transcript.isBlank()) return
        viewModelScope.launch {
            runCatching { api.send(task.id, transcript) }
                .onSuccess {
                    state = state.copy(
                        transcript = "",
                        screen = Screen.TaskDetail,
                    )
                }
                .onFailure {
                    dispatch(RelayAction.Failure(it.message ?: "Unable to send transcript"))
                }
        }
    }

    fun rerecordVoice() {
        state = state.copy(transcript = "", screen = Screen.VoiceRecord)
    }

    fun cancelTranscript() {
        state = state.copy(transcript = "", screen = Screen.Instruction)
    }

    fun startLiveMonitoring() {
        if (preferences.deviceId == null || !state.connected || state.stale) return
        preferences.liveMonitoringEnabled = true
        liveMonitoringEnabled = true
        val app = getApplication<Application>()
        app.startForegroundService(
            Intent(app, LiveMonitoringService::class.java)
                .setAction(LiveMonitoringService.ACTION_START),
        )
    }

    fun stopLiveMonitoring() {
        preferences.liveMonitoringEnabled = false
        liveMonitoringEnabled = false
        val app = getApplication<Application>()
        app.startService(
            Intent(app, LiveMonitoringService::class.java)
                .setAction(LiveMonitoringService.ACTION_STOP),
        )
        RelayRefreshWorker.schedule(app)
    }

    fun beginNewTask() {
        state = state.copy(
            newTaskDraft = NewTaskDraft(),
            screen = Screen.Workspaces,
        )
        loadFolderEntries("", Screen.Workspaces)
    }

    fun selectWorkspace(folder: RelayFolder) {
        state = state.copy(
            newTaskDraft = state.newTaskDraft.copy(folder = folder.path),
        )
        loadFolderEntries(folder.path, Screen.Folders)
    }

    fun openFolder(folder: RelayFolder) {
        state = state.copy(
            newTaskDraft = state.newTaskDraft.copy(folder = folder.path),
        )
        loadFolderEntries(folder.path, Screen.Folders)
    }

    fun useSelectedFolder() {
        loadModels()
    }

    fun selectModel(model: RelayModel) {
        state = state.copy(
            newTaskDraft = state.newTaskDraft.copy(
                modelId = model.id,
                modelName = model.name,
                effort = model.defaultEffort,
            ),
            screen = Screen.Effort,
        )
    }

    fun selectEffort(effort: String) {
        state = state.copy(
            newTaskDraft = state.newTaskDraft.copy(effort = effort),
            screen = Screen.Permissions,
        )
    }

    fun selectPermissionProfile(profile: String) {
        state = state.copy(
            newTaskDraft = state.newTaskDraft.copy(permissionProfile = profile),
            screen = Screen.Prompt,
        )
    }

    fun updateDraftPrompt(prompt: String) {
        state = state.copy(
            newTaskDraft = state.newTaskDraft.copy(prompt = prompt),
        )
    }

    fun reviewNewTask() {
        if (state.newTaskDraft.prompt.isNotBlank()) {
            state = state.copy(screen = Screen.NewTaskReview)
        }
    }

    fun startNewTask() {
        val draft = state.newTaskDraft
        if (!state.connected || state.stale || draft.prompt.isBlank()) return
        viewModelScope.launch {
            state = state.copy(loading = true)
            runCatching {
                api.startTask(
                    draft.folder,
                    draft.modelId,
                    draft.effort,
                    draft.prompt.trim(),
                )
            }.onSuccess {
                state = state.copy(
                    loading = false,
                    newTaskDraft = NewTaskDraft(),
                    screen = Screen.Tasks,
                )
                loadTasks()
            }.onFailure {
                dispatch(RelayAction.Failure(it.message ?: "Unable to start task"))
            }
        }
    }

    fun unpair() {
        stopLiveMonitoring()
        voiceRecorder.cancel()
        recordingVoice = false
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

    private fun loadFolderEntries(path: String, destination: Screen) {
        viewModelScope.launch {
            state = state.copy(loading = true, screen = destination)
            runCatching { api.folders(path) }
                .onSuccess { folders ->
                    state = state.copy(folders = folders, loading = false)
                }
                .onFailure {
                    dispatch(RelayAction.Failure(it.message ?: "Unable to load folders"))
                }
        }
    }

    private fun loadModels() {
        viewModelScope.launch {
            state = state.copy(loading = true, screen = Screen.Models)
            runCatching { api.models() }
                .onSuccess { models ->
                    state = state.copy(models = models, loading = false)
                }
                .onFailure {
                    dispatch(RelayAction.Failure(it.message ?: "Unable to load models"))
                }
        }
    }

    private fun transcribeVoiceClip(clip: VoiceClip) {
        viewModelScope.launch {
            transcribingVoice = true
            runCatching {
                clip.consume {
                    api.transcribe(it.file, it.durationMs)
                }
            }.onSuccess { transcript ->
                transcribingVoice = false
                state = state.copy(
                    transcript = transcript,
                    screen = Screen.TranscriptReview,
                )
            }.onFailure {
                transcribingVoice = false
                state = state.copy(screen = Screen.VoiceRecord)
                dispatch(RelayAction.Failure(it.message ?: "Transcription failed"))
            }
        }
    }

    override fun onCleared() {
        voiceRecorder.cancel()
        socket.close()
        super.onCleared()
    }
}
