package dev.ungaaaabungaaa.relay.background

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import dev.ungaaaabungaaa.relay.MainActivity
import dev.ungaaaabungaaa.relay.R
import dev.ungaaaabungaaa.relay.data.RelayApi
import dev.ungaaaabungaaa.relay.data.RelayCloudDeviceStore
import dev.ungaaaabungaaa.relay.data.RelayCloudTransport
import dev.ungaaaabungaaa.relay.data.RelayLiveEvent
import dev.ungaaaabungaaa.relay.data.RelayPreferences
import dev.ungaaaabungaaa.relay.data.RelaySocket
import dev.ungaaaabungaaa.relay.domain.RelayConnectionState
import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class LiveMonitoringService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val policy by lazy {
        LiveMonitoringPolicy(
            lowBatteryThreshold = preferences.lowBatteryThreshold,
        )
    }
    private val preferences by lazy { RelayPreferences(this) }
    private val identity by lazy { DeviceIdentity() }
    private val cloudStore by lazy { RelayCloudDeviceStore(this) }
    private val api by lazy {
        RelayApi(
            preferences,
            identity,
            RelayCloudTransport(preferences, cloudStore),
        )
    }
    private val socket by lazy {
        RelaySocket(
            preferences = preferences,
            identity = identity,
            cloudDeviceStore = cloudStore,
            scope = serviceScope,
            onEvent = ::handleEvent,
            onConnectionChanged = ::handleConnection,
        )
    }
    private var startedAtMs = 0L
    private var stopped = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopMonitoring(MonitoringStopReason.UserStopped)
            return START_NOT_STICKY
        }
        if (preferences.deviceId == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (startedAtMs == 0L) startMonitoring()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        socket.close()
        serviceScope.cancel()
        preferences.liveMonitoringEnabled = false
        RelayRefreshWorker.schedule(this)
        super.onDestroy()
    }

    private fun startMonitoring() {
        startedAtMs = System.currentTimeMillis()
        preferences.liveMonitoringEnabled = true
        RelayRefreshWorker.cancel(this)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, monitoringNotification())
        socket.start(preferences.lastEventId)
        serviceScope.launch {
            while (isActive && !stopped) {
                evaluateStopPolicy()
                if (cloudStore.load() != null) {
                    refreshSnapshot(preferences.lastEventId)
                }
                delay(60_000)
            }
        }
    }

    private fun handleEvent(event: RelayLiveEvent) {
        when (event) {
            is RelayLiveEvent.SnapshotRequired -> refreshSnapshot(event.latestEventId)
            else -> {
                val sequence = event.sequenceOrNull() ?: return
                val expected = preferences.lastEventId + 1
                if (preferences.lastEventId == 0L || sequence == expected) {
                    preferences.lastEventId = sequence
                } else if (sequence > preferences.lastEventId) {
                    refreshSnapshot(sequence)
                }
            }
        }
    }

    private fun handleConnection(connectionState: RelayConnectionState) {
        if (connectionState == RelayConnectionState.Revoked) {
            stopMonitoring(MonitoringStopReason.Revoked)
        }
    }

    private fun refreshSnapshot(latestEventId: Long) {
        serviceScope.launch {
            runCatching {
                val inbox = api.inbox()
                val tasks = api.tasks()
                preferences.pendingSummaryCount = inbox.first.size + inbox.second.size
                preferences.runningTaskSummaryCount = tasks.count { it.status == "running" }
                preferences.lastSummaryRefreshAt = System.currentTimeMillis()
                preferences.lastEventId = latestEventId
                socket.start(latestEventId)
            }
        }
    }

    private fun evaluateStopPolicy() {
        val battery = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, 100) ?: 100
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val batteryPercent = if (scale > 0) level * 100 / scale else 100
        val status = battery?.getIntExtra(
            BatteryManager.EXTRA_STATUS,
            BatteryManager.BATTERY_STATUS_UNKNOWN,
        )
        val charging =
            status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        val decision = policy.evaluate(
            startedAtMs = startedAtMs,
            nowMs = System.currentTimeMillis(),
            batteryPercent = batteryPercent,
            charging = charging,
            revoked = false,
            explicitStop = false,
        )
        if (decision is MonitoringDecision.Stop) stopMonitoring(decision.reason)
    }

    private fun stopMonitoring(reason: MonitoringStopReason) {
        if (stopped) return
        stopped = true
        preferences.lastMonitoringStopReason = reason.name
        preferences.liveMonitoringEnabled = false
        socket.close()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun monitoringNotification(): android.app.Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, LiveMonitoringService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_relay)
            .setContentTitle("Relay live monitoring")
            .setContentText("Connected to your Mac · maximum four hours")
            .setContentIntent(openIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .addAction(0, "Stop", stopIntent)
        OngoingActivity.Builder(this, NOTIFICATION_ID, builder)
            .setStaticIcon(R.drawable.ic_relay)
            .setAnimatedIcon(R.drawable.ic_relay)
            .setTouchIntent(openIntent)
            .setContentDescription("Relay live monitoring")
            .build()
            .apply(this)
        return builder.build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Relay live monitoring",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "dev.ungaaaabungaaa.relay.action.START_LIVE_MONITORING"
        const val ACTION_STOP = "dev.ungaaaabungaaa.relay.action.STOP_LIVE_MONITORING"
        private const val CHANNEL_ID = "relay-live-monitoring"
        private const val NOTIFICATION_ID = 43117
    }
}

private fun RelayLiveEvent.sequenceOrNull(): Long? = when (this) {
    is RelayLiveEvent.ApprovalRequested -> sequence
    is RelayLiveEvent.QuestionRequested -> sequence
    is RelayLiveEvent.TaskChanged -> sequence
    is RelayLiveEvent.Ignored -> sequence
    is RelayLiveEvent.SnapshotRequired -> null
}
