package dev.ungaaaabungaaa.relay.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class IdempotencyKeyTest {
    @Test
    fun createsStableValidKeysForOneLogicalAction() {
        val first = idempotencyKeyFor("approval", "approval-1", "approve")
        val repeated = idempotencyKeyFor("approval", "approval-1", "approve")
        val denied = idempotencyKeyFor("approval", "approval-1", "deny")

        assertEquals(first, repeated)
        assertNotEquals(first, denied)
        assertTrue(first.matches(Regex("[A-Za-z0-9._:-]{16,128}")))
    }
}
