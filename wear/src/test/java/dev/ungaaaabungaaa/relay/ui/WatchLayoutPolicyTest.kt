package dev.ungaaaabungaaa.relay.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchLayoutPolicyTest {
    @Test
    fun roundScreensReserveMoreHorizontalEdgeSpace() {
        val round = WatchLayoutPolicy.forScreen(
            widthDp = 192,
            heightDp = 192,
            isRound = true,
        )
        val square = WatchLayoutPolicy.forScreen(
            widthDp = 192,
            heightDp = 192,
            isRound = false,
        )

        assertTrue(round.horizontalInsetDp > square.horizontalInsetDp)
        assertEquals(12, round.verticalInsetDp)
        assertEquals(8, square.verticalInsetDp)
    }

    @Test
    fun smallerWatchesKeepTouchTargetsAndUseCompactSpacing() {
        val compact = WatchLayoutPolicy.forScreen(
            widthDp = 180,
            heightDp = 180,
            isRound = true,
        )

        assertEquals(48, compact.minimumTouchTargetDp)
        assertTrue(compact.compact)
    }
}
