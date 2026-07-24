package dev.ungaaaabungaaa.relay.background

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.ungaaaabungaaa.relay.data.RelayApi
import dev.ungaaaabungaaa.relay.data.RelayPreferences
import dev.ungaaaabungaaa.relay.security.DeviceIdentity
import java.util.concurrent.TimeUnit

class RelayRefreshWorker(
    applicationContext: Context,
    workerParameters: WorkerParameters,
) : CoroutineWorker(applicationContext, workerParameters) {
    override suspend fun doWork(): Result {
        val preferences = RelayPreferences(applicationContext)
        if (preferences.liveMonitoringEnabled || preferences.deviceId == null) {
            return Result.success()
        }
        return runCatching {
            val api = RelayApi(preferences, DeviceIdentity())
            val inbox = api.inbox()
            val tasks = api.tasks()
            preferences.pendingSummaryCount = inbox.first.size + inbox.second.size
            preferences.runningTaskSummaryCount = tasks.count { it.status == "running" }
            preferences.lastSummaryRefreshAt = System.currentTimeMillis()
            Result.success()
        }.getOrElse {
            Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "relay-summary-refresh"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<RelayRefreshWorker>(
                15,
                TimeUnit.MINUTES,
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresBatteryNotLow(true)
                        .build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
