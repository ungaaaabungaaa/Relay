package dev.ungaaaabungaaa.relay.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ungaaaabungaaa.relay.domain.Screen

private val Ink = Color(0xFF050505)
private val Surface = Color(0xFF171717)
private val Line = Color(0xFF303030)
private val White = Color(0xFFF5F5F5)
private val Muted = Color(0xFF9A9A9A)
private val Green = Color(0xFF42D77D)
private val Red = Color(0xFFFF5C5C)

@Composable
fun RelayApp(viewModel: RelayViewModel) {
    val state = viewModel.state
    Box(
        modifier = Modifier.fillMaxSize().background(Ink).padding(horizontal = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        when (state.screen) {
            Screen.Pairing -> Pairing(viewModel)
            Screen.Offline -> Offline(viewModel)
            Screen.Inbox -> Inbox(viewModel)
            Screen.Approval -> Approval(viewModel)
            Screen.Question -> SimpleScreen("Question", state.selectedQuestion?.prompt ?: "No question")
            Screen.Tasks -> Tasks(viewModel)
            Screen.TaskDetail -> TaskDetail(viewModel)
            Screen.Voice -> SimpleScreen("Voice", "Hold to record\nReview before sending")
            Screen.Transcript -> SimpleScreen("Transcript", state.transcript.ifBlank { "No transcript yet" })
            Screen.Folders -> SimpleScreen("Mac folders", state.selectedFolder.ifBlank { "Choose when creating a task" })
            Screen.Models -> SimpleScreen("Models", state.selectedModel.ifBlank { "Loaded from Codex" })
            Screen.NewTask -> SimpleScreen("New task", "Folder · model · effort · prompt")
            Screen.Settings -> Settings(viewModel)
            Screen.History -> History(viewModel)
        }
        state.error?.let {
            Box(
                Modifier.align(Alignment.BottomCenter)
                    .background(Red, RoundedCornerShape(20.dp))
                    .clickable { viewModel.clearError() }
                    .padding(horizontal = 12.dp, vertical = 7.dp),
            ) { Label(it, color = Color.Black, size = 10) }
        }
    }
}

@Composable
private fun Pairing(vm: RelayViewModel) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Label("RELAY", size = 20, weight = FontWeight.Bold, family = FontFamily.Monospace)
        Label("Pair with your Mac", color = Muted, size = 11)
        Spacer(Modifier.height(10.dp))
        Input(vm.bridgeUrl, "Bridge URL") { vm.bridgeUrl = it }
        Spacer(Modifier.height(6.dp))
        Input(vm.pairingCode, "6-character code") { vm.pairingCode = it.uppercase().take(6) }
        Spacer(Modifier.height(9.dp))
        Action("Pair watch", Green) { vm.pair() }
    }
}

@Composable
private fun Offline(vm: RelayViewModel) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Label("Mac offline", size = 18, weight = FontWeight.Bold)
        Label("Check adb reverse and bridge", color = Muted, size = 10)
        Spacer(Modifier.height(10.dp))
        Action("Reconnect", White) { vm.refresh() }
        Spacer(Modifier.height(5.dp))
        Link("Settings") { vm.navigate(Screen.Settings) }
    }
}

@Composable
private fun Inbox(vm: RelayViewModel) {
    val state = vm.state
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item { Label("INBOX", size = 12, family = FontFamily.Monospace, color = Muted) }
        if (state.approvals.isEmpty() && state.questions.isEmpty()) {
            item { Label("Nothing blocking Codex", color = Green, size = 12) }
        }
        items(state.approvals) { approval ->
            Card(
                title = approval.command ?: approval.kind,
                detail = approval.cwd ?: "Approval required",
                color = Color(0xFF251919),
            ) { vm.selectApproval(approval) }
        }
        items(state.questions) { question ->
            Card("Question", question.prompt) {
                vm.navigate(Screen.Question)
            }
        }
        item {
            Row {
                Link("Tasks") { vm.navigate(Screen.Tasks) }
                Spacer(Modifier.width(12.dp))
                Link("History") { vm.navigate(Screen.History) }
            }
        }
    }
}

@Composable
private fun Approval(vm: RelayViewModel) {
    val approval = vm.state.selectedApproval
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Label("APPROVAL", color = Red, size = 11, family = FontFamily.Monospace)
        Label(approval?.command ?: approval?.kind ?: "Expired", size = 13, weight = FontWeight.Bold)
        Label(approval?.cwd ?: "", color = Muted, size = 9, family = FontFamily.Monospace)
        Label(approval?.reason ?: "", color = Muted, size = 9)
        Spacer(Modifier.height(9.dp))
        Row {
            Action("Deny", Red) { vm.decide(false) }
            Spacer(Modifier.width(6.dp))
            Action("Approve", Green) { vm.decide(true) }
        }
    }
}

@Composable
private fun Tasks(vm: RelayViewModel) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { Label("TASKS", size = 12, family = FontFamily.Monospace, color = Muted) }
        items(vm.state.tasks) { task ->
            Card(task.title, "${task.status} · ${task.cwd}") { vm.selectTask(task) }
        }
        item { Link("Back to inbox") { vm.navigate(Screen.Inbox) } }
    }
}

@Composable
private fun TaskDetail(vm: RelayViewModel) {
    val task = vm.state.selectedTask
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Label(task?.title ?: "Task", size = 15, weight = FontWeight.Bold)
        Label(task?.cwd ?: "", color = Muted, size = 9, family = FontFamily.Monospace)
        Spacer(Modifier.height(8.dp))
        Input(vm.instruction, "Instruction") { vm.instruction = it }
        Spacer(Modifier.height(7.dp))
        Action("Send", White) { vm.sendInstruction() }
        Spacer(Modifier.height(5.dp))
        Row {
            Link("Voice") { vm.navigate(Screen.Voice) }
            Spacer(Modifier.width(12.dp))
            Link("Inbox") { vm.navigate(Screen.Inbox) }
        }
    }
}

@Composable
private fun Settings(vm: RelayViewModel) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Label("SETTINGS", size = 12, family = FontFamily.Monospace, color = Muted)
        Label(vm.bridgeUrl, size = 9, family = FontFamily.Monospace)
        Spacer(Modifier.height(8.dp))
        Action("Unpair", Red) { vm.unpair() }
        Spacer(Modifier.height(5.dp))
        Link("Back") { vm.navigate(Screen.Inbox) }
    }
}

@Composable
private fun History(vm: RelayViewModel) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        item { Label("HISTORY", size = 12, family = FontFamily.Monospace, color = Muted) }
        items(vm.state.history) { item -> Card(item.decision, item.summary) {} }
        item { Link("Back") { vm.navigate(Screen.Inbox) } }
    }
}

@Composable
private fun SimpleScreen(title: String, body: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Label(title.uppercase(), color = Muted, size = 11, family = FontFamily.Monospace)
        Spacer(Modifier.height(6.dp))
        Label(body, size = 12)
    }
}

@Composable
private fun Input(value: String, hint: String, onChange: (String) -> Unit) {
    Box(
        Modifier.fillMaxWidth()
            .background(Surface, RoundedCornerShape(16.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            textStyle = TextStyle(White, fontSize = 10.sp, fontFamily = FontFamily.Monospace),
            decorationBox = { inner ->
                if (value.isBlank()) Label(hint, color = Muted, size = 10)
                inner()
            },
        )
    }
}

@Composable
private fun Action(label: String, color: Color, onClick: () -> Unit) {
    Box(
        Modifier.background(color, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 8.dp),
    ) { Label(label, color = Color.Black, size = 10, weight = FontWeight.Bold) }
}

@Composable
private fun Link(label: String, onClick: () -> Unit) {
    Box(Modifier.clickable(onClick = onClick).padding(8.dp)) {
        Label(label, color = White, size = 10)
    }
}

@Composable
private fun Card(
    title: String,
    detail: String,
    color: Color = Surface,
    onClick: () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth()
            .background(color, RoundedCornerShape(18.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 9.dp),
    ) {
        Label(title, size = 11, weight = FontWeight.SemiBold)
        Label(detail, color = Muted, size = 8, family = FontFamily.Monospace)
    }
}

@Composable
private fun Label(
    text: String,
    color: Color = White,
    size: Int = 12,
    weight: FontWeight = FontWeight.Normal,
    family: FontFamily = FontFamily.SansSerif,
) {
    BasicText(
        text = text,
        style = TextStyle(
            color = color,
            fontSize = size.sp,
            fontWeight = weight,
            fontFamily = family,
            textAlign = TextAlign.Center,
        ),
    )
}
