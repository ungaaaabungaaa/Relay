package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import dev.ungaaaabungaaa.relay.security.RelayAgreementIdentity
import dev.ungaaaabungaaa.relay.security.RelayCloudCrypto
import dev.ungaaaabungaaa.relay.security.RelayCloudPairingCrypto
import dev.ungaaaabungaaa.relay.security.RelayCloudPairingPayloadEnvelope
import dev.ungaaaabungaaa.relay.security.RelayP256
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

data class RelayCloudPendingPairing(
    val requestId: String,
    val pollToken: String,
    val accountId: String,
    val hostId: String,
    val sessionNonce: ByteArray,
    val macFingerprint: String,
    val rootKey: ByteArray,
    val expiresAt: Long,
)

sealed interface RelayCloudPairingStatus {
    data object Pending : RelayCloudPairingStatus
    data object Denied : RelayCloudPairingStatus
    data class Approved(val config: RelayCloudDeviceConfig) : RelayCloudPairingStatus
}

class RelayCloudPairingClient(
    private val identity: DeviceIdentity,
    private val agreementIdentity: RelayAgreementIdentity,
    private val deviceStore: RelayCloudDeviceStore,
    private val client: OkHttpClient = OkHttpClient(),
    private val apiOrigin: String = "https://api.relayforcodex.com",
) {
    suspend fun request(
        code: String,
        metadata: PairingDeviceMetadata,
    ): RelayCloudPendingPairing = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("fingerprint", identity.fingerprint())
            .put("signingPublicKey", identity.publicKeyPem())
            .put(
                "agreementPublicKey",
                Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(agreementIdentity.publicKeyX963()),
            )
            .put("metadata", JSONObject(metadata.toJson()))
            .toString()
        val request = Request.Builder()
            .url("$apiOrigin/cloud/v1/pairing-sessions/${code.uppercase()}/requests")
            .post(body.toRequestBody(JSON))
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Pairing failed")
            val result = JSONObject(response.body.string())
            val sessionNonce = Base64.getUrlDecoder()
                .decode(result.getString("sessionNonce"))
            val macPublicKey = RelayP256.publicKeyFromX963(
                Base64.getUrlDecoder().decode(
                    result.getString("macAgreementPublicKey"),
                ),
            )
            val rootKey = RelayCloudCrypto.deriveRootKey(
                agreementIdentity.privateKey(),
                macPublicKey,
                sessionNonce,
            )
            RelayCloudPendingPairing(
                requestId = result.getString("id"),
                pollToken = result.getString("pollToken"),
                accountId = result.getString("accountId"),
                hostId = result.getString("hostId"),
                sessionNonce = sessionNonce,
                macFingerprint = result.getString("macFingerprint"),
                rootKey = rootKey,
                expiresAt = result.getLong("expiresAt"),
            )
        }
    }

    suspend fun poll(pending: RelayCloudPendingPairing): RelayCloudPairingStatus =
        withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url("$apiOrigin/cloud/v1/pairing-requests/${pending.requestId}")
                .header("authorization", "Pairing ${pending.pollToken}")
                .get()
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("Pairing approval expired")
                val result = JSONObject(response.body.string())
                when (result.getString("status")) {
                    "pending" -> RelayCloudPairingStatus.Pending
                    "denied" -> RelayCloudPairingStatus.Denied
                    "approved" -> {
                        val payload = result.getJSONObject("payload")
                        val credential = RelayCloudPairingCrypto.open(
                            RelayCloudPairingPayloadEnvelope(
                                version = payload.getInt("version"),
                                nonce = payload.getString("nonce"),
                                ciphertext = payload.getString("ciphertext"),
                            ),
                            requestId = pending.requestId,
                            hostId = pending.hostId,
                            rootKey = pending.rootKey,
                        )
                        check(
                            credential.accountId == pending.accountId &&
                                credential.hostId == pending.hostId &&
                                credential.apiVersion in
                                credential.minimumApiVersion..credential.maximumApiVersion &&
                                credential.minimumApiVersion <= 1 &&
                                credential.maximumApiVersion >= 1
                        ) { "Relay update required" }
                        val config = RelayCloudDeviceConfig(
                            accountId = credential.accountId,
                            hostId = credential.hostId,
                            deviceId = credential.deviceId,
                            credential = credential.credential,
                            rootKey = pending.rootKey,
                            apiVersion = credential.apiVersion,
                        )
                        deviceStore.save(config)
                        RelayCloudPairingStatus.Approved(config)
                    }
                    else -> error("Unsupported pairing response")
                }
            }
        }

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}
