package dev.ungaaaabungaaa.relay.ui

import dev.ungaaaabungaaa.relay.domain.Screen
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationPolicyTest {
    @Test
    fun reachesApprovalFromHomeThroughInbox() {
        assertPathAllowed(
            Screen.Home,
            Screen.Inbox,
            Screen.Approval,
        )
    }

    @Test
    fun reachesInstructionFromHomeThroughATask() {
        assertPathAllowed(
            Screen.Home,
            Screen.Tasks,
            Screen.TaskDetail,
            Screen.Instruction,
        )
    }

    @Test
    fun newTaskUsesAnExplicitLinearReviewFlow() {
        assertPathAllowed(
            Screen.Home,
            Screen.Workspaces,
            Screen.Folders,
            Screen.Models,
            Screen.Effort,
            Screen.Permissions,
            Screen.Prompt,
            Screen.NewTaskReview,
        )
    }

    private fun assertPathAllowed(vararg screens: Screen) {
        screens.asList().zipWithNext().forEach { (from, to) ->
            assertTrue(
                "$from should allow $to",
                NavigationPolicy.canNavigate(from, to),
            )
        }
    }
}
