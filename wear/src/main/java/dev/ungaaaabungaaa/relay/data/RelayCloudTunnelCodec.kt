package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.security.RelayCloudCrypto
import dev.ungaaaabungaaa.relay.security.RelayRoutingFields
import dev.ungaaaabungaaa.relay.security.RelaySequenceWindow
import dev.ungaaaabungaaa.relay.security.RelayTunnelEnvelope
import java.security.SecureRandom
import org.json.JSONObject

data class RelayTunnelHTTPResponse(
    val status: Int,
    val headers: Map<String, String>,
    val body: String,
)

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

    fun decryptResponse(
        envelope: RelayTunnelEnvelope,
        expectedRequestId: String,
    ): RelayTunnelHTTPResponse {
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
        if (inner.getString("kind") != "response") {
            throw SecurityException("Relay response authentication failed")
        }
        val response = inner.getJSONObject("body")
        if (response.getString("requestId") != expectedRequestId) {
            throw SecurityException("Relay response request mismatch")
        }
        hostReplay.accept(hostId, envelope.sequence)
        val headersObject = response.getJSONObject("headers")
        val headers = headersObject.keys().asSequence()
            .associateWith(headersObject::getString)
        return RelayTunnelHTTPResponse(
            status = response.getInt("status"),
            headers = headers,
            body = response.getString("body"),
        )
    }
}
