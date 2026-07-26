package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.security.RelayTunnelEnvelope
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
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

    val isPaired: Boolean
        get() = deviceStore.load() != null

    suspend fun request(
        method: String,
        path: String,
        headers: Map<String, String>,
        body: String,
    ): RelayTunnelHTTPResponse = requestMutex.withLock {
        withTimeout(15_000) {
            val config = deviceStore.load() ?: error("Watch is not paired")
            val requestId = UUID.randomUUID().toString()
            val codec = RelayCloudTunnelCodec(
                accountId = config.accountId,
                hostId = config.hostId,
                deviceId = config.deviceId,
                rootKey = config.rootKey,
                initialOutgoingSequence = preferences.cloudOutgoingSequence,
                initialHostSequence = preferences.cloudHostSequence,
            )
            val envelope = codec.encryptRequest(
                requestId = requestId,
                method = method,
                path = path,
                headers = headers,
                body = body,
            )
            preferences.cloudOutgoingSequence = codec.currentOutgoingSequence
            suspendCancellableCoroutine { continuation ->
                val finished = AtomicBoolean(false)
                lateinit var socket: WebSocket
                fun fail(error: Throwable) {
                    if (finished.compareAndSet(false, true)) {
                        continuation.resumeWithException(error)
                    }
                }
                socket = client.newWebSocket(
                    Request.Builder()
                        .url(socketOrigin)
                        .header("authorization", "Bearer ${config.credential}")
                        .header("x-relay-device-id", config.deviceId)
                        .header("cache-control", "no-store")
                        .build(),
                    object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            if (!webSocket.send(envelope.toJson().toString())) {
                                fail(IllegalStateException("Relay Cloud is unavailable"))
                            }
                        }

                        override fun onMessage(webSocket: WebSocket, text: String) {
                            runCatching {
                                val incoming = relayEnvelopeFromJson(JSONObject(text))
                                val decoded = codec.decryptResponse(incoming, requestId)
                                preferences.cloudHostSequence = codec.highestHostSequence
                                decoded
                            }.onSuccess { decoded ->
                                if (finished.compareAndSet(false, true)) {
                                    webSocket.close(1000, "request complete")
                                    continuation.resume(decoded)
                                }
                            }.onFailure(::fail)
                        }

                        override fun onFailure(
                            webSocket: WebSocket,
                            t: Throwable,
                            response: Response?,
                        ) {
                            fail(
                                if (response?.code == 401 || response?.code == 403) {
                                    SecurityException("Relay watch access was revoked")
                                } else {
                                    IllegalStateException("Relay Cloud is unavailable", t)
                                },
                            )
                        }

                        override fun onClosed(
                            webSocket: WebSocket,
                            code: Int,
                            reason: String,
                        ) {
                            fail(IllegalStateException("Relay Cloud disconnected"))
                        }
                    },
                )
                continuation.invokeOnCancellation { socket.cancel() }
            }
        }
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
