package dev.ungaaaabungaaa.relay.ui

import dev.ungaaaabungaaa.relay.ui.components.HoldController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HoldControllerTest {
    @Test
    fun confirmsOnlyAfterFifteenHundredMillisecondsOfContinuousPress() {
        val controller = HoldController()
        controller.press(10_000)

        assertFalse(controller.advance(11_499))
        assertTrue(controller.advance(11_500))
        assertFalse(controller.advance(12_000))
    }

    @Test
    fun earlyReleasePointerExitAndLifecycleLossResetProgress() {
        val controller = HoldController()
        controller.press(1_000)
        assertFalse(controller.release(2_499))
        assertEquals(0f, controller.progress(2_499))

        controller.press(3_000)
        controller.cancel()
        assertEquals(0f, controller.progress(4_000))

        controller.press(5_000)
        controller.cancel()
        assertFalse(controller.advance(7_000))
    }
}
