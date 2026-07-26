package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.security.RelayCloudCrypto
import dev.ungaaaabungaaa.relay.security.RelayRoutingFields
import dev.ungaaaabungaaa.relay.security.RelaySequenceWindow
import dev.ungaaaabungaaa.relay.security.RelayTunnelEnvelope
import java.security.SecureRandom
import java.util.Base64
import org.json.JSONObject

data class RelayTunnelHTTPResponse(
    val status: Int,
    val headers: Map<String, String>,
    val body: String,
)

sealed interface RelayCloudIncoming {
    data class Response(
        val requestId: String,
        val response: RelayTunnelHTTPResponse,
    ) : RelayCloudIncoming

    data class Event(val body: JSONObject) : RelayCloudIncoming
}

class RelayCloudTunnelCodec(
    private val accountId: String,
    private val hostId: String,
    private val deviceId: String,
    private val rootKey: ByteArray,
    initialOutgoingSequence: Long = 0,
    initialHostSequence: Long = 0,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var outgoingSequence = initialOutgoingSequence
    private val hostReplay = RelaySequenceWindow(
        if (initialHostSequence > 0) mapOf(hostId to initialHostSequence) else emptyMap(),
    )

    val highestHostSequence: Long
        get() = hostReplay.snapshot()[hostId] ?: 0

    val currentOutgoingSequence: Long
        get() = outgoingSequence

    fun encryptRequest(
        requestId: String,
        method: String,
        path: String,
        headers: Map<String, String>,
        body: String,
        nonce: ByteArray = ByteArray(12).also(SecureRandom()::nextBytes),
    ): RelayTunnelEnvelope {
        require(path.startsWith("/v1/") && !path.startsWith("//"))
        outgoingSequence += 1
        val inner = JSONObject()
            .put("kind", "request")
            .put(
                "body",
                JSONObject()
                    .put("method", method.uppercase())
                    .put("path", path)
                    .put("headers", JSONObject(headers))
                    .put("body", body),
            )
            .toString()
            .toByteArray()
        return RelayCloudCrypto.encrypt(
            RelayRoutingFields(
                version = 1,
                messageId = requestId,
                accountId = accountId,
                hostId = hostId,
                senderId = deviceId,
                recipientId = hostId,
                sentAt = now(),
                sequence = outgoingSequence,
            ),
            inner,
            rootKey,
            nonce,
        )
    }

    fun encryptVoiceChunk(
        messageId: String,
        transferId: String,
        index: Int,
        totalChunks: Int,
        recordedAtMs: Long,
        durationMs: Long,
        path: String,
        headers: Map<String, String>,
        data: ByteArray,
        nonce: ByteArray = ByteArray(12).also(SecureRandom()::nextBytes),
    ): RelayTunnelEnvelope {
        require(transferId.length in 8..128)
        require(totalChunks in 1..16 && index in 0 until totalChunks)
        require(durationMs in 1..30_000 && recordedAtMs in 0..durationMs)
        require(path.startsWith("/v1/transcribe?durationMs="))
        require(data.isNotEmpty() && data.size <= 128 * 1024)
        outgoingSequence += 1
        val inner = JSONObject()
            .put("kind", "voice")
            .put(
                "body",
                JSONObject()
                    .put("transferId", transferId)
                    .put("index", index)
                    .put("totalChunks", totalChunks)
                    .put("recordedAtMs", recordedAtMs)
                    .put("durationMs", durationMs)
                    .put("method", "POST")
                    .put("path", path)
                    .put("headers", JSONObject(headers))
                    .put("data", Base64.getEncoder().encodeToString(data)),
            )
            .toString()
            .toByteArray()
        return RelayCloudCrypto.encrypt(
            RelayRoutingFields(
                version = 1,
                messageId = messageId,
                accountId = accountId,
                hostId = hostId,
                senderId = deviceId,
                recipientId = hostId,
                sentAt = now(),
                sequence = outgoingSequence,
            ),
            inner,
            rootKey,
            nonce,
        )
    }

    fun decryptResponse(
        envelope: RelayTunnelEnvelope,
        expectedRequestId: String,
    ): RelayTunnelHTTPResponse {
        val incoming = decryptIncoming(envelope)
        if (
            incoming !is RelayCloudIncoming.Response ||
            incoming.requestId != expectedRequestId
        ) {
            throw SecurityException("Relay response request mismatch")
        }
        return incoming.response
    }

    fun decryptIncoming(envelope: RelayTunnelEnvelope): RelayCloudIncoming {
        if (
            envelope.accountId != accountId ||
            envelope.hostId != hostId ||
            envelope.senderId != hostId ||
            envelope.recipientId != deviceId ||
            kotlin.math.abs(now() - envelope.sentAt) > 5 * 60_000
        ) {
            throw SecurityException("Relay response authentication failed")
        }
        val plaintext = RelayCloudCrypto.decrypt(envelope, rootKey)
        val inner = JSONObject(plaintext.decodeToString())
        val kind = inner.getString("kind")
        val body = inner.getJSONObject("body")
        val decoded = when (kind) {
            "response" -> {
                val headersObject = body.getJSONObject("headers")
                RelayCloudIncoming.Response(
                    requestId = body.getString("requestId"),
                    response = RelayTunnelHTTPResponse(
                        status = body.getInt("status"),
                        headers = headersObject.keys().asSequence()
                            .associateWith(headersObject::getString),
                        body = body.getString("body"),
                    ),
                )
            }
            "event" -> RelayCloudIncoming.Event(body)
            else -> throw SecurityException("Relay response authentication failed")
        }
        hostReplay.accept(hostId, envelope.sequence)
        return decoded
    }
}
