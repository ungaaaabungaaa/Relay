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

    var liveMonitoringEnabled: Boolean
        get() = values.getBoolean("live_monitoring_enabled", false)
        set(value) = values.edit().putBoolean("live_monitoring_enabled", value).apply()

    var lowBatteryThreshold: Int
        get() = values.getInt("low_battery_threshold", 15)
        set(value) = values.edit().putInt("low_battery_threshold", value.coerceIn(5, 50)).apply()

    var pendingSummaryCount: Int
        get() = values.getInt("pending_summary_count", 0)
        set(value) = values.edit().putInt("pending_summary_count", value).apply()

    var runningTaskSummaryCount: Int
        get() = values.getInt("running_task_summary_count", 0)
        set(value) = values.edit().putInt("running_task_summary_count", value).apply()

    var lastSummaryRefreshAt: Long
        get() = values.getLong("last_summary_refresh_at", 0)
        set(value) = values.edit().putLong("last_summary_refresh_at", value).apply()

    var lastMonitoringStopReason: String?
        get() = values.getString("last_monitoring_stop_reason", null)
        set(value) = values.edit().putString("last_monitoring_stop_reason", value).apply()

    fun clear() {
        values.edit().clear().apply()
    }
}
