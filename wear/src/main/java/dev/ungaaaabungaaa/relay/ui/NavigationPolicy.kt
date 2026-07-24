package dev.ungaaaabungaaa.relay.ui

import dev.ungaaaabungaaa.relay.domain.Screen

object NavigationPolicy {
    private val transitions = setOf(
        Screen.Home to Screen.Inbox,
        Screen.Inbox to Screen.Approval,
        Screen.Inbox to Screen.Question,
        Screen.Home to Screen.Tasks,
        Screen.Tasks to Screen.TaskDetail,
        Screen.TaskDetail to Screen.Instruction,
        Screen.Home to Screen.Workspaces,
        Screen.Workspaces to Screen.Folders,
        Screen.Folders to Screen.Models,
        Screen.Models to Screen.Effort,
        Screen.Effort to Screen.Permissions,
        Screen.Permissions to Screen.Prompt,
        Screen.Prompt to Screen.NewTaskReview,
    )

    fun canNavigate(from: Screen, to: Screen): Boolean =
        from == to || transitions.contains(from to to)
}
