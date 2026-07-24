package dev.ungaaaabungaaa.relay.ui.components

import android.os.SystemClock
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors
import kotlinx.coroutines.withTimeoutOrNull

class HoldController(
    private val requiredDurationMs: Long = 1_500,
) {
    private var pressedAtMs: Long? = null
    private var confirmed = false

    fun press(nowMs: Long) {
        pressedAtMs = nowMs
        confirmed = false
    }

    fun advance(nowMs: Long): Boolean {
        val startedAt = pressedAtMs ?: return false
        if (confirmed || nowMs - startedAt < requiredDurationMs) return false
        confirmed = true
        return true
    }

    fun release(nowMs: Long): Boolean {
        val didConfirm = advance(nowMs)
        reset()
        return didConfirm
    }

    fun cancel() {
        reset()
    }

    fun progress(nowMs: Long): Float {
        val startedAt = pressedAtMs ?: return 0f
        return ((nowMs - startedAt).toFloat() / requiredDurationMs)
            .coerceIn(0f, 1f)
    }

    private fun reset() {
        pressedAtMs = null
        confirmed = false
    }
}

@Composable
fun HoldToConfirm(
    label: String,
    enabled: Boolean,
    onConfirm: () -> Unit,
) {
    val controller = remember { HoldController() }
    var pressed by remember { mutableStateOf(false) }
    val progress by animateFloatAsState(
        targetValue = if (pressed) 1f else 0f,
        animationSpec = tween(durationMillis = if (pressed) 1_500 else 150),
        label = "hold progress",
    )
    DisposableEffect(controller) {
        onDispose { controller.cancel() }
    }

    Box(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .background(
                if (enabled) RelayColors.Raised else RelayColors.Line,
                CircleShape,
            )
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                detectTapGestures(
                    onPress = {
                        controller.press(SystemClock.uptimeMillis())
                        pressed = true
                        try {
                            val released = withTimeoutOrNull(1_500) {
                                tryAwaitRelease()
                            }
                            if (released == null) {
                                if (controller.advance(SystemClock.uptimeMillis())) {
                                    onConfirm()
                                }
                            } else if (released) {
                                if (controller.release(SystemClock.uptimeMillis())) {
                                    onConfirm()
                                }
                            } else {
                                controller.cancel()
                            }
                        } finally {
                            controller.cancel()
                            pressed = false
                        }
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .fillMaxWidth(progress)
                .fillMaxHeight()
                .align(Alignment.CenterStart)
                .background(RelayColors.Green.copy(alpha = 0.75f), CircleShape),
        )
        RelayLabel(
            if (enabled) label else "Unavailable while offline",
            color = if (enabled) RelayColors.White else RelayColors.Muted,
            size = 10,
        )
    }
}

@Composable
fun HoldToRecord(
    enabled: Boolean,
    recording: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onCancel: () -> Unit,
) {
    Box(
        Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 58.dp)
            .background(
                when {
                    !enabled -> RelayColors.Line
                    recording -> RelayColors.Red
                    else -> RelayColors.Red.copy(alpha = 0.24f)
                },
                CircleShape,
            )
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                detectTapGestures(
                    onPress = {
                        onStart()
                        val released = tryAwaitRelease()
                        if (released) onStop() else onCancel()
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        RelayLabel(
            when {
                !enabled -> "Unavailable while offline"
                recording -> "Release to transcribe"
                else -> "Press and hold to record"
            },
            color = RelayColors.White,
            size = 10,
        )
    }
}
