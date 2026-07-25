package dev.ungaaaabungaaa.relay.platform

import android.os.Build

data class RuntimeCapabilityPolicy(
    val sdkInt: Int = Build.VERSION.SDK_INT,
) {
    val requiresNotificationPermission: Boolean
        get() = sdkInt >= Build.VERSION_CODES.TIRAMISU

    val requiresDataSyncForegroundServicePermission: Boolean
        get() = sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    val canStartForegroundService: Boolean
        get() = sdkInt >= Build.VERSION_CODES.O

    val usesContextMediaRecorder: Boolean
        get() = sdkInt >= Build.VERSION_CODES.S
}
