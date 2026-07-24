package dev.ungaaaabungaaa.relay.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

object RelayColors {
    val Ink = Color(0xFF050505)
    val Surface = Color(0xFF17191C)
    val Raised = Color(0xFF22252A)
    val Line = Color(0xFF353941)
    val White = Color(0xFFF5F7F8)
    val Muted = Color(0xFFA2A8B0)
    val Green = Color(0xFF62E790)
    val Amber = Color(0xFFFFC857)
    val Red = Color(0xFFFF6B6B)
    val Blue = Color(0xFF71B7FF)
}

@Composable
fun RelayTheme(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(RelayColors.Ink),
    ) {
        content()
    }
}
