package dev.ungaaaabungaaa.relay.security

import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RelayCloudCryptoTest {
    @Test
    fun macAndWatchDeriveTheSameRootKey() {
        val generator = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }
        val mac = generator.generateKeyPair()
        val watch = generator.generateKeyPair()
        val salt = ByteArray(32) { 7 }

        assertArrayEquals(
            RelayCloudCrypto.deriveRootKey(mac.private, watch.public, salt),
            RelayCloudCrypto.deriveRootKey(watch.private, mac.public, salt),
        )
    }

    @Test
    fun authenticatedRoutingFieldsCannotBeModified() {
        val key = ByteArray(32) { 4 }
        val routing = RelayRoutingFields(
            version = 1,
            messageId = "message-1",
            accountId = "account-1",
            hostId = "host-1",
            senderId = "watch-1",
            recipientId = "host-1",
            sentAt = 1000,
            sequence = 1,
        )
        val envelope = RelayCloudCrypto.encrypt(
            routing = routing,
            plaintext = """{"kind":"request"}""".toByteArray(),
            rootKey = key,
            nonce = ByteArray(12) { 2 },
        )
        assertEquals(
            """{"kind":"request"}""",
            RelayCloudCrypto.decrypt(envelope, key).decodeToString(),
        )
        assertThrows(SecurityException::class.java) {
            RelayCloudCrypto.decrypt(
                envelope.copy(recipientId = "attacker"),
                key,
            )
        }
    }

    @Test
    fun replayStateSurvivesRecreation() {
        val first = RelaySequenceWindow(mapOf("watch-1" to 8))
        first.accept("watch-1", 9)
        val restored = RelaySequenceWindow(first.snapshot())

        assertThrows(SecurityException::class.java) {
            restored.accept("watch-1", 9)
        }
    }
}
