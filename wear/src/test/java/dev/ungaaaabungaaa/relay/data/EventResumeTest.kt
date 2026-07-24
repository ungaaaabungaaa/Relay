package dev.ungaaaabungaaa.relay.data

import dev.ungaaaabungaaa.relay.domain.ApprovalRisk
import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayQuestion
import dev.ungaaaabungaaa.relay.domain.RelayState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EventResumeTest {
    @Test
    fun ignoresDuplicateEventsAndAdvancesOnlyAcceptedSequences() {
        val approval = RelayApproval(
            id = "approval-1",
            threadId = "thread-1",
            kind = "command",
            risk = ApprovalRisk.Normal,
            riskReasons = emptyList(),
            command = "pnpm test",
            cwd = "/workspace",
            reason = null,
        )
        val initialState = RelayState(lastEventId = 3)
        val state = applyEvents(
            initialState,
            listOf(
                RelayLiveEvent.ApprovalRequested(4, approval),
                RelayLiveEvent.ApprovalRequested(4, approval),
                RelayLiveEvent.TaskChanged(5, "thread-1"),
            ),
        )

        assertEquals(5, state.lastEventId)
        assertEquals(2, state.appliedEventCount)
        assertEquals(listOf(approval), state.approvals)
        assertTrue(state.snapshotRequired)
    }

    @Test
    fun mapsQuestionsAndRequestsAFreshSnapshotAcrossRetentionGap() {
        val question = RelayQuestion(
            id = "question-1",
            threadId = "thread-1",
            prompt = "Which option?",
            options = listOf("Safe"),
        )
        val withQuestion = applyEvents(
            RelayState(lastEventId = 7),
            listOf(RelayLiveEvent.QuestionRequested(8, question)),
        )
        val gap = applyEvents(
            withQuestion,
            listOf(RelayLiveEvent.SnapshotRequired(latestEventId = 12)),
        )

        assertEquals(listOf(question), withQuestion.questions)
        assertEquals(8, withQuestion.lastEventId)
        assertTrue(gap.snapshotRequired)
        assertEquals(12, gap.snapshotEventId)
        assertEquals(8, gap.lastEventId)
    }
}
