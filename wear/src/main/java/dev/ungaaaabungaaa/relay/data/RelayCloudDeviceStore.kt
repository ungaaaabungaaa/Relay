package dev.ungaaaabungaaa.relay.data

import android.content.Context
import dev.ungaaaabungaaa.relay.security.RelaySecureStore
import java.util.Base64
import org.json.JSONObject

data class RelayCloudDeviceConfig(
    val accountId: String,
    val hostId: String,
    val deviceId: String,
    val credential: String,
    val rootKey: ByteArray,
    val apiVersion: Int,
)

class RelayCloudDeviceStore(context: Context) {
    private val secureStore = RelaySecureStore(context)

    fun load(): RelayCloudDeviceConfig? {
        val data = secureStore.get(CONFIG) ?: return null
        return runCatching {
            val objectValue = JSONObject(data.decodeToString())
            RelayCloudDeviceConfig(
                accountId = objectValue.getString("accountId"),
                hostId = objectValue.getString("hostId"),
                deviceId = objectValue.getString("deviceId"),
                credential = objectValue.getString("credential"),
                rootKey = Base64.getUrlDecoder().decode(objectValue.getString("rootKey")),
                apiVersion = objectValue.getInt("apiVersion"),
            ).also { require(it.rootKey.size == 32) }
        }.getOrNull()
    }

    fun save(config: RelayCloudDeviceConfig) {
        require(config.rootKey.size == 32)
        val data = JSONObject()
            .put("accountId", config.accountId)
            .put("hostId", config.hostId)
            .put("deviceId", config.deviceId)
            .put("credential", config.credential)
            .put(
                "rootKey",
                Base64.getUrlEncoder().withoutPadding().encodeToString(config.rootKey),
            )
            .put("apiVersion", config.apiVersion)
            .toString()
            .toByteArray()
        secureStore.put(CONFIG, data)
    }

    fun clear() = secureStore.remove(CONFIG)

    companion object {
        private const val CONFIG = "cloud_device_config_v1"
    }
}
