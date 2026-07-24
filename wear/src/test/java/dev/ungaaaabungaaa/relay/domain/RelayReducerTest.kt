package dev.ungaaaabungaaa.relay.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RelayReducerTest {
    @Test
    fun startsInPairingAndConnectsToHome() {
        val initial = RelayState()
        assertEquals(Screen.PairingCode, initial.screen)

        val connected = reduce(initial, RelayAction.Connected)
        assertEquals(Screen.Home, connected.screen)
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

    @Test
    fun revocationClearsCachedPrivateState() {
        val state = RelayState(
            screen = Screen.Home,
            connectionState = RelayConnectionState.Live,
            tasks = listOf(RelayTask("1", "Private task", "running", "/private")),
            questions = listOf(RelayQuestion("q", "t", "Private question")),
        )

        val revoked = reduce(
            state,
            RelayAction.ConnectionChanged(RelayConnectionState.Revoked),
        )

        assertEquals(Screen.Revoked, revoked.screen)
        assertTrue(revoked.tasks.isEmpty())
        assertTrue(revoked.questions.isEmpty())
    }
}
