package dev.ungaaaabungaaa.relay.security

import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.PrivateKey
import java.security.PublicKey
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class RelayRoutingFields(
    val version: Int,
    val messageId: String,
    val accountId: String,
    val hostId: String,
    val senderId: String,
    val recipientId: String,
    val sentAt: Long,
    val sequence: Long,
)

data class RelayTunnelEnvelope(
    val version: Int,
    val messageId: String,
    val accountId: String,
    val hostId: String,
    val senderId: String,
    val recipientId: String,
    val sentAt: Long,
    val sequence: Long,
    val nonce: String,
    val ciphertext: String,
) {
    fun routing() = RelayRoutingFields(
        version,
        messageId,
        accountId,
        hostId,
        senderId,
        recipientId,
        sentAt,
        sequence,
    )
}

object RelayCloudCrypto {
    private const val INFO = "relay-e2ee-v1"

    fun deriveRootKey(
        privateKey: PrivateKey,
        peerPublicKey: PublicKey,
        pairingSessionNonce: ByteArray,
    ): ByteArray {
        require(pairingSessionNonce.size >= 16)
        val agreement = KeyAgreement.getInstance("ECDH")
        agreement.init(privateKey)
        agreement.doPhase(peerPublicKey, true)
        val sharedSecret = agreement.generateSecret()
        val pseudorandomKey = hmac(pairingSessionNonce, sharedSecret)
        return hmac(
            pseudorandomKey,
            INFO.toByteArray(StandardCharsets.UTF_8) + byteArrayOf(1),
        ).copyOf(32)
    }

    fun encrypt(
        routing: RelayRoutingFields,
        plaintext: ByteArray,
        rootKey: ByteArray,
        nonce: ByteArray,
    ): RelayTunnelEnvelope {
        require(rootKey.size == 32)
        require(nonce.size == 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(rootKey, "AES"),
            GCMParameterSpec(128, nonce),
        )
        cipher.updateAAD(canonicalAAD(routing))
        return RelayTunnelEnvelope(
            routing.version,
            routing.messageId,
            routing.accountId,
            routing.hostId,
            routing.senderId,
            routing.recipientId,
            routing.sentAt,
            routing.sequence,
            Base64.getUrlEncoder().withoutPadding().encodeToString(nonce),
            Base64.getUrlEncoder().withoutPadding()
                .encodeToString(cipher.doFinal(plaintext)),
        )
    }

    fun decrypt(envelope: RelayTunnelEnvelope, rootKey: ByteArray): ByteArray {
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(rootKey, "AES"),
                GCMParameterSpec(
                    128,
                    Base64.getUrlDecoder().decode(envelope.nonce),
                ),
            )
            cipher.updateAAD(canonicalAAD(envelope.routing()))
            return cipher.doFinal(
                Base64.getUrlDecoder().decode(envelope.ciphertext),
            )
        } catch (_: Exception) {
            throw SecurityException("Relay envelope authentication failed")
        }
    }

    fun canonicalAAD(routing: RelayRoutingFields): ByteArray {
        require(routing.version == 1)
        require(routing.sequence > 0)
        val json = buildString {
            append("""{"version":${routing.version},"messageId":""")
            append(jsonString(routing.messageId))
            append(""","accountId":""")
            append(jsonString(routing.accountId))
            append(""","hostId":""")
            append(jsonString(routing.hostId))
            append(""","senderId":""")
            append(jsonString(routing.senderId))
            append(""","recipientId":""")
            append(jsonString(routing.recipientId))
            append(""","sentAt":${routing.sentAt},"sequence":${routing.sequence}}""")
        }
        return json.toByteArray(StandardCharsets.UTF_8)
    }

    private fun hmac(key: ByteArray, value: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(value)
    }

    private fun jsonString(value: String): String = buildString {
        for (character in value) {
            when (character) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> {
                    if (character.code < 0x20) {
                        append("\\u%04x".format(character.code))
                    } else {
                        append(character)
                    }
                }
            }
        }
    }
}

class RelaySequenceWindow(initial: Map<String, Long> = emptyMap()) {
    private val highest = initial.toMutableMap()

    fun accept(senderId: String, sequence: Long) {
        if (sequence <= (highest[senderId] ?: 0)) {
            throw SecurityException("Relay replay rejected")
        }
        highest[senderId] = sequence
    }

    fun snapshot(): Map<String, Long> = highest.toMap()
}
