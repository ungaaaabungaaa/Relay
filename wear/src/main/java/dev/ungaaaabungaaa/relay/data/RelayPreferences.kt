package dev.ungaaaabungaaa.relay.data

import android.content.Context

class RelayPreferences(context: Context) {
    private val values = context.getSharedPreferences("relay", Context.MODE_PRIVATE)

    var deviceId: String?
        get() = values.getString("device_id", null)
        set(value) = values.edit().putString("device_id", value).apply()

    var bridgeUrl: String
        get() = values.getString("bridge_url", "http://127.0.0.1:43117")
            ?: "http://127.0.0.1:43117"
        set(value) = values.edit().putString("bridge_url", value.trimEnd('/')).apply()

    var lastEventId: Long
        get() = values.getLong("last_event_id", 0)
        set(value) = values.edit().putLong("last_event_id", value).apply()

    fun clear() {
        values.edit().clear().apply()
    }
}
