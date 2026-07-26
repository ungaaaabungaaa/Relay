package dev.ungaaaabungaaa.relay.security

import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RelayCloudPairingCryptoTest {
    @Test
    fun approvedCredentialIsEncryptedForTheWatchAgreementKey() {
        val generator = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }
        val mac = generator.generateKeyPair()
        val watch = generator.generateKeyPair()
        val sessionNonce = ByteArray(32) { 6 }
        val root = RelayCloudCrypto.deriveRootKey(
            mac.private,
            watch.public,
            sessionNonce,
        )
        val credential = RelayCloudPairingCredential(
            accountId = "account-1",
            hostId = "host-1",
            deviceId = "watch-1",
            credential = "watch-secret",
            apiVersion = 1,
            minimumApiVersion = 1,
            maximumApiVersion = 1,
        )
        val envelope = RelayCloudPairingCrypto.seal(
            credential,
            requestId = "request-1",
            hostId = "host-1",
            rootKey = root,
            nonce = ByteArray(12) { 7 },
        )

        assertEquals(
            credential,
            RelayCloudPairingCrypto.open(
                envelope,
                requestId = "request-1",
                hostId = "host-1",
                rootKey = RelayCloudCrypto.deriveRootKey(
                    watch.private,
                    mac.public,
                    sessionNonce,
                ),
            ),
        )
        assertThrows(SecurityException::class.java) {
            RelayCloudPairingCrypto.open(
                envelope,
                requestId = "another-request",
                hostId = "host-1",
                rootKey = root,
            )
        }
    }

    @Test
    fun x963PublicKeysRoundTripWithoutChangingTheAgreement() {
        val generator = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }
        val pair = generator.generateKeyPair()
        val x963 = RelayP256.publicKeyX963(pair.public)
        val decoded = RelayP256.publicKeyFromX963(x963)

        assertArrayEquals(x963, RelayP256.publicKeyX963(decoded))
    }

    @Test
    fun pairingCompletionOpensTheSharedCrossPlatformVector() {
        val credential = RelayCloudPairingCrypto.open(
            RelayCloudPairingPayloadEnvelope(
                version = 1,
                nonce = "BwcHBwcHBwcHBwcH",
                ciphertext = "Ipns_AseincDozOvrOAShV5XcyT0IcNnsqx5_4ACyn1hheZdO2yVENqvqHewusDboJLNJrXksCO4QF2L4ULZIrO0xtPQeZir4ejLnlNgyks06MUKP96sllHjC0kg-fTFUR69DnmQGHBd2uOniuIBj7C4Tu6AvsVnfqTYcO6xXJx855wfqzOAhKkTq1GUsQywQ5spui_x5IOsMHC3maU24urmS2n5eMw",
            ),
            requestId = "request-1",
            hostId = "host-1",
            rootKey = ByteArray(32) { 9 },
        )

        assertEquals("watch-1", credential.deviceId)
        assertEquals("watch-secret", credential.credential)
    }
}
