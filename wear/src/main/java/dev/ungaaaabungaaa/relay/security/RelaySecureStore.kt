package dev.ungaaaabungaaa.relay.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class RelaySecureStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        "relay_secure",
        Context.MODE_PRIVATE,
    )
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun put(name: String, plaintext: ByteArray) {
        val nonce = ByteArray(12).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            encryptionKey(),
            GCMParameterSpec(128, nonce),
        )
        cipher.updateAAD(name.toByteArray())
        val encoded = Base64.getEncoder().encodeToString(
            nonce + cipher.doFinal(plaintext),
        )
        preferences.edit().putString(name, encoded).apply()
    }

    fun get(name: String): ByteArray? {
        val encoded = preferences.getString(name, null) ?: return null
        return try {
            val combined = Base64.getDecoder().decode(encoded)
            require(combined.size > 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                encryptionKey(),
                GCMParameterSpec(128, combined.copyOfRange(0, 12)),
            )
            cipher.updateAAD(name.toByteArray())
            cipher.doFinal(combined.copyOfRange(12, combined.size))
        } catch (_: Exception) {
            null
        }
    }

    fun remove(name: String) {
        preferences.edit().remove(name).apply()
    }

    private fun encryptionKey(): SecretKey {
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val KEY_ALIAS = "relay-watch-storage-key-v1"
    }
}
