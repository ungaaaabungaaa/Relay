package dev.ungaaaabungaaa.relay.security

import java.math.BigInteger
import java.nio.charset.StandardCharsets
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.PublicKey
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

data class RelayCloudPairingPayloadEnvelope(
    val version: Int,
    val nonce: String,
    val ciphertext: String,
)

data class RelayCloudPairingCredential(
    val accountId: String,
    val hostId: String,
    val deviceId: String,
    val credential: String,
    val apiVersion: Int,
    val minimumApiVersion: Int,
    val maximumApiVersion: Int,
)

object RelayCloudPairingCrypto {
    fun seal(
        credential: RelayCloudPairingCredential,
        requestId: String,
        hostId: String,
        rootKey: ByteArray,
        nonce: ByteArray = ByteArray(12).also(SecureRandom()::nextBytes),
    ): RelayCloudPairingPayloadEnvelope {
        require(rootKey.size == 32 && nonce.size == 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(rootKey, "AES"),
            GCMParameterSpec(128, nonce),
        )
        cipher.updateAAD(aad(requestId, hostId))
        val plaintext = JSONObject()
            .put("accountId", credential.accountId)
            .put("hostId", credential.hostId)
            .put("deviceId", credential.deviceId)
            .put("credential", credential.credential)
            .put("apiVersion", credential.apiVersion)
            .put("minimumApiVersion", credential.minimumApiVersion)
            .put("maximumApiVersion", credential.maximumApiVersion)
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
        return RelayCloudPairingPayloadEnvelope(
            version = 1,
            nonce = Base64.getUrlEncoder().withoutPadding().encodeToString(nonce),
            ciphertext = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(cipher.doFinal(plaintext)),
        )
    }

    fun open(
        envelope: RelayCloudPairingPayloadEnvelope,
        requestId: String,
        hostId: String,
        rootKey: ByteArray,
    ): RelayCloudPairingCredential {
        try {
            require(envelope.version == 1 && rootKey.size == 32)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(rootKey, "AES"),
                GCMParameterSpec(
                    128,
                    Base64.getUrlDecoder().decode(envelope.nonce),
                ),
            )
            cipher.updateAAD(aad(requestId, hostId))
            val body = JSONObject(
                cipher.doFinal(
                    Base64.getUrlDecoder().decode(envelope.ciphertext),
                ).decodeToString(),
            )
            return RelayCloudPairingCredential(
                accountId = body.getString("accountId"),
                hostId = body.getString("hostId"),
                deviceId = body.getString("deviceId"),
                credential = body.getString("credential"),
                apiVersion = body.getInt("apiVersion"),
                minimumApiVersion = body.getInt("minimumApiVersion"),
                maximumApiVersion = body.getInt("maximumApiVersion"),
            )
        } catch (_: Exception) {
            throw SecurityException("Relay pairing payload authentication failed")
        }
    }

    private fun aad(requestId: String, hostId: String): ByteArray =
        (
            "{\"version\":1,\"requestId\":${JSONObject.quote(requestId)}," +
                "\"hostId\":${JSONObject.quote(hostId)}}"
        ).toByteArray(StandardCharsets.UTF_8)
}

object RelayP256 {
    fun publicKeyX963(publicKey: PublicKey): ByteArray {
        val point = (publicKey as ECPublicKey).w
        return byteArrayOf(4) + fixed(point.affineX) + fixed(point.affineY)
    }

    fun publicKeyFromX963(encoded: ByteArray): PublicKey {
        require(encoded.size == 65 && encoded[0] == 4.toByte())
        val parameters = AlgorithmParameters.getInstance("EC").apply {
            init(ECGenParameterSpec("secp256r1"))
        }.getParameterSpec(ECParameterSpec::class.java)
        val point = ECPoint(
            BigInteger(1, encoded.copyOfRange(1, 33)),
            BigInteger(1, encoded.copyOfRange(33, 65)),
        )
        return KeyFactory.getInstance("EC").generatePublic(
            ECPublicKeySpec(point, parameters),
        )
    }

    private fun fixed(value: BigInteger): ByteArray {
        val bytes = value.toByteArray()
        return when {
            bytes.size == 32 -> bytes
            bytes.size > 32 -> bytes.copyOfRange(bytes.size - 32, bytes.size)
            else -> ByteArray(32 - bytes.size) + bytes
        }
    }
}
