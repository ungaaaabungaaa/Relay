package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.security.RelayCloudCrypto
import dev.ungaaaabungaaa.relay.security.RelayRoutingFields
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RelayCloudTunnelCodecTest {
    @Test
    fun requestIsEncryptedAsTheExistingSignedHttpContract() {
        val rootKey = ByteArray(32) { 5 }
        val codec = RelayCloudTunnelCodec(
            accountId = "account-1",
            hostId = "host-1",
            deviceId = "watch-1",
            rootKey = rootKey,
            initialOutgoingSequence = 40,
            now = { 1_000 },
        )
        val envelope = codec.encryptRequest(
            requestId = "request-1",
            method = "POST",
            path = "/v1/tasks/task-1/stop",
            headers = mapOf(
                "x-relay-device" to "watch-1",
                "x-relay-signature" to "signature",
                "idempotency-key" to "idempotency-0001",
            ),
            body = """{"turnId":"turn-1"}""",
            nonce = ByteArray(12) { 3 },
        )
        val inner = JSONObject(
            RelayCloudCrypto.decrypt(envelope, rootKey).decodeToString(),
        )

        assertEquals(41, envelope.sequence)
        assertEquals("request", inner.getString("kind"))
        assertEquals("POST", inner.getJSONObject("body").getString("method"))
        assertEquals(
            "/v1/tasks/task-1/stop",
            inner.getJSONObject("body").getString("path"),
        )
        assertEquals(
            "signature",
            inner.getJSONObject("body").getJSONObject("headers")
                .getString("x-relay-signature"),
        )
    }

    @Test
    fun responseMustMatchARequestAndAdvanceTheHostReplayWindow() {
        val rootKey = ByteArray(32) { 5 }
        val codec = RelayCloudTunnelCodec(
            accountId = "account-1",
            hostId = "host-1",
            deviceId = "watch-1",
            rootKey = rootKey,
            initialHostSequence = 8,
            now = { 1_000 },
        )
        val response = RelayCloudCrypto.encrypt(
            RelayRoutingFields(
                1,
                "response-1",
                "account-1",
                "host-1",
                "host-1",
                "watch-1",
                1_000,
                9,
            ),
            """{"kind":"response","body":{"requestId":"request-1","status":200,"headers":{},"body":"{\"ok\":true}"}}"""
                .toByteArray(),
            rootKey,
            ByteArray(12) { 4 },
        )

        val decoded = codec.decryptResponse(response, "request-1")
        assertEquals(200, decoded.status)
        assertEquals("""{"ok":true}""", decoded.body)
        assertEquals(9, codec.highestHostSequence)
        assertThrows(SecurityException::class.java) {
            codec.decryptResponse(response, "request-1")
        }
    }
}
