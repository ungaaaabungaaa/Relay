package dev.ungaaaabungaaa.relay

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.ungaaaabungaaa.relay.ui.RelayApp
import dev.ungaaaabungaaa.relay.ui.RelayViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            RelayApp(viewModel<RelayViewModel>())
        }
    }
}
