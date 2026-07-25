package dev.ungaaaabungaaa.relay.data

import java.net.URI
import org.json.JSONObject

data class PairingDiscoveryRecord(
    val origin: String,
    val discoveryToken: String,
    val apiVersion: Int,
) {
    companion object {
        fun fromTxtAttributes(attributes: Map<String, ByteArray>): PairingDiscoveryRecord? {
            val origin = attributes["origin"]?.decodeToString()?.trimEnd('/') ?: return null
            val token = attributes["token"]?.decodeToString() ?: return null
            val api = attributes["api"]?.decodeToString()?.toIntOrNull() ?: return null
            val uri = runCatching { URI(origin) }.getOrNull() ?: return null
            if (
                uri.scheme != "https" ||
                uri.host.isNullOrBlank() ||
                !token.matches(Regex("^[a-f0-9]{32}$")) ||
                api != 1
            ) {
                return null
            }
            return PairingDiscoveryRecord(origin, token, api)
        }
    }
}

data class PairingMac(
    val name: String,
    val fingerprint: String,
    val apiVersion: Int,
    val expiresAt: Long,
)

data class PairingDeviceMetadata(
    val platform: String,
    val manufacturer: String,
    val model: String,
    val osVersion: String,
    val appVersion: String,
    val screenShape: String,
) {
    val displayName: String
        get() = listOf(manufacturer, model)
            .filter(String::isNotBlank)
            .joinToString(" ")
            .ifBlank { "Wear OS watch" }

    fun asMap(): Map<String, String> = mapOf(
        "platform" to platform,
        "manufacturer" to manufacturer,
        "model" to model,
        "osVersion" to osVersion,
        "appVersion" to appVersion,
        "screenShape" to screenShape,
    )

    fun toJson(): String = JSONObject()
        .apply { asMap().forEach(::put) }
        .toString()

    companion object {
        fun detected(
            manufacturer: String,
            model: String,
            osVersion: String,
            appVersion: String,
            isRound: Boolean,
        ) = PairingDeviceMetadata(
            platform = "wear-os",
            manufacturer = manufacturer.trim(),
            model = model.trim(),
            osVersion = osVersion.trim(),
            appVersion = appVersion.trim(),
            screenShape = if (isRound) "round" else "square",
        )
    }
}

object PairingContract {
    fun sessionPath(discoveryToken: String) =
        "/v1/pairing-sessions/$discoveryToken"

    fun statusPath(discoveryToken: String) =
        "${sessionPath(discoveryToken)}/status"
}

data class PendingPairing(
    val pairingId: String,
    val pollToken: String,
    val expiresAt: Long,
)

sealed interface PairingPollResult {
    data object Pending : PairingPollResult
    data object Denied : PairingPollResult
    data class Approved(
        val deviceId: String,
        val origin: String,
        val apiVersion: Int,
    ) : PairingPollResult
}
