package dev.ungaaaabungaaa.relay.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ApprovalPolicyTest {
    @Test
    fun dangerousApprovalRequiresHold() {
        assertTrue(sampleApproval(ApprovalRisk.Dangerous).requiresHold())
        assertFalse(sampleApproval(ApprovalRisk.Normal).requiresHold())
    }

    @Test
    fun missingOrUnknownRiskFailsClosed() {
        assertTrue(parseApprovalRisk(null) == ApprovalRisk.Dangerous)
        assertTrue(parseApprovalRisk("") == ApprovalRisk.Dangerous)
        assertTrue(parseApprovalRisk("elevated") == ApprovalRisk.Dangerous)
        assertTrue(parseApprovalRisk("normal") == ApprovalRisk.Normal)
    }

    private fun sampleApproval(risk: ApprovalRisk) = RelayApproval(
        id = "approval-1",
        threadId = "thread-1",
        kind = "command",
        risk = risk,
        riskReasons = emptyList(),
        command = "git status",
        cwd = "/tmp/relay",
        reason = null,
    )
}
