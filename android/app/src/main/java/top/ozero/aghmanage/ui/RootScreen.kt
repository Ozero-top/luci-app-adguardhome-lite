package top.ozero.aghmanage.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import top.ozero.aghmanage.data.AghClient

private class Tab(val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("概览", Icons.Filled.Home),
    Tab("日志", Icons.AutoMirrored.Filled.List),
    Tab("规则", Icons.Filled.CheckCircle),
    Tab("设置", Icons.Filled.Settings),
    Tab("更多", Icons.Filled.MoreVert)
)

@Composable
fun RootScreen(client: AghClient, onLogout: () -> Unit) {
    var index by remember { mutableStateOf(0) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { i, tab ->
                    NavigationBarItem(
                        selected = index == i,
                        onClick = { index = i },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (index) {
                0 -> OverviewScreen(client, onLogout)
                1 -> LogsScreen(client)
                2 -> RulesScreen(client)
                3 -> SettingsScreen(client)
                else -> MoreScreen(client)
            }
        }
    }
}
