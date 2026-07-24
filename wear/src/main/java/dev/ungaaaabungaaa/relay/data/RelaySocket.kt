package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayConnectionState
import dev.ungaaaabungaaa.relay.domain.RelayQuestion
import dev.ungaaaabungaaa.relay.domain.RelayState
import dev.ungaaaabungaaa.relay.domain.parseApprovalRisk
import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import dev.ungaaaabungaaa.relay.security.canonicalRequest
import java.util.UUID
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject

sealed interface RelayLiveEvent {
    data class ApprovalRequested(
        val sequence: Long,
        val approval: RelayApproval,
    ) : RelayLiveEvent

    data class QuestionRequested(
        val sequence: Long,
        val question: RelayQuestion,
    ) : RelayLiveEvent

    data class TaskChanged(
        val sequence: Long,
        val threadId: String?,
    ) : RelayLiveEvent

    data class Ignored(
        val sequence: Long,
        val type: String,
    ) : RelayLiveEvent

    data class SnapshotRequired(
        val latestEventId: Long,
    ) : RelayLiveEvent
}

fun applyEvents(
    initial: RelayState,
    events: List<RelayLiveEvent>,
): RelayState = events.fold(initial, ::applyEvent)

private fun applyEvent(
    state: RelayState,
    event: RelayLiveEvent,
): RelayState {
    if (event is RelayLiveEvent.SnapshotRequired) {
        return state.copy(
            snapshotRequired = true,
            snapshotEventId = maxOf(state.snapshotEventId, event.latestEventId),
        )
    }

    val sequence = when (event) {
        is RelayLiveEvent.ApprovalRequested -> event.sequence
        is RelayLiveEvent.QuestionRequested -> event.sequence
        is RelayLiveEvent.TaskChanged -> event.sequence
        is RelayLiveEvent.Ignored -> event.sequence
        is RelayLiveEvent.SnapshotRequired -> error("handled above")
    }
    if (sequence <= state.lastEventId) return state
    if (state.lastEventId > 0 && sequence != state.lastEventId + 1) {
        return state.copy(
            snapshotRequired = true,
            snapshotEventId = maxOf(state.snapshotEventId, sequence),
        )
    }

    val accepted = when (event) {
        is RelayLiveEvent.ApprovalRequested -> state.copy(
            approvals = listOf(event.approval) +
                state.approvals.filterNot { it.id == event.approval.id },
        )
        is RelayLiveEvent.QuestionRequested -> state.copy(
            questions = listOf(event.question) +
                state.questions.filterNot { it.id == event.question.id },
        )
        is RelayLiveEvent.TaskChanged -> state.copy(snapshotRequired = true)
        is RelayLiveEvent.Ignored -> state
        is RelayLiveEvent.SnapshotRequired -> error("handled above")
    }
    return accepted.copy(
        lastEventId = sequence,
        appliedEventCount = state.appliedEventCount + 1,
    )
}

class RelaySocket(
    private val preferences: RelayPreferences,
    private val identity: DeviceIdentity,
    private val scope: CoroutineScope,
    private val client: OkHttpClient = OkHttpClient(),
    private val onEvent: (RelayLiveEvent) -> Unit,
    private val onConnectionChanged: (RelayConnectionState) -> Unit,
) {
    private var socket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var generation = 0L
    private var reconnectAttempt = 0
    private var stopped = true

    fun start(after: Long) {
        generation += 1
        stopped = false
        reconnectAttempt = 0
        reconnectJob?.cancel()
        reconnectJob = null
        socket?.cancel()
        socket = null
        onConnectionChanged(RelayConnectionState.Connecting)
        connect(generation, after)
    }

    fun close() {
        generation += 1
        stopped = true
        reconnectJob?.cancel()
        reconnectJob = null
        socket?.close(1000, "watch closed")
        socket = null
    }

    private fun connect(connectionGeneration: Long, after: Long) {
        if (stopped || connectionGeneration != generation) return
        val deviceId = preferences.deviceId
        if (deviceId == null) {
            stopped = true
            onConnectionChanged(RelayConnectionState.Unpaired)
            return
        }
        val path = "/v1/events?after=$after"
        val timestamp = System.currentTimeMillis()
        val nonce = UUID.randomUUID().toString()
        val canonical = canonicalRequest(
            deviceId = deviceId,
            method = "GET",
            path = path,
            body = ByteArray(0),
            timestamp = timestamp,
            nonce = nonce,
        )
        val request = Request.Builder()
            .url("${preferences.bridgeUrl}$path")
            .header("x-relay-device", deviceId)
            .header("x-relay-timestamp", timestamp.toString())
            .header("x-relay-nonce", nonce)
            .header("x-relay-signature", identity.sign(canonical))
            .build()

        socket = client.newWebSocket(
            request,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    if (!isCurrent(connectionGeneration, webSocket)) {
                        webSocket.cancel()
                        return
                    }
                    reconnectAttempt = 0
                    onConnectionChanged(RelayConnectionState.Live)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (!isCurrent(connectionGeneration, webSocket)) return
                    runCatching { parseLiveEvent(text) }
                        .onSuccess(onEvent)
                        .onFailure {
                            webSocket.close(1003, "invalid event")
                        }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (isCurrent(connectionGeneration, webSocket)) {
                        scheduleReconnect(connectionGeneration)
                    }
                }

                override fun onFailure(
                    webSocket: WebSocket,
                    t: Throwable,
                    response: Response?,
                ) {
                    if (!isCurrent(connectionGeneration, webSocket)) return
                    when (response?.code) {
                        401, 403 -> {
                            stopped = true
                            onConnectionChanged(RelayConnectionState.Revoked)
                        }
                        426 -> {
                            stopped = true
                            onConnectionChanged(RelayConnectionState.UpdateRequired)
                        }
                        else -> scheduleReconnect(connectionGeneration)
                    }
                }
            },
        )
    }

    private fun scheduleReconnect(connectionGeneration: Long) {
        if (stopped || connectionGeneration != generation || reconnectJob?.isActive == true) {
            return
        }
        reconnectAttempt += 1
        onConnectionChanged(RelayConnectionState.Reconnecting)
        val delayMs = min(30_000L, 1_000L shl min(reconnectAttempt - 1, 5))
        reconnectJob = scope.launch {
            delay(delayMs)
            reconnectJob = null
            connect(connectionGeneration, preferences.lastEventId)
        }
    }

    private fun isCurrent(
        connectionGeneration: Long,
        webSocket: WebSocket,
    ): Boolean = !stopped && connectionGeneration == generation && socket === webSocket
}

internal fun parseLiveEvent(text: String): RelayLiveEvent {
    val message = JSONObject(text)
    if (message.getString("type") == "snapshot.required") {
        return RelayLiveEvent.SnapshotRequired(
            latestEventId = message.getLong("latestEventId"),
        )
    }

    val sequence = message.getLong("id")
    val type = message.getString("type")
    val data = message.optJSONObject("data") ?: JSONObject()
    return when (type) {
        "approval.requested" -> RelayLiveEvent.ApprovalRequested(
            sequence,
            parseApproval(data),
        )
        "question.requested" -> RelayLiveEvent.QuestionRequested(
            sequence,
            parseQuestion(data),
        )
        else -> if (
            type == "task.updated" ||
            type.startsWith("thread/") ||
            type.startsWith("turn/")
        ) {
            RelayLiveEvent.TaskChanged(
                sequence,
                data.optString("threadId").takeIf(String::isNotBlank),
            )
        } else {
            RelayLiveEvent.Ignored(sequence, type)
        }
    }
}

private fun parseApproval(data: JSONObject): RelayApproval = RelayApproval(
    id = data.getString("id"),
    threadId = data.getString("threadId"),
    kind = data.getString("kind"),
    risk = parseApprovalRisk(data.optString("risk").takeIf(String::isNotBlank)),
    riskReasons = data.optJSONArray("riskReasons")?.mapStrings() ?: emptyList(),
    command = data.optionalString("command"),
    cwd = data.optionalString("cwd"),
    reason = data.optionalString("reason"),
)

private fun parseQuestion(data: JSONObject): RelayQuestion {
    val first = data.getJSONArray("questions").getJSONObject(0)
    return RelayQuestion(
        id = data.getString("id"),
        threadId = data.getString("threadId"),
        prompt = first.getString("question"),
        options = first.optJSONArray("options")?.mapObjects {
            it.getString("label")
        } ?: emptyList(),
        questionId = first.getString("id"),
    )
}

private fun JSONObject.optionalString(name: String): String? =
    optString(name).takeIf { it.isNotBlank() && it != "null" }

private fun JSONArray.mapStrings(): List<String> =
    List(length()) { index -> getString(index) }

private inline fun <T> JSONArray.mapObjects(block: (JSONObject) -> T): List<T> =
    List(length()) { index -> block(getJSONObject(index)) }
