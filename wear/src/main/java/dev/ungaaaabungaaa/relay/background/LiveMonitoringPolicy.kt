package dev.ungaaaabungaaa.relay.background

const val FOUR_HOURS_MS: Long = 4 * 60 * 60 * 1_000

enum class MonitoringStopReason {
    TimeLimit,
    LowBattery,
    Revoked,
    UserStopped,
}

sealed interface MonitoringDecision {
    data object Continue : MonitoringDecision
    data class Stop(val reason: MonitoringStopReason) : MonitoringDecision
}

class LiveMonitoringPolicy(
    private val maximumDurationMs: Long = FOUR_HOURS_MS,
    private val lowBatteryThreshold: Int = 15,
) {
    fun evaluate(
        startedAtMs: Long,
        nowMs: Long,
        batteryPercent: Int,
        charging: Boolean,
        revoked: Boolean,
        explicitStop: Boolean,
    ): MonitoringDecision = when {
        revoked -> MonitoringDecision.Stop(MonitoringStopReason.Revoked)
        explicitStop -> MonitoringDecision.Stop(MonitoringStopReason.UserStopped)
        nowMs - startedAtMs >= maximumDurationMs ->
            MonitoringDecision.Stop(MonitoringStopReason.TimeLimit)
        !charging && batteryPercent < lowBatteryThreshold ->
            MonitoringDecision.Stop(MonitoringStopReason.LowBattery)
        else -> MonitoringDecision.Continue
    }
}
