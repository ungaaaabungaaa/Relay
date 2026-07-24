package dev.ungaaaabungaaa.relay.security

import org.junit.Assert.assertEquals
import org.junit.Test

class RequestSignerTest {
    @Test
    fun canonicalRequestMatchesBridgeFormat() {
        assertEquals(
            "watch\nGET\n/v1/tasks\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n42\nnonce-1234567890",
            canonicalRequest(
                deviceId = "watch",
                method = "get",
                path = "/v1/tasks",
                body = ByteArray(0),
                timestamp = 42,
                nonce = "nonce-1234567890",
            ),
        )
    }
}
