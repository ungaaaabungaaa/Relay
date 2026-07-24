package dev.ungaaaabungaaa.relay.domain

data class RelayTask(
    val id: String,
    val title: String,
    val status: String,
    val cwd: String,
    val preview: String = "",
    val updatedAt: Long = 0,
)

data class RelayApproval(
    val id: String,
    val threadId: String,
    val kind: String,
    val command: String?,
    val cwd: String?,
    val reason: String?,
)

data class RelayQuestion(
    val id: String,
    val threadId: String,
    val prompt: String,
    val options: List<String> = emptyList(),
)

data class RelayModel(
    val id: String,
    val name: String,
    val description: String,
    val efforts: List<String>,
    val defaultEffort: String,
)

data class RelayFolder(val name: String, val path: String)

data class ApprovalHistoryItem(
    val id: String,
    val decision: String,
    val summary: String,
    val timestamp: Long,
)
