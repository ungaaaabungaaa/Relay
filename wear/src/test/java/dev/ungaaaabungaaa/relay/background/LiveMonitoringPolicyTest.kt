package dev.ungaaaabungaaa.relay.background

import org.junit.Assert.assertEquals
import org.junit.Test

class LiveMonitoringPolicyTest {
    private val policy = LiveMonitoringPolicy()

    @Test
    fun stopsAtExactlyFourHours() {
        assertEquals(
            MonitoringDecision.Continue,
            policy.evaluate(
                startedAtMs = 1_000,
                nowMs = 1_000 + FOUR_HOURS_MS - 1,
                batteryPercent = 80,
                charging = false,
                revoked = false,
                explicitStop = false,
            ),
        )
        assertEquals(
            MonitoringDecision.Stop(MonitoringStopReason.TimeLimit),
            policy.evaluate(
                startedAtMs = 1_000,
                nowMs = 1_000 + FOUR_HOURS_MS,
                batteryPercent = 80,
                charging = false,
                revoked = false,
                explicitStop = false,
            ),
        )
    }

    @Test
    fun stopsBelowFifteenPercentUnlessCharging() {
        assertEquals(
            MonitoringDecision.Stop(MonitoringStopReason.LowBattery),
            policy.evaluate(0, 1, 14, false, false, false),
        )
        assertEquals(
            MonitoringDecision.Continue,
            policy.evaluate(0, 1, 14, true, false, false),
        )
        assertEquals(
            MonitoringDecision.Continue,
            policy.evaluate(0, 1, 15, false, false, false),
        )
    }

    @Test
    fun revocationAndExplicitStopEndTheSessionImmediately() {
        assertEquals(
            MonitoringDecision.Stop(MonitoringStopReason.Revoked),
            policy.evaluate(0, 0, 100, true, true, false),
        )
        assertEquals(
            MonitoringDecision.Stop(MonitoringStopReason.UserStopped),
            policy.evaluate(0, 0, 100, true, false, true),
        )
    }
}
