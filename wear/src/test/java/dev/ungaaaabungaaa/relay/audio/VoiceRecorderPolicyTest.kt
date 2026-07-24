package dev.ungaaaabungaaa.relay.audio

import java.io.File
import kotlin.io.path.createTempFile
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceRecorderPolicyTest {
    @Test
    fun stopsAtExactlyThirtySeconds() {
        val policy = VoiceRecorderPolicy()
        assertFalse(policy.shouldStop(startedAtMs = 1_000, nowMs = 30_999))
        assertTrue(policy.shouldStop(startedAtMs = 1_000, nowMs = 31_000))
    }

    @Test
    fun cancellationDeletesTheLocalRecording() {
        val file = createTempFile("relay-cancel-", ".m4a").toFile()
        val recorder = VoiceRecorder(
            outputFileFactory = { file },
            backendFactory = { FakeBackend() },
            clock = { 1_000 },
        )

        recorder.start()
        recorder.cancel()

        assertFalse(file.exists())
    }

    @Test
    fun uploadSuccessAndFailureBothDeleteTheClip() = runBlocking {
        val successFile = createTempFile("relay-success-", ".m4a").toFile()
        val success = VoiceClip(successFile, durationMs = 1_000).consume {
            "transcript"
        }
        assertEquals("transcript", success)
        assertFalse(successFile.exists())

        val failureFile = createTempFile("relay-failure-", ".m4a").toFile()
        runCatching {
            VoiceClip(failureFile, durationMs = 1_000).consume<String> {
                error("upload failed")
            }
        }
        assertFalse(failureFile.exists())
    }
}

private class FakeBackend : RecordingBackend {
    override fun start(onMaximumDuration: () -> Unit) = Unit
    override fun stop() = Unit
    override fun cancel() = Unit
}
