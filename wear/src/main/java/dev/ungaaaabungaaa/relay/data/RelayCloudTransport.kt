package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.domain.RelayConnectionState
import dev.ungaaaabungaaa.relay.security.RelayTunnelEnvelope
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.min
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

class RelayCloudTransport(
    private val preferences: RelayPreferences,
    private val deviceStore: RelayCloudDeviceStore,
    private val client: OkHttpClient = OkHttpClient(),
    private val socketOrigin: String =
        "wss://api.relayforcodex.com/cloud/v1/connect/device",
) {
    private val requestMutex = Mutex()
    private val stateLock = Any()
    private val transportScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var socket: WebSocket? = null
    private var ready: CompletableDeferred<Unit>? = null
    private var codec: RelayCloudTunnelCodec? = null
    private var codecDeviceId: String? = null
    private var pendingRequestId: String? = null
    private var pendingResponse:
        kotlin.coroutines.Continuation<RelayTunnelHTTPResponse>? = null
    private var onEvent: ((RelayLiveEvent) -> Unit)? = null
    private var onConnectionChanged: ((RelayConnectionState) -> Unit)? = null
    private var reconnectAttempt = 0
    private var reconnectScheduled = false
    private var explicitlyClosed = false

    val isPaired: Boolean
        get() = deviceStore.load() != null

    fun startEvents(
        onEvent: (RelayLiveEvent) -> Unit,
        onConnectionChanged: (RelayConnectionState) -> Unit,
    ) {
        synchronized(stateLock) {
            this.onEvent = onEvent
            this.onConnectionChanged = onConnectionChanged
            explicitlyClosed = false
            reconnectAttempt = 0
        }
        onConnectionChanged(RelayConnectionState.Connecting)
        runCatching { ensureConnection() }
            .onSuccess { connection ->
                transportScope.launch {
                    runCatching { connection.await() }
                        .onSuccess {
                            val callback = synchronized(stateLock) {
                                if (socket == null) null
                                else this@RelayCloudTransport.onConnectionChanged
                            }
                            callback?.invoke(RelayConnectionState.Live)
                        }
                }
            }
            .onFailure { onConnectionChanged(RelayConnectionState.Unpaired) }
    }

    fun close() {
        val activeSocket: WebSocket?
        val pending: kotlin.coroutines.Continuation<RelayTunnelHTTPResponse>?
        synchronized(stateLock) {
            explicitlyClosed = true
            onEvent = null
            onConnectionChanged = null
            activeSocket = socket
            socket = null
            ready?.cancel()
            ready = null
            pending = pendingResponse
            pendingResponse = null
            pendingRequestId = null
        }
        activeSocket?.cancel()
        pending?.resumeWithException(
            IllegalStateException("Relay Cloud disconnected"),
        )
    }

    suspend fun request(
        method: String,
        path: String,
        headers: Map<String, String>,
        body: String,
    ): RelayTunnelHTTPResponse = requestMutex.withLock {
        withTimeout(15_000) {
            val connection = ensureConnection()
            connection.await()
            val requestId = UUID.randomUUID().toString()
            val envelope = synchronized(stateLock) {
                val activeCodec = codecForCurrentDevice()
                activeCodec.encryptRequest(
                    requestId = requestId,
                    method = method,
                    path = path,
                    headers = headers,
                    body = body,
                ).also {
                    preferences.cloudOutgoingSequence =
                        activeCodec.currentOutgoingSequence
                }
            }
            sendAndAwait(requestId, listOf(envelope))
        }
    }

    suspend fun voiceRequest(
        path: String,
        headers: Map<String, String>,
        audio: ByteArray,
        durationMs: Long,
    ): RelayTunnelHTTPResponse = requestMutex.withLock {
        require(audio.isNotEmpty() && audio.size <= 2 * 1024 * 1024)
        require(durationMs in 1..30_000)
        withTimeout(30_000) {
            val connection = ensureConnection()
            connection.await()
            val transferId = UUID.randomUUID().toString()
            val totalChunks = (audio.size + VOICE_CHUNK_BYTES - 1) /
                VOICE_CHUNK_BYTES
            val envelopes = synchronized(stateLock) {
                val activeCodec = codecForCurrentDevice()
                List(totalChunks) { index ->
                    val start = index * VOICE_CHUNK_BYTES
                    val end = min(audio.size, start + VOICE_CHUNK_BYTES)
                    val recordedAtMs = if (totalChunks == 1) {
                        durationMs
                    } else {
                        durationMs * index / (totalChunks - 1)
                    }
                    activeCodec.encryptVoiceChunk(
                        messageId = UUID.randomUUID().toString(),
                        transferId = transferId,
                        index = index,
                        totalChunks = totalChunks,
                        recordedAtMs = recordedAtMs,
                        durationMs = durationMs,
                        path = path,
                        headers = headers,
                        data = audio.copyOfRange(start, end),
                    )
                }.also {
                    preferences.cloudOutgoingSequence =
                        activeCodec.currentOutgoingSequence
                }
            }
            sendAndAwait(checkNotNull(envelopes.lastOrNull()).messageId, envelopes)
        }
    }

    private suspend fun sendAndAwait(
        requestId: String,
        envelopes: List<RelayTunnelEnvelope>,
    ): RelayTunnelHTTPResponse = suspendCancellableCoroutine { continuation ->
        val activeSocket = synchronized(stateLock) {
            pendingRequestId = requestId
            pendingResponse = continuation
            socket
        }
        val sent = activeSocket != null && envelopes.all { envelope ->
            activeSocket.send(envelope.toJson().toString())
        }
        if (!sent) {
            synchronized(stateLock) {
                if (pendingRequestId == requestId) {
                    pendingRequestId = null
                    pendingResponse = null
                }
            }
            continuation.resumeWithException(
                IllegalStateException("Relay Cloud is unavailable"),
            )
        }
        continuation.invokeOnCancellation {
            synchronized(stateLock) {
                if (pendingRequestId == requestId) {
                    pendingRequestId = null
                    pendingResponse = null
                }
            }
        }
    }

    private fun ensureConnection(): CompletableDeferred<Unit> =
        synchronized(stateLock) {
            val config = deviceStore.load() ?: error("Watch is not paired")
            explicitlyClosed = false
            ready?.let { existing ->
                if (socket != null) return@synchronized existing
            }
            codecFor(config)
            val connectionReady = CompletableDeferred<Unit>()
            ready = connectionReady
            val request = Request.Builder()
                .url(socketOrigin)
                .header("authorization", "Bearer ${config.credential}")
                .header("x-relay-device-id", config.deviceId)
                .header("cache-control", "no-store")
                .build()
            socket = client.newWebSocket(request, listener())
            connectionReady
        }

    private fun listener(): WebSocketListener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            val callback = synchronized(stateLock) {
                if (socket !== webSocket) return
                reconnectAttempt = 0
                ready?.complete(Unit)
                onConnectionChanged
            }
            callback?.invoke(RelayConnectionState.Live)
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val message = runCatching { JSONObject(text) }.getOrElse {
                webSocket.close(1003, "invalid message")
                return
            }
            if (message.optString("type") == "host_offline") {
                failPending(IllegalStateException("Mac is offline"))
                synchronized(stateLock) { onConnectionChanged }
                    ?.invoke(RelayConnectionState.Offline)
                return
            }
            val incoming = runCatching {
                synchronized(stateLock) {
                    if (socket !== webSocket) return
                    codecForCurrentDevice().decryptIncoming(
                        relayEnvelopeFromJson(message),
                    ).also {
                        preferences.cloudHostSequence =
                            codecForCurrentDevice().highestHostSequence
                    }
                }
            }.getOrElse {
                webSocket.close(1003, "invalid encrypted message")
                return
            }
            when (incoming) {
                is RelayCloudIncoming.Response -> {
                    val continuation = synchronized(stateLock) {
                        if (pendingRequestId != incoming.requestId) return
                        pendingRequestId = null
                        pendingResponse.also { pendingResponse = null }
                    }
                    continuation?.resume(incoming.response)
                }
                is RelayCloudIncoming.Event -> {
                    val event = runCatching {
                        parseLiveEvent(incoming.body.toString())
                    }.getOrElse {
                        webSocket.close(1003, "invalid event")
                        return
                    }
                    synchronized(stateLock) { onEvent }?.invoke(event)
                }
            }
        }

        override fun onFailure(
            webSocket: WebSocket,
            t: Throwable,
            response: Response?,
        ) {
            disconnected(
                webSocket,
                if (response?.code == 401 || response?.code == 403) {
                    SecurityException("Relay watch access was revoked")
                } else {
                    IllegalStateException("Relay Cloud is unavailable", t)
                },
                revoked = response?.code == 401 || response?.code == 403,
            )
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            disconnected(
                webSocket,
                if (code == 4003) {
                    SecurityException("Relay watch access was revoked")
                } else {
                    IllegalStateException("Relay Cloud disconnected")
                },
                revoked = code == 4003,
            )
        }
    }

    private fun disconnected(
        webSocket: WebSocket,
        error: Throwable,
        revoked: Boolean,
    ) {
        val callback = synchronized(stateLock) {
            if (socket !== webSocket) return
            socket = null
            ready?.completeExceptionally(error)
            ready = null
            onConnectionChanged
        }
        failPending(error)
        callback?.invoke(
            if (revoked) RelayConnectionState.Revoked
            else RelayConnectionState.Reconnecting,
        )
        if (!revoked) scheduleReconnect()
    }

    private fun failPending(error: Throwable) {
        val continuation = synchronized(stateLock) {
            pendingRequestId = null
            pendingResponse.also { pendingResponse = null }
        }
        continuation?.resumeWithException(error)
    }

    private fun scheduleReconnect() {
        val shouldSchedule = synchronized(stateLock) {
            if (
                explicitlyClosed ||
                onEvent == null ||
                reconnectScheduled
            ) {
                false
            } else {
                reconnectScheduled = true
                reconnectAttempt += 1
                true
            }
        }
        if (!shouldSchedule) return
        transportScope.launch {
            val attempt = synchronized(stateLock) { reconnectAttempt }
            delay(min(30_000L, 1_000L shl min(attempt - 1, 5)))
            synchronized(stateLock) { reconnectScheduled = false }
            runCatching { ensureConnection() }
                .onFailure { scheduleReconnect() }
        }
    }

    private fun codecForCurrentDevice(): RelayCloudTunnelCodec =
        codecFor(deviceStore.load() ?: error("Watch is not paired"))

    private fun codecFor(
        config: RelayCloudDeviceConfig,
    ): RelayCloudTunnelCodec {
        if (codec == null || codecDeviceId != config.deviceId) {
            codec = RelayCloudTunnelCodec(
                accountId = config.accountId,
                hostId = config.hostId,
                deviceId = config.deviceId,
                rootKey = config.rootKey,
                initialOutgoingSequence = preferences.cloudOutgoingSequence,
                initialHostSequence = preferences.cloudHostSequence,
            )
            codecDeviceId = config.deviceId
        }
        return checkNotNull(codec)
    }

    companion object {
        private const val VOICE_CHUNK_BYTES = 128 * 1024
    }
}

internal fun RelayTunnelEnvelope.toJson(): JSONObject = JSONObject()
    .put("version", version)
    .put("messageId", messageId)
    .put("accountId", accountId)
    .put("hostId", hostId)
    .put("senderId", senderId)
    .put("recipientId", recipientId)
    .put("sentAt", sentAt)
    .put("sequence", sequence)
    .put("nonce", nonce)
    .put("ciphertext", ciphertext)

internal fun relayEnvelopeFromJson(value: JSONObject) = RelayTunnelEnvelope(
    version = value.getInt("version"),
    messageId = value.getString("messageId"),
    accountId = value.getString("accountId"),
    hostId = value.getString("hostId"),
    senderId = value.getString("senderId"),
    recipientId = value.getString("recipientId"),
    sentAt = value.getLong("sentAt"),
    sequence = value.getLong("sequence"),
    nonce = value.getString("nonce"),
    ciphertext = value.getString("ciphertext"),
)
