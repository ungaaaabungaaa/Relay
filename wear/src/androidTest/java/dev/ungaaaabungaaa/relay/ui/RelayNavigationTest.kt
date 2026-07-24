package dev.ungaaaabungaaa.relay.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.ungaaaabungaaa.relay.domain.ApprovalRisk
import dev.ungaaaabungaaa.relay.domain.RelayApproval
import dev.ungaaaabungaaa.relay.domain.RelayState
import dev.ungaaaabungaaa.relay.ui.screens.ApprovalScreen
import dev.ungaaaabungaaa.relay.ui.screens.HomeScreen
import dev.ungaaaabungaaa.relay.ui.screens.InboxScreen
import dev.ungaaaabungaaa.relay.ui.theme.RelayTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RelayNavigationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun homeToInboxToApprovalKeepsTheExactCommandVisible() {
        val approval = RelayApproval(
            id = "approval-1",
            threadId = "thread-1",
            kind = "command",
            risk = ApprovalRisk.Normal,
            riskReasons = emptyList(),
            command = "git status --short",
            cwd = "/workspace/relay",
            reason = null,
        )
        var screen by mutableStateOf("home")

        compose.setContent {
            RelayTheme {
                when (screen) {
                    "home" -> HomeScreen(
                        state = RelayState(
                            connected = true,
                            approvals = listOf(approval),
                        ),
                        onInbox = { screen = "inbox" },
                        onTasks = {},
                        onNewTask = {},
                        onSettings = {},
                    )
                    "inbox" -> InboxScreen(
                        state = RelayState(
                            connected = true,
                            approvals = listOf(approval),
                        ),
                        onApproval = { screen = "approval" },
                        onQuestion = {},
                        onHome = {},
                        onHistory = {},
                    )
                    else -> ApprovalScreen(
                        approval = approval,
                        canRespond = true,
                        onDeny = {},
                        onApprove = {},
                        onBack = {},
                    )
                }
            }
        }

        compose.onNodeWithText("1 waiting").performClick()
        compose.onNodeWithText("git status --short").performClick()
        compose.onNodeWithText("git status --short").assertIsDisplayed()
        compose.onNodeWithText("/workspace/relay").assertIsDisplayed()
    }
}
