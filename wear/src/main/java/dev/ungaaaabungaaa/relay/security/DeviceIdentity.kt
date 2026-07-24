package dev.ungaaaabungaaa.relay.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec

class DeviceIdentity {
    private val alias = "relay-watch-signing-key"
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun ensureKey() {
        if (keyStore.containsAlias(alias)) return
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            "AndroidKeyStore",
        )
        generator.initialize(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKeyPair()
    }

    fun publicKeyPem(): String {
        ensureKey()
        val encoded = keyStore.getCertificate(alias).publicKey.encoded
        val base64 = Base64.encodeToString(encoded, Base64.NO_WRAP)
        return "-----BEGIN PUBLIC KEY-----\n" +
            base64.chunked(64).joinToString("\n") +
            "\n-----END PUBLIC KEY-----\n"
    }

    fun sign(value: String): String {
        ensureKey()
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(keyStore.getKey(alias, null) as java.security.PrivateKey)
        signature.update(value.toByteArray())
        return Base64.encodeToString(signature.sign(), Base64.NO_WRAP)
    }

    fun delete() {
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
    }
}
