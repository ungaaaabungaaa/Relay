package dev.ungaaaabungaaa.relay.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import dev.ungaaaabungaaa.relay.ui.theme.RelayColors

@Composable
fun RelayScreen(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

@Composable
fun RelayList(
    title: String,
    status: String? = null,
    content: ScalingLazyListScope.() -> Unit,
) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 28.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                RelayLabel(
                    title.uppercase(),
                    color = RelayColors.Muted,
                    size = 11,
                    family = FontFamily.Monospace,
                    weight = FontWeight.Bold,
                )
                status?.let {
                    RelayLabel(it, color = RelayColors.Amber, size = 9)
                }
            }
        }
        content()
    }
}

@Composable
fun RelayLabel(
    text: String,
    color: Color = RelayColors.White,
    size: Int = 12,
    weight: FontWeight = FontWeight.Normal,
    family: FontFamily = FontFamily.SansSerif,
    maxLines: Int = 3,
    align: TextAlign = TextAlign.Center,
) {
    BasicText(
        text = text,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        style = TextStyle(
            color = color,
            fontSize = size.sp,
            fontWeight = weight,
            fontFamily = family,
            textAlign = align,
        ),
    )
}

@Composable
fun RelayCard(
    title: String,
    detail: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tone: Color = RelayColors.Surface,
    contentDescription: String = title,
    onClick: () -> Unit,
) {
    Column(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .background(tone, RoundedCornerShape(22.dp))
            .semantics { this.contentDescription = contentDescription }
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 15.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        RelayLabel(
            title,
            size = 11,
            weight = FontWeight.SemiBold,
            align = TextAlign.Start,
            maxLines = 2,
        )
        if (detail.isNotBlank()) {
            RelayLabel(
                detail,
                color = if (enabled) RelayColors.Muted else RelayColors.Line,
                size = 9,
                family = FontFamily.Monospace,
                align = TextAlign.Start,
                maxLines = 2,
            )
        }
    }
}

@Composable
fun RelayActionButton(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    color: Color = RelayColors.White,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .defaultMinSize(minWidth = 52.dp, minHeight = 48.dp)
            .background(if (enabled) color else RelayColors.Line, CircleShape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        RelayLabel(
            label,
            color = RelayColors.Ink,
            size = 10,
            weight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}

@Composable
fun RelayTextButton(
    label: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .defaultMinSize(minHeight = 48.dp)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        RelayLabel(
            label,
            color = if (enabled) RelayColors.White else RelayColors.Line,
            size = 10,
            weight = FontWeight.SemiBold,
        )
    }
}

@Composable
fun RelayInput(
    value: String,
    hint: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    onChange: (String) -> Unit,
) {
    Box(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 50.dp)
            .background(RelayColors.Surface, RoundedCornerShape(20.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = singleLine,
            textStyle = TextStyle(
                color = RelayColors.White,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                textAlign = TextAlign.Start,
            ),
            decorationBox = { inner ->
                if (value.isBlank()) {
                    RelayLabel(
                        hint,
                        color = RelayColors.Muted,
                        size = 10,
                        align = TextAlign.Start,
                    )
                }
                inner()
            },
        )
    }
}

@Composable
fun RelayStatusPill(
    text: String,
    color: Color,
) {
    Box(
        Modifier
            .background(color.copy(alpha = 0.18f), CircleShape)
            .padding(horizontal = 9.dp, vertical = 5.dp),
    ) {
        RelayLabel(text, color = color, size = 9, weight = FontWeight.Bold)
    }
}
