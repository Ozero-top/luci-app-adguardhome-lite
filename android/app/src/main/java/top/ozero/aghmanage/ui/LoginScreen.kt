package top.ozero.aghmanage.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import top.ozero.aghmanage.data.Profile

@Composable
fun LoginScreen(
    initial: Profile,
    onClientOnly: () -> Unit = {},
    onLogin: suspend (Profile) -> Unit
) {
    var host by remember { mutableStateOf(initial.host) }
    var port by remember { mutableStateOf(initial.port.toString()) }
    var https by remember { mutableStateOf(initial.https) }
    var user by remember { mutableStateOf(initial.user) }
    var pass by remember { mutableStateOf(initial.pass) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun submit() {
        if (busy) return
        val target = Profile(
            host = host.trim(),
            port = port.toIntOrNull() ?: 80,
            https = https,
            user = user.trim(),
            pass = pass
        )
        if (target.host.isEmpty()) {
            error = "请填写路由器地址"
            return
        }
        error = null
        busy = true
        scope.launch {
            try {
                onLogin(target)
            } catch (e: Exception) {
                error = e.message ?: "连接失败"
            } finally {
                busy = false
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFFDF7))
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 40.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(
            text = "AGHTools管理器",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = Color.Black
        )
        Text(
            text = "连接局域网内的路由器，管理 DNS 过滤与统计。",
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF5A5F52)
        )

        Spacer(Modifier.height(8.dp))

        OutlinedTextField(
            value = host,
            onValueChange = { host = it },
            label = { Text("路由器地址") },
            placeholder = { Text("192.168.1.1") },
            singleLine = true,
            colors = loginFieldColors(),
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = port,
            onValueChange = { port = it.filter { ch -> ch.isDigit() }.take(5) },
            label = { Text("端口") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            colors = loginFieldColors(),
            modifier = Modifier.fillMaxWidth()
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("使用 HTTPS", style = MaterialTheme.typography.bodyMedium, color = Color.Black)
            Spacer(Modifier.weight(1f))
            Switch(checked = https, onCheckedChange = { https = it })
        }

        OutlinedTextField(
            value = user,
            onValueChange = { user = it },
            label = { Text("用户名") },
            singleLine = true,
            colors = loginFieldColors(),
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = pass,
            onValueChange = { pass = it },
            label = { Text("密码") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            colors = loginFieldColors(),
            modifier = Modifier.fillMaxWidth()
        )

        error?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFFB04A3A)
            )
        }

        Button(
            onClick = { submit() },
            enabled = !busy,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
        ) {
            if (busy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary
                )
                Spacer(Modifier.width(10.dp))
                Text("连接中")
            } else {
                Text("连接")
            }
        }

        Text(
            text = "账号密码用于登录路由器 LuCI，保存在系统加密存储中。",
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF5A5F52)
        )

        OutlinedButton(
            onClick = onClientOnly,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
            border = BorderStroke(1.dp, Color(0xFF4F7D3A)),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = Color(0xFFE9F0DF),
                contentColor = Color(0xFF2F3B2A)
            )
        ) {
            Text("仅使用手机端过滤（不连接路由器）")
        }
    }
}

@Composable
private fun loginFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Color.Black,
    unfocusedTextColor = Color.Black,
    focusedContainerColor = Color.Transparent,
    unfocusedContainerColor = Color.Transparent,
    cursorColor = Color.Black,
    focusedLabelColor = Color.Black,
    unfocusedLabelColor = Color.Black,
    focusedPlaceholderColor = Color.Black,
    unfocusedPlaceholderColor = Color.Black,
    focusedBorderColor = Color(0xFF4F7D3A),
    unfocusedBorderColor = Color(0xFFC9BDA1)
)
