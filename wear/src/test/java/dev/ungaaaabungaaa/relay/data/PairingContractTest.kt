package dev.ungaaaabungaaa.relay.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingContractTest {
    @Test
    fun bonjourRecordAcceptsOnlyHttpsApiOneAndA128BitToken() {
        val token = "0123456789abcdef0123456789abcdef"
        val record = PairingDiscoveryRecord.fromTxtAttributes(
            mapOf(
                "origin" to "https://relay.example.ts.net".toByteArray(),
                "token" to token.toByteArray(),
                "api" to "1".toByteArray(),
            ),
        )

        assertEquals(
            PairingDiscoveryRecord(
                origin = "https://relay.example.ts.net",
                discoveryToken = token,
                apiVersion = 1,
            ),
            record,
        )
        assertNull(
            PairingDiscoveryRecord.fromTxtAttributes(
                mapOf(
                    "origin" to "http://192.168.1.2:43117".toByteArray(),
                    "token" to token.toByteArray(),
                    "api" to "1".toByteArray(),
                ),
            ),
        )
    }

    @Test
    fun deviceMetadataUsesDetectedWatchDetailsWithoutGalaxyBranding() {
        val metadata = PairingDeviceMetadata.detected(
            manufacturer = "Google",
            model = "Pixel Watch 2",
            osVersion = "4",
            appVersion = "0.2.0-beta.1",
            isRound = true,
        )

        assertEquals("Google Pixel Watch 2", metadata.displayName)
        assertEquals("round", metadata.screenShape)
        assertEquals("wear-os", metadata.asMap()["platform"])
        assertTrue(!metadata.asMap().values.contains("Galaxy Watch6"))
    }

    @Test
    fun pairingPathsNeverExposeTheDiscoveryTokenOutsideItsScopedRoute() {
        val token = "0123456789abcdef0123456789abcdef"

        assertEquals("/v1/pairing-sessions/$token", PairingContract.sessionPath(token))
        assertEquals(
            "/v1/pairing-sessions/$token/status",
            PairingContract.statusPath(token),
        )
    }
}
