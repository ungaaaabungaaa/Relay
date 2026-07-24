package dev.ungaaaabungaaa.relay.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RelayReducerTest {
    @Test
    fun startsInPairingAndConnectsToInbox() {
        val initial = RelayState()
        assertEquals(Screen.Pairing, initial.screen)

        val connected = reduce(initial, RelayAction.Connected)
        assertEquals(Screen.Inbox, connected.screen)
        assertTrue(connected.connected)
    }

    @Test
    fun preservesCurrentScreenWhenAConnectedSessionRefreshes() {
        val state = RelayState(
            screen = Screen.TaskDetail,
            connectionState = RelayConnectionState.Live,
            connected = true,
        )

        assertEquals(Screen.TaskDetail, reduce(state, RelayAction.Connected).screen)
    }

    @Test
    fun preservesTasksWhenConnectionBecomesStale() {
        val state = RelayState(
            screen = Screen.Tasks,
            connected = true,
            tasks = listOf(RelayTask("1", "Build", "running", "/tmp")),
        )
        val offline = reduce(state, RelayAction.Disconnected)
        assertEquals(1, offline.tasks.size)
        assertTrue(offline.stale)
        assertEquals(Screen.Offline, offline.screen)
    }

    @Test
    fun removesResolvedApproval() {
        val approval = RelayApproval(
            id = "a",
            threadId = "t",
            kind = "command",
            risk = ApprovalRisk.Dangerous,
            riskReasons = listOf("remote write"),
            command = "git push",
            cwd = "/tmp",
            reason = "network",
        )
        val state = RelayState(approvals = listOf(approval))
        assertTrue(reduce(state, RelayAction.ApprovalResolved("a")).approvals.isEmpty())
    }
}
