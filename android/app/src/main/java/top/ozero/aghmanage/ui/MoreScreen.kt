package top.ozero.aghmanage.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.data.AghClient
import top.ozero.aghmanage.data.DashboardStatus
import top.ozero.aghmanage.data.LegacyScan
import top.ozero.aghmanage.data.ProgressInfo

@Composable
fun MoreScreen(client: AghClient) {
    var status by remember { mutableStateOf<DashboardStatus?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageIsError by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var refreshKey by remember { mutableStateOf(0) }
    var pending by remember { mutableStateOf<PendingAction?>(null) }

    var watchCore by remember { mutableStateOf(false) }
    var coreProgress by remember { mutableStateOf<ProgressInfo?>(null) }
    var watchPlugin by remember { mutableStateOf(false) }
    var pluginProgress by remember { mutableStateOf<ProgressInfo?>(null) }

    var legacy by remember { mutableStateOf<LegacyScan?>(null) }
    var legacyNote by remember { mutableStateOf<String?>(null) }

    var newPass by remember { mutableStateOf("") }
    var confirmPass by remember { mutableStateOf("") }

    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val feedback = rememberFeedback()

    LaunchedEffect(message, messageIsError) {
        message?.let { feedback(it, messageIsError) }
    }
    val appVersion = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: ""
    }

    fun perform(success: String?, block: suspend () -> Unit) {
        if (busy) return
        busy = true
        message = null
        scope.launch {
            try {
                withContext(Dispatchers.IO) { block() }
                val text = success ?: message
                if (text != null) message = text
                messageIsError = false
                refreshKey++
            } catch (e: Exception) {
                message = e.message ?: "操作失败"
                messageIsError = true
            } finally {
                busy = false
            }
        }
    }

    LaunchedEffect(refreshKey) {
        while (true) {
            try {
                status = withContext(Dispatchers.IO) { client.fetchStatus() }
                loadError = null
            } catch (e: Exception) {
                loadError = e.message ?: "请求失败"
            }
            delay(10000)
        }
    }

    LaunchedEffect(watchCore) {
        if (!watchCore) return@LaunchedEffect
        delay(1500)
        repeat(120) {
            val info = withContext(Dispatchers.IO) {
                runCatching { client.coreProgress() }.getOrNull()
            }
            if (info != null) coreProgress = info
            if (info == null) {
                delay(2000)
                return@repeat
            }
            if (!info.running) {
                watchCore = false
                refreshKey++
                return@LaunchedEffect
            }
            delay(2000)
        }
        watchCore = false
    }

    LaunchedEffect(watchPlugin) {
        if (!watchPlugin) return@LaunchedEffect
        delay(1500)
        repeat(120) {
            val info = withContext(Dispatchers.IO) {
                runCatching { client.pluginProgress() }.getOrNull()
            }
            if (info != null) pluginProgress = info
            if (info == null) {
                delay(2000)
                return@repeat
            }
            if (!info.running) {
                watchPlugin = false
                refreshKey++
                return@LaunchedEffect
            }
            delay(2000)
        }
        watchPlugin = false
    }

    val s = status

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            ScreenTitle(
                title = "更多",
                subtitle = "内核、插件与维护",
                trailing = { TextButton(onClick = { refreshKey++ }) { Text("刷新") } }
            )
        }
        if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        item { NoticeText(loadError, error = true) }
        item { NoticeText(message, error = messageIsError) }

        item {
            SectionCard("内核") {
                InfoRow("已安装", if (s?.coreInstalled == true) "是" else "否")
                InfoRow("当前版本", s?.coreVersion?.ifEmpty { "未安装" } ?: "-")
                InfoRow("最新版本", s?.coreLatest?.ifEmpty { "未知" } ?: "未知")
                if (s != null && s.updateRunning) {
                    Text(
                        text = "内核更新任务运行中…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                Button(
                    onClick = {
                        pending = PendingAction(
                            title = if (s?.coreInstalled == true) "更新内核" else "安装内核",
                            text = "将从网络下载 AdGuard Home 内核，过程中会短暂中断 DNS 服务。确定继续？",
                            confirmLabel = "开始"
                        ) {
                            perform("已启动内核任务") { client.installCore() }
                            watchCore = true
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (s?.coreInstalled == true) "安装 / 更新内核" else "安装内核")
                }
                coreProgress?.let { info ->
                    ProgressCard("内核任务日志", info)
                }
            }
        }

        item {
            SectionCard("插件") {
                InfoRow("当前版本", s?.pluginVersion?.ifEmpty { "未知" } ?: "-")
                InfoRow("最新版本", s?.pluginLatest?.ifEmpty { "未知" } ?: "未知")
                if (s != null && s.pluginUpdate) {
                    Text(
                        text = "有新版本可更新",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            perform(null) {
                                val result = client.pluginCheck()
                                var current = result.current
                                var latest = result.latest
                                var update = result.update
                                var tries = 0
                                while (latest.isEmpty() && tries < 10) {
                                    delay(2000)
                                    val st = client.fetchStatus()
                                    current = st.pluginVersion
                                    latest = st.pluginLatest
                                    update = st.pluginUpdate
                                    tries++
                                }
                                message = when {
                                    latest.isNotEmpty() && update ->
                                        "发现新版本 ${versionLabel(latest)}"
                                    latest.isNotEmpty() ->
                                        "已是最新版本 ${versionLabel(current.ifEmpty { latest })}"
                                    else ->
                                        "检查已发起，暂未获取到最新版本，请稍后查看"
                                }
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("检查更新")
                    }
                    Button(
                        onClick = {
                            val latest = s?.pluginLatest.orEmpty()
                            pending = PendingAction(
                                title = "更新插件",
                                text = "将更新到 v$latest，更新过程中管理页面可能短暂不可用。确定继续？",
                                confirmLabel = "更新"
                            ) {
                                perform("已启动插件更新") {
                                    client.pluginUpdate(latest, force = false, channel = "cn", method = "source")
                                }
                                watchPlugin = true
                            }
                        },
                        enabled = !busy && !s?.pluginLatest.isNullOrEmpty() && s?.pluginUpdate == true,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("更新插件")
                    }
                }
                pluginProgress?.let { info ->
                    ProgressCard("插件任务日志", info)
                }
            }
        }

        item {
            SectionCard("管理面板密码") {
                Text(
                    text = "修改的是 AdGuard Home 面板的管理密码，不影响手机连接路由器使用的 LuCI 账号。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedTextField(
                    value = newPass,
                    onValueChange = { newPass = it },
                    label = { Text("新密码（至少 8 位）") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = confirmPass,
                    onValueChange = { confirmPass = it },
                    label = { Text("确认新密码") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = {
                        val pass = newPass
                        if (pass.length < 8) {
                            message = "新密码至少需要 8 个字符"
                            messageIsError = true
                            return@Button
                        }
                        if (pass != confirmPass) {
                            message = "两次输入的密码不一致"
                            messageIsError = true
                            return@Button
                        }
                        pending = PendingAction(
                            title = "修改面板密码",
                            text = "修改后需要使用新密码登录 AdGuard Home 面板。确定继续？",
                            confirmLabel = "修改"
                        ) {
                            perform("面板密码已更新") { client.changePassword(pass) }
                            newPass = ""
                            confirmPass = ""
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("修改密码")
                }
            }
        }

        item {
            SectionCard("旧版残留") {
                Text(
                    text = "扫描旧版 AdGuard Home 插件留下的文件与内核，清理前会自动备份。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                legacyNote?.let { NoticeText(it) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            perform("扫描完成") {
                                legacy = withContext(Dispatchers.IO) { client.scanLegacy() }
                                legacyNote = null
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("扫描")
                    }
                    Button(
                        onClick = {
                            pending = PendingAction(
                                title = "清理旧版残留",
                                text = "将删除扫描到的旧插件文件与旧内核，并备份到 /etc/adguardhome_lite。确定继续？",
                                confirmLabel = "清理",
                                destructive = true
                            ) {
                                perform("清理完成") {
                                    val result = client.cleanLegacy()
                                    legacy = null
                                    legacyNote = "已删除 ${result.removed} 项，备份位置：${result.backup}"
                                }
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("清理")
                    }
                }
                legacy?.let { scan ->
                    if (scan.items.isEmpty()) {
                        Text(
                            text = "未发现旧版残留",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        Text(
                            text = "发现 ${scan.count} 项：",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        scan.items.forEach { item ->
                            Column {
                                Text(
                                    text = "${item.name}（${item.kind}）",
                                    style = MaterialTheme.typography.bodyMedium
                                )
                                Text(
                                    text = item.path,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                if (item.note.isNotEmpty()) {
                                    Text(
                                        text = item.note,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        item {
            SectionCard("关于") {
                InfoRow("应用版本", appVersion.ifEmpty { "-" })
                Text(
                    text = "本应用包含路由器插件管理与客户端过滤。客户端过滤只接管 DNS，可在登录页进入客户端过滤后开启或暂停。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    pending?.let { p -> ConfirmDialog(p) { pending = null } }
}

@Composable
private fun ProgressCard(title: String, info: ProgressInfo) {
    Text(
        text = title + if (info.running) " · 进行中" else " · 已结束",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Card(Modifier.fillMaxWidth().height(200.dp)) {
        SelectionContainer {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(10.dp)
            ) {
                Text(
                    text = info.log.ifEmpty { "暂无日志" },
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.sp,
                    lineHeight = 14.sp
                )
            }
        }
    }
}

private fun versionLabel(value: String): String =
    if (value.isEmpty() || value.startsWith("v")) value else "v$value"
