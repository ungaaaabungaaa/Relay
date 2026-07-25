package dev.ungaaaabungaaa.relay.platform

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeCapabilityPolicyTest {
    @Test
    fun wearOs3DoesNotRequestPermissionsIntroducedAfterApi30() {
        val policy = RuntimeCapabilityPolicy(sdkInt = 30)

        assertFalse(policy.requiresNotificationPermission)
        assertFalse(policy.requiresDataSyncForegroundServicePermission)
        assertFalse(policy.usesContextMediaRecorder)
        assertTrue(policy.canStartForegroundService)
    }

    @Test
    fun currentAndroidUsesNotificationAndDataSyncGuards() {
        val policy = RuntimeCapabilityPolicy(sdkInt = 36)

        assertTrue(policy.requiresNotificationPermission)
        assertTrue(policy.requiresDataSyncForegroundServicePermission)
        assertTrue(policy.usesContextMediaRecorder)
        assertTrue(policy.canStartForegroundService)
    }
}
