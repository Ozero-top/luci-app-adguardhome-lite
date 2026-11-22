package top.ozero.aghmanage.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.client.AghVpnService
import top.ozero.aghmanage.client.AppList
import top.ozero.aghmanage.client.BlockLog
import top.ozero.aghmanage.client.BlockedEntry
import top.ozero.aghmanage.client.ClientPrefs
import top.ozero.aghmanage.client.ClientState
import top.ozero.aghmanage.client.InstalledApp
import top.ozero.aghmanage.client.RuleStore
import top.ozero.aghmanage.client.RuleUpdater

@Composable
fun ClientScreen(onBack: (() -> Unit)? = null) {
    val context = LocalContext.current
    val prefs = remember { ClientPrefs(context) }
    val state by ClientState.flow.collectAsState()
    val scope = rememberCoroutineScope()

    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageIsError by remember { mutableStateOf(false) }
    var upstream by remember { mutableStateOf(prefs.upstream) }
    var updating by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf("") }

    var autoStart by remember { mutableStateOf(prefs.autoStart) }
    var splitMode by remember { mutableStateOf(prefs.splitMode) }
    var selectedApps by remember { mutableStateOf(prefs.selectedApps) }
    var showAppPicker by remember { mutableStateOf(false) }
    var apps by remember { mutableStateOf<List<InstalledApp>>(emptyList()) }
    var appsLoaded by remember { mutableStateOf(false) }
    var appsLoading by remember { mutableStateOf(false) }
    var appQuery by remember { mutableStateOf("") }
    var draftSelection by remember { mutableStateOf<Set<String>>(emptySet()) }
    var blockLog by remember { mutableStateOf<List<BlockedEntry>>(emptyList()) }
    var logPage by remember { mutableStateOf(0) }
    val feedback = rememberFeedback()

    LaunchedEffect(message, messageIsError) {
        message?.let { feedback(it, messageIsError) }
    }

    LaunchedEffect(Unit) {
        while (true) {
            blockLog = withContext(Dispatchers.IO) { BlockLog.snapshot(context) }
            delay(2000)
        }
    }

    fun startClient() {
        val intent = Intent(context, AghVpnService::class.java)
            .setAction(AghVpnService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        message = "正在开启手机端过滤…"
        messageIsError = false
    }

    val vpnLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            startClient()
        } else {
            message = "未授予 VPN 权限，无法开启手机端过滤"
            messageIsError = true
        }
    }

    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    fun enableClient() {
        val prepare = VpnService.prepare(context)
        if (prepare != null) {
            vpnLauncher.launch(prepare)
        } else {
            startClient()
        }
    }

    fun stopClient() {
        context.startService(
            Intent(context, AghVpnService::class.java).setAction(AghVpnService.ACTION_STOP)
        )
        message = "已停止手机端过滤"
        messageIsError = false
    }

    fun togglePause() {
        context.startService(
            Intent(context, AghVpnService::class.java).setAction(AghVpnService.ACTION_TOGGLE_PAUSE)
        )
    }

    fun updateRules() {
        if (updating) return
        updating = true
        message = null
        scope.launch {
            val result = RuleUpdater.update(context) { progress = it }
            result.onSuccess {
                message = "规则已更新，共 ${RuleStore.count} 条"
                messageIsError = false
            }.onFailure {
                message = it.message ?: "规则更新失败"
                messageIsError = true
            }
            updating = false
            progress = ""
            ClientState.update { it.copy(rules = RuleStore.count) }
        }
    }

    fun saveUpstream() {
        val servers = upstream.split(',', ' ', ';')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val valid = servers.isNotEmpty() && servers.all {
            it.matches(Regex("^\\d{1,3}(\\.\\d{1,3}){3}$"))
        }
        if (!valid) {
            message = "上游 DNS 必须是 IPv4 地址，多个用逗号分隔"
            messageIsError = true
            return
        }
        prefs.upstream = servers.joinToString(", ")
        upstream = prefs.upstream
        message = "上游 DNS 已保存"
        messageIsError = false
    }

    fun restartFilterIfRunning() {
        if (ClientState.snapshot().running) {
            context.startService(
                Intent(context, AghVpnService::class.java)
                    .setAction(AghVpnService.ACTION_RESTART)
            )
        }
    }

    fun changeSplitMode(mode: String) {
        splitMode = mode
        prefs.splitMode = mode
        restartFilterIfRunning()
        message = "应用分流已应用"
        messageIsError = false
    }

    fun openAppPicker() {
        draftSelection = selectedApps
        appQuery = ""
        showAppPicker = true
    }

    fun saveApps() {
        prefs.selectedApps = draftSelection
        selectedApps = draftSelection
        showAppPicker = false
        restartFilterIfRunning()
        message = "已选择 ${draftSelection.size} 个应用"
        messageIsError = false
    }

    LaunchedEffect(Unit) {
        if (ClientState.snapshot().rules == 0) {
            withContext(Dispatchers.IO) { RuleStore.load(context) }
        }
        ClientState.update {
            it.copy(
                rules = RuleStore.count,
                blocked = maxOf(it.blocked, prefs.blockedTotal),
                pausedUntil = prefs.pausedUntil
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }

    LaunchedEffect(showAppPicker) {
        if (showAppPicker && !appsLoaded) {
            appsLoading = true
            apps = withContext(Dispatchers.IO) { AppList.launcherApps(context) }
            appsLoaded = true
            appsLoading = false
        }
    }

    val paused = state.isPaused(now)
    val remaining = ((state.pausedUntil - now) / 1000).coerceAtLeast(0)

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (onBack != null) {
            item {
                TextButton(onClick = onBack) { Text("← 返回登录") }
            }
        }

        item {
            ScreenTitle(
                title = "手机端过滤",
                subtitle = "仅接管手机 DNS，不代理其它流量"
            )
        }

        item { NoticeText(message, error = messageIsError) }

        item {
            SectionCard("运行状态") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = if (state.running) "过滤已开启" else "过滤已关闭",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = if (state.running) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            text = when {
                                paused -> "暂停中，${remaining} 秒后自动恢复"
                                state.running -> "通知栏或快捷磁贴可暂停 30 秒"
                                else -> "开启后使用手机端规则拦截广告域名"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = state.running,
                        onCheckedChange = { on -> if (on) enableClient() else stopClient() }
                    )
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))

                InfoRow("已拦截", formatNumber(state.blocked))
                InfoRow("规则条数", formatNumber(state.rules.toLong()))

                if (state.running) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = { togglePause() },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(if (paused) "继续过滤" else "暂停 30 秒")
                        }
                        OutlinedButton(
                            onClick = { stopClient() },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("停止")
                        }
                    }
                }
            }
        }

        item {
            SectionCard("应用分流") {
                ChoiceChips(
                    label = "分流方式",
                    options = listOf(
                        ClientPrefs.SPLIT_ALL to "全部应用",
                        ClientPrefs.SPLIT_ALLOW to "仅选中应用",
                        ClientPrefs.SPLIT_DENY to "排除选中应用"
                    ),
                    selected = splitMode
                ) { mode -> changeSplitMode(mode) }

                Text(
                    text = when (splitMode) {
                        ClientPrefs.SPLIT_ALLOW -> "只有选中的应用使用手机端过滤，其余应用直连。"
                        ClientPrefs.SPLIT_DENY -> "选中的应用直连，不使用手机端过滤。"
                        else -> "所有应用都使用手机端过滤。"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                if (splitMode != ClientPrefs.SPLIT_ALL) {
                    InfoRow("已选应用", "${selectedApps.size} 个")
                    if (selectedApps.isEmpty()) {
                        Text(
                            text = "尚未选择应用，当前按「全部应用」处理。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    OutlinedButton(
                        onClick = { openAppPicker() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("选择应用")
                    }
                }
                Text(
                    text = "修改后会自动重启过滤使其生效。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            SectionCard("开机自启") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("开机后自动开启手机端过滤", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            text = "需已授权 VPN，且关机前处于开启状态。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = autoStart,
                        onCheckedChange = {
                            autoStart = it
                            prefs.autoStart = it
                        }
                    )
                }
            }
        }

        item {
            SectionCard("过滤规则") {
                Text(
                    text = "更新使用六类规则：安全防护、中文广告、全站广告、跟踪统计、网页干扰、外语分区。内置基础清单可离线使用。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                InfoRow("当前规则", "${formatNumber(state.rules.toLong())} 条")
                InfoRow("上次更新", formatTime(prefs.lastUpdate))

                if (updating) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    if (progress.isNotEmpty()) {
                        Text(
                            text = progress,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Button(
                    onClick = { updateRules() },
                    enabled = !updating,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (updating) "正在更新…" else "更新规则")
                }
                if (state.updateMessage.isNotEmpty()) {
                    Text(
                        text = state.updateMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }

        item {
            SectionCard("拦截日志") {
                Text(
                    text = "仅记录手机端过滤拦截的请求，最多保留 300 条。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (blockLog.isEmpty()) {
                    Text(
                        text = "暂无拦截记录",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "共 ${blockLog.size} 条",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Spacer(Modifier.weight(1f))
                        TextButton(
                            onClick = {
                                scope.launch {
                                    withContext(Dispatchers.IO) { BlockLog.clear(context) }
                                    blockLog = emptyList()
                                    logPage = 0
                                }
                            }
                        ) {
                            Text("清空")
                        }
                    }
                    val pageSize = 15
                    val pageCount = ((blockLog.size + pageSize - 1) / pageSize).coerceAtLeast(1)
                    val currentPage = logPage.coerceIn(0, pageCount - 1)
                    blockLog.drop(currentPage * pageSize).take(pageSize).forEach { entry ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 3.dp),
                            verticalAlignment = Alignment.Top
                        ) {
                            Text(
                                text = formatClock(entry.time),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.width(58.dp)
                            )
                            Column(Modifier.weight(1f)) {
                                Text(
                                    text = entry.domain,
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = entry.qtype,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f)
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedButton(
                            onClick = { logPage = currentPage - 1 },
                            enabled = currentPage > 0
                        ) {
                            Text("上一页")
                        }
                        Text(
                            text = "第 ${currentPage + 1} / $pageCount 页",
                            modifier = Modifier.weight(1f),
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        OutlinedButton(
                            onClick = { logPage = currentPage + 1 },
                            enabled = currentPage < pageCount - 1
                        ) {
                            Text("下一页")
                        }
                    }
                }
            }
        }

        item {
            SectionCard("上游 DNS") {
                OutlinedTextField(
                    value = upstream,
                    onValueChange = { upstream = it },
                    label = { Text("上游 DNS（IPv4，逗号分隔）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = { saveUpstream() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("保存上游 DNS")
                }
            }
        }

        item {
            SectionCard("说明") {
                listOf(
                    "仅 DNS 流量经过手机 VPN，网页与应用流量仍走原网络。",
                    "浏览器开启安全 DNS（DoH）或应用内置 DoH 时，查询会绕过手机端过滤。",
                    "系统「私人 DNS」设为自动或指定 DoT 时也可能绕过过滤，建议设为关闭。",
                    "开启后状态栏会出现 VPN 图标，这是 Android 对本地 VPN 的提示。"
                ).forEach {
                    Text(
                        text = "• $it",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        item { Spacer(Modifier.padding(bottom = 4.dp)) }
    }

    if (showAppPicker) {
        val filtered = remember(apps, appQuery) {
            val query = appQuery.trim().lowercase()
            if (query.isEmpty()) {
                apps
            } else {
                apps.filter {
                    it.label.lowercase().contains(query) ||
                        it.packageName.lowercase().contains(query)
                }
            }
        }
        AlertDialog(
            onDismissRequest = { showAppPicker = false },
            title = { Text("选择应用") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = appQuery,
                        onValueChange = { appQuery = it },
                        label = { Text("搜索应用") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (appsLoading) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text(
                                text = "正在读取应用列表…",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                    LazyColumn(Modifier.height(320.dp)) {
                        items(filtered, key = { it.packageName }) { app ->
                            val checked = app.packageName in draftSelection
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        draftSelection = if (checked) {
                                            draftSelection - app.packageName
                                        } else {
                                            draftSelection + app.packageName
                                        }
                                    }
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = checked,
                                    onCheckedChange = { on ->
                                        draftSelection = if (on) {
                                            draftSelection + app.packageName
                                        } else {
                                            draftSelection - app.packageName
                                        }
                                    }
                                )
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        text = app.label,
                                        style = MaterialTheme.typography.bodyMedium,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        text = app.packageName,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { saveApps() }) {
                    Text("确定（${draftSelection.size}）")
                }
            },
            dismissButton = {
                TextButton(onClick = { showAppPicker = false }) { Text("取消") }
            }
        )
    }
}

private fun formatTime(timestamp: Long): String {
    if (timestamp <= 0) return "从未更新"
    return SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(timestamp))
}

private fun formatClock(timestamp: Long): String =
    SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(timestamp))
