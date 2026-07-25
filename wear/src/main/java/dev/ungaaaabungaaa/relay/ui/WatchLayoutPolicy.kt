package dev.ungaaaabungaaa.relay.ui

data class WatchLayoutPolicy(
    val horizontalInsetDp: Int,
    val verticalInsetDp: Int,
    val minimumTouchTargetDp: Int,
    val compact: Boolean,
) {
    companion object {
        fun forScreen(
            widthDp: Int,
            heightDp: Int,
            isRound: Boolean,
        ): WatchLayoutPolicy {
            val compact = minOf(widthDp, heightDp) < 192
            return WatchLayoutPolicy(
                horizontalInsetDp = when {
                    isRound && compact -> 18
                    isRound -> 16
                    compact -> 8
                    else -> 6
                },
                verticalInsetDp = if (isRound) 12 else 8,
                minimumTouchTargetDp = 48,
                compact = compact,
            )
        }
    }
}
