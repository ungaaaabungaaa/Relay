package dev.ungaaaabungaaa.relay.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec

class RelayAgreementIdentity(context: Context) {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val secureStore = RelaySecureStore(context)

    fun privateKey(): PrivateKey = if (Build.VERSION.SDK_INT >= 31) {
        ensureKeystorePair()
        keyStore.getKey(KEY_ALIAS, null) as PrivateKey
    } else {
        fallbackPair().private
    }

    fun publicKey(): PublicKey = if (Build.VERSION.SDK_INT >= 31) {
        ensureKeystorePair()
        keyStore.getCertificate(KEY_ALIAS).publicKey
    } else {
        fallbackPair().public
    }

    fun publicKeyX963(): ByteArray = RelayP256.publicKeyX963(publicKey())

    fun delete() {
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
        secureStore.remove(FALLBACK_PRIVATE)
        secureStore.remove(FALLBACK_PUBLIC)
    }

    private fun ensureKeystorePair() {
        if (keyStore.containsAlias(KEY_ALIAS)) return
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            "AndroidKeyStore",
        )
        generator.initialize(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_AGREE_KEY,
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setUserAuthenticationRequired(false)
                .build(),
        )
        generator.generateKeyPair()
    }

    private fun fallbackPair(): KeyPair {
        val factory = KeyFactory.getInstance("EC")
        val storedPrivate = secureStore.get(FALLBACK_PRIVATE)
        val storedPublic = secureStore.get(FALLBACK_PUBLIC)
        if (storedPrivate != null && storedPublic != null) {
            return KeyPair(
                factory.generatePublic(X509EncodedKeySpec(storedPublic)),
                factory.generatePrivate(PKCS8EncodedKeySpec(storedPrivate)),
            )
        }
        val pair = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()
        secureStore.put(FALLBACK_PRIVATE, pair.private.encoded)
        secureStore.put(FALLBACK_PUBLIC, pair.public.encoded)
        return pair
    }

    companion object {
        private const val KEY_ALIAS = "relay-watch-agreement-key-v1"
        private const val FALLBACK_PRIVATE = "agreement_private_pkcs8"
        private const val FALLBACK_PUBLIC = "agreement_public_x509"
    }
}
