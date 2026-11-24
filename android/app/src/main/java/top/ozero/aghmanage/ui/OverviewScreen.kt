package top.ozero.aghmanage.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.data.AghClient
import top.ozero.aghmanage.data.DashboardStatus
import top.ozero.aghmanage.data.SelfTestResult

@Composable
fun OverviewScreen(client: AghClient, onLogout: () -> Unit) {
    var status by remember { mutableStateOf<DashboardStatus?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageIsError by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var refreshKey by remember { mutableStateOf(0) }
    var selfTest by remember { mutableStateOf<SelfTestResult?>(null) }
    var pending by remember { mutableStateOf<PendingAction?>(null) }
    var showChannel by remember { mutableStateOf(false) }
    var coreLog by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val feedback = rememberFeedback()

    LaunchedEffect(message, messageIsError) {
        message?.let { feedback(it, messageIsError) }
    }

    LaunchedEffect(refreshKey) {
        while (true) {
            try {
                status = withContext(Dispatchers.IO) { client.fetchStatus() }
                loadError = null
            } catch (e: Exception) {
                loadError = e.message ?: "请求失败"
            }
            delay(5000)
        }
    }

    fun perform(success: String?, block: suspend () -> Unit) {
        if (busy) return
        busy = true
        message = null
        scope.launch {
            try {
                withContext(Dispatchers.IO) { block() }
                message = success
                messageIsError = false
            } catch (e: Exception) {
                message = e.message ?: "操作失败"
                messageIsError = true
            } finally {
                busy = false
                refreshKey++
            }
        }
    }

    fun switchChannel(target: String) {
        val label = channelLabel(target)
        val legacyHint = if (target == "legacy") {
            "旧版本可能无法读取已升级的配置，若没有兼容备份会自动取消安装。"
        } else {
            ""
        }
        pending = PendingAction(
            title = "切换到${label}内核",
            text = "将把更新通道改为${label}并下载安装该通道的最新内核（约 30MB），安装期间 DNS 会短暂中断。${legacyHint}确定继续？",
            confirmLabel = "开始切换"
        ) {
            coreLog = ""
            perform("内核已切换到$label") {
                val settings = withContext(Dispatchers.IO) { client.fetchSettings() }
                withContext(Dispatchers.IO) {
                    client.saveSettings(settings.toSaveParams(target))
                }
                delay(1500)
                withContext(Dispatchers.IO) { client.installCore() }

                var sawRunning = false
                var finished = false
                var exitCode: Int? = null
                repeat(180) {
                    if (finished) return@repeat
                    delay(2000)
                    val progress = withContext(Dispatchers.IO) {
                        runCatching { client.coreProgress() }.getOrNull()
                    } ?: return@repeat
                    coreLog = progress.log
                    if (progress.running) sawRunning = true
                    if (!progress.running && (sawRunning || progress.code != null)) {
                        finished = true
                        exitCode = progress.code
                    }
                }
                if (!finished) {
                    throw IllegalStateException("内核任务超时，请到「更多」页查看进度")
                }
                if (exitCode != null && exitCode != 0) {
                    throw IllegalStateException("内核安装失败（退出码 $exitCode），请查看日志")
                }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ScreenTitle(
            title = "AGHTools管理器",
            subtitle = status?.let {
                when {
                    it.running -> "服务运行中 · ${dnsModeLabel(it.dnsMode)}"
                    it.coreInstalled -> "服务已停止"
                    else -> "尚未安装内核"
                }
            } ?: "读取中…",
            trailing = { OutlinedButton(onClick = onLogout) { Text("退出") } }
        )

        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())

        NoticeText(loadError, error = true)
        NoticeText(message, error = messageIsError)

        val s = status
        if (s == null) {
            SectionCard { Text("正在连接路由器…", style = MaterialTheme.typography.bodyMedium) }
        } else {
            SectionCard("运行状态") {
                InfoRow("服务", if (s.running) "运行中" else "已停止")
                InfoRow("开机自启", if (s.enabled) "已开启" else "已关闭")
                InfoRow("DNS 接管", dnsModeLabel(s.dnsMode))
                InfoRow("DNS 端口", s.dnsPort.toString())
                InfoRow("面板端口", s.webPort.toString())
            }

            SectionCard("内核") {
                InfoRow("已安装", if (s.coreInstalled) "是" else "否")
                InfoRow("版本", s.coreVersion.ifEmpty { "未安装" })
                if (s.coreLatest.isNotEmpty()) {
                    InfoRow(
                        "最新版本",
                        s.coreLatest + if (s.coreUpdate) "（可更新）" else "",
                        valueColor = if (s.coreUpdate) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                    )
                }
                InfoRow("更新通道", channelLabel(s.channel))
                if (s.coreChannel.isNotEmpty() && s.coreChannel != s.channel) {
                    InfoRow("已安装通道", channelLabel(s.coreChannel))
                }
                OutlinedButton(
                    onClick = { showChannel = true },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("切换内核通道")
                }
            }

            if (coreLog.isNotEmpty()) {
                SectionCard("内核任务") {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(180.dp)
                    ) {
                        SelectionContainer {
                            Column(
                                Modifier
                                    .fillMaxSize()
                                    .verticalScroll(rememberScrollState())
                            ) {
                                Text(
                                    text = coreLog.takeLast(6000),
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 10.sp,
                                    lineHeight = 14.sp
                                )
                            }
                        }
                    }
                }
            }

            SectionCard("统计") {
                InfoRow("查询总数", formatNumber(s.queries))
                InfoRow("已拦截", formatNumber(s.blocked))
                InfoRow("拦截率", String.format("%.1f%%", s.blockedPercent))
                InfoRow("平均耗时", String.format("%.1f ms", s.avgMs * 1000))
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = {
                        val action = if (s.running) "stop" else "start"
                        if (s.running) {
                            pending = PendingAction(
                                title = "停止服务",
                                text = "停止后全屋 DNS 过滤会立即失效，确定继续？",
                                confirmLabel = "停止",
                                destructive = true
                            ) { perform("已停止服务") { client.serviceAction("stop") } }
                        } else {
                            perform("已提交启动请求") { client.serviceAction(action) }
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (s.running) "停止服务" else "启动服务")
                }
                OutlinedButton(
                    onClick = {
                        pending = PendingAction(
                            title = "重启服务",
                            text = "重启期间 DNS 会短暂不可用，确定继续？",
                            confirmLabel = "重启"
                        ) { perform("已提交重启请求") { client.serviceAction("restart") } }
                    },
                    enabled = !busy,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("重启服务")
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = {
                        pending = PendingAction(
                            title = "清空统计",
                            text = "将清空查询总数、拦截数与排行数据，无法撤销。",
                            confirmLabel = "清空",
                            destructive = true
                        ) { perform("统计已清空") { client.clearStats() } }
                    },
                    enabled = !busy,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("清空统计")
                }
                OutlinedButton(
                    onClick = {
                        perform(null) {
                            selfTest = withContext(Dispatchers.IO) { client.runSelfTest() }
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("运行自检")
                }
            }
        }

        selfTest?.let { result ->
            SectionCard("自检结果 · DNS 端口 ${result.dnsPort}") {
                Text(
                    text = if (result.ok) "全部通过" else "存在异常项",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = if (result.ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                )
                result.checks.forEach { check ->
                    Row(
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Box(
                            Modifier
                                .padding(top = 6.dp)
                                .size(8.dp)
                                .background(
                                    if (check.ok) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.error,
                                    CircleShape
                                )
                        )
                        Column(Modifier.weight(1f)) {
                            Text(check.label, style = MaterialTheme.typography.bodyMedium)
                            if (check.detail.isNotEmpty()) {
                                Text(
                                    text = check.detail,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(4.dp))

        OutlinedButton(
            onClick = { refreshKey++ },
            modifier = Modifier
                .fillMaxWidth()
                .height(44.dp)
        ) {
            Text("立即刷新")
        }
    }

    pending?.let { p ->
        ConfirmDialog(p) { pending = null }
    }

    if (showChannel) {
        val current = status?.channel ?: "stable"
        ChoiceDialog(
            title = "切换内核通道",
            options = listOf("stable" to "正式版", "beta" to "预发布版", "legacy" to "旧版本"),
            selected = current,
            onSelect = { target ->
                if (target != current) switchChannel(target)
            },
            onDismiss = { showChannel = false }
        )
    }
}

private fun channelLabel(value: String): String = when (value) {
    "beta" -> "预发布版"
    "legacy" -> "旧版本"
    else -> "正式版"
}
