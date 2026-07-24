package dev.ungaaaabungaaa.relay.domain

fun parseApprovalRisk(value: String?): ApprovalRisk = when (value) {
    "normal" -> ApprovalRisk.Normal
    else -> ApprovalRisk.Dangerous
}

fun RelayApproval.requiresHold(): Boolean = risk == ApprovalRisk.Dangerous
