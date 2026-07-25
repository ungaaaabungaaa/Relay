package dev.ungaaaabungaaa.relay.audio

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import java.io.File
import java.util.UUID

data class VoiceClip(
    val file: File,
    val durationMs: Long,
)

class VoiceRecorderPolicy(
    private val maximumDurationMs: Long = 30_000,
) {
    fun shouldStop(startedAtMs: Long, nowMs: Long): Boolean =
        nowMs - startedAtMs >= maximumDurationMs
}

interface RecordingBackend {
    fun start(onMaximumDuration: () -> Unit)
    fun stop()
    fun cancel()
}

class VoiceRecorder(
    private val outputFileFactory: () -> File,
    private val backendFactory: (File) -> RecordingBackend,
    private val clock: () -> Long = SystemClock::elapsedRealtime,
    private val onMaximumDuration: (VoiceClip) -> Unit = {},
) {
    private var activeFile: File? = null
    private var activeBackend: RecordingBackend? = null
    private var startedAtMs: Long = 0

    val isRecording: Boolean
        get() = activeBackend != null

    fun start() {
        check(activeBackend == null) { "recording already active" }
        val file = outputFileFactory()
        file.parentFile?.mkdirs()
        val backend = backendFactory(file)
        activeFile = file
        activeBackend = backend
        startedAtMs = clock()
        try {
            backend.start {
                if (isRecording) onMaximumDuration(stop())
            }
        } catch (error: Throwable) {
            activeBackend = null
            activeFile = null
            deleteSensitiveFile(file)
            throw error
        }
    }

    fun stop(): VoiceClip {
        val backend = checkNotNull(activeBackend) { "no active recording" }
        val file = checkNotNull(activeFile) { "recording file missing" }
        val durationMs = (clock() - startedAtMs).coerceIn(1, 30_000)
        activeBackend = null
        activeFile = null
        try {
            backend.stop()
        } catch (error: Throwable) {
            deleteSensitiveFile(file)
            throw error
        }
        return VoiceClip(file, durationMs)
    }

    fun cancel() {
        val backend = activeBackend
        val file = activeFile
        activeBackend = null
        activeFile = null
        runCatching { backend?.cancel() }
        if (file != null) deleteSensitiveFile(file)
    }

    companion object {
        fun forContext(
            context: Context,
            onMaximumDuration: (VoiceClip) -> Unit,
        ): VoiceRecorder = VoiceRecorder(
            outputFileFactory = {
                File(
                    context.cacheDir,
                    "relay-audio-${UUID.randomUUID()}.m4a",
                )
            },
            backendFactory = { file -> AndroidRecordingBackend(context, file) },
            onMaximumDuration = onMaximumDuration,
        )
    }
}

suspend fun <T> VoiceClip.consume(operation: suspend (VoiceClip) -> T): T =
    try {
        operation(this)
    } finally {
        deleteSensitiveFile(file)
    }

private fun deleteSensitiveFile(file: File) {
    if (file.exists() && !file.delete()) {
        throw IllegalStateException("unable to delete temporary audio")
    }
}

private class AndroidRecordingBackend(
    context: Context,
    private val file: File,
) : RecordingBackend {
    private val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        MediaRecorder(context)
    } else {
        @Suppress("DEPRECATION")
        MediaRecorder()
    }
    private var started = false

    override fun start(onMaximumDuration: () -> Unit) {
        recorder.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(16_000)
            setAudioEncodingBitRate(64_000)
            setMaxDuration(30_000)
            setOutputFile(file.absolutePath)
            setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) {
                    onMaximumDuration()
                }
            }
            prepare()
            start()
        }
        started = true
    }

    override fun stop() {
        try {
            if (started) recorder.stop()
        } finally {
            started = false
            recorder.release()
        }
    }

    override fun cancel() {
        try {
            if (started) runCatching { recorder.stop() }
        } finally {
            started = false
            recorder.release()
        }
    }
}
