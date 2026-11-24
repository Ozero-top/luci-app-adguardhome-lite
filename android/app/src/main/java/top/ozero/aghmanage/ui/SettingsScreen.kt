package top.ozero.aghmanage.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.data.AghClient
import top.ozero.aghmanage.data.SettingsData

private data class SettingsForm(
    val enabled: Boolean,
    val dnsMode: String,
    val webPort: String,
    val binPath: String,
    val workDir: String,
    val channel: String,
    val githubProxy: String,
    val cacheEnabled: Boolean,
    val cacheSizeMb: String,
    val cacheTtlMin: String,
    val cacheTtlMax: String,
    val cacheOptimistic: Boolean,
    val dnsCrypto: String,
    val dnsCryptoCustom: String,
    val upstreamSource: String,
    val upstreamCustom: String,
    val bypassIfaces: String,
    val bypassClients: String,
    val statsDays: String,
    val queryDays: String
) {
    fun toParams(): Map<String, String> = mapOf(
        "enabled" to if (enabled) "1" else "0",
        "dns_mode" to dnsMode,
        "webport" to webPort,
        "binpath" to binPath,
        "workdir" to workDir,
        "channel" to channel,
        "github_proxy" to githubProxy,
        "cache_enabled" to if (cacheEnabled) "1" else "0",
        "cache_size_mb" to cacheSizeMb,
        "cache_ttl_min" to cacheTtlMin,
        "cache_ttl_max" to cacheTtlMax,
        "cache_optimistic" to if (cacheOptimistic) "1" else "0",
        "dns_crypto" to dnsCrypto,
        "dns_crypto_custom" to dnsCryptoCustom,
        "upstream_source" to upstreamSource,
        "upstream_custom" to upstreamCustom,
        "bypass_ifaces" to bypassIfaces,
        "bypass_clients" to bypassClients
    )

    companion object {
        fun from(s: SettingsData) = SettingsForm(
            enabled = s.enabled,
            dnsMode = s.dnsMode,
            webPort = s.webPort.toString(),
            binPath = s.binPath,
            workDir = s.workDir,
            channel = s.channel,
            githubProxy = s.githubProxy,
            cacheEnabled = s.cacheEnabled,
            cacheSizeMb = s.cacheSizeMb.toString(),
            cacheTtlMin = s.cacheTtlMin.toString(),
            cacheTtlMax = s.cacheTtlMax.toString(),
            cacheOptimistic = s.cacheOptimistic,
            dnsCrypto = s.dnsCrypto.ifEmpty { "off" },
            dnsCryptoCustom = s.dnsCryptoCustom,
            upstreamSource = s.upstreamSource.ifEmpty { "auto" },
            upstreamCustom = s.upstreamCustom,
            bypassIfaces = s.bypassIfaces,
            bypassClients = s.bypassClients,
            statsDays = s.statsRetentionDays.toString(),
            queryDays = s.querylogRetentionDays.toString()
        )
    }
}

private class ChoiceSpec(
    val title: String,
    val options: List<Pair<String, String>>,
    val selected: String,
    val apply: (String) -> Unit
)

@Composable
fun SettingsScreen(client: AghClient) {
    var data by remember { mutableStateOf<SettingsData?>(null) }
    var form by remember { mutableStateOf<SettingsForm?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageIsError by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableStateOf(0) }
    var choices by remember { mutableStateOf<ChoiceSpec?>(null) }
    var pending by remember { mutableStateOf<PendingAction?>(null) }
    var yamlText by remember { mutableStateOf<String?>(null) }
    var yamlPath by remember { mutableStateOf("/etc/AdGuardHome.yaml") }
    val scope = rememberCoroutineScope()
    val feedback = rememberFeedback()

    LaunchedEffect(message, messageIsError) {
        message?.let { feedback(it, messageIsError) }
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
                reloadKey++
            } catch (e: Exception) {
                message = e.message ?: "操作失败"
                messageIsError = true
            } finally {
                busy = false
            }
        }
    }

    LaunchedEffect(reloadKey) {
        try {
            val fetched = withContext(Dispatchers.IO) { client.fetchSettings() }
            data = fetched
            form = SettingsForm.from(fetched)
            yamlPath = fetched.configPath
            loadError = null
        } catch (e: Exception) {
            loadError = e.message ?: "读取设置失败"
        }
    }

    val current = data
    val f = form

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            ScreenTitle(
                title = "设置",
                subtitle = current?.let { if (it.running) "服务运行中" else "服务未运行" } ?: "读取中…",
                trailing = { TextButton(onClick = { reloadKey++ }) { Text("刷新") } }
            )
        }
        if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        item { NoticeText(loadError, error = true) }
        item { NoticeText(message, error = messageIsError) }

        if (f == null) {
            item { SectionCard { Text("正在读取设置…", style = MaterialTheme.typography.bodyMedium) } }
        } else {
            item {
                SectionCard("基础设置") {
                    SwitchRow("启用服务", f.enabled) { v -> form = f.copy(enabled = v) }
                    NumberField("Web 端口（1-65535）", f.webPort) { v -> form = f.copy(webPort = v) }
                    ChoiceRow("DNS 接管方式", dnsModeLabel(f.dnsMode)) {
                        choices = ChoiceSpec(
                            "DNS 接管方式",
                            listOf(
                                "takeover" to "接管 53 端口",
                                "passwall" to "PassWall 前置",
                                "clashfirst" to "Clash 前置",
                                "upstream" to "DNSMasq 上游",
                                "none" to "仅面板"
                            ),
                            f.dnsMode
                        ) { v -> form = f.copy(dnsMode = v) }
                    }
                    ChoiceRow("内核位置", f.binPath) {
                        choices = ChoiceSpec(
                            "内核位置",
                            listOf(
                                "/usr/bin/AdGuardHome/AdGuardHome" to "闪存（重启保留）",
                                "/tmp/AdGuardHome/AdGuardHome" to "内存（重启丢失）"
                            ),
                            f.binPath
                        ) { v -> form = f.copy(binPath = v) }
                    }
                    ChoiceRow("工作目录", f.workDir) {
                        choices = ChoiceSpec(
                            "工作目录",
                            listOf(
                                "/etc/AdGuardHome" to "闪存目录",
                                "/tmp/AdGuardHome" to "临时目录"
                            ),
                            f.workDir
                        ) { v -> form = f.copy(workDir = v) }
                    }
                    ChoiceRow("更新通道", channelLabel(f.channel)) {
                        choices = ChoiceSpec(
                            "更新通道",
                            listOf("stable" to "正式版", "beta" to "预发布版", "legacy" to "旧版本"),
                            f.channel
                        ) { v -> form = f.copy(channel = v) }
                    }
                    ChoiceRow("GitHub 反代", proxyLabel(f.githubProxy)) {
                        choices = ChoiceSpec(
                            "GitHub 反代",
                            listOf(
                                "none" to "不使用",
                                "gh-proxy.org" to "gh-proxy.org",
                                "ghproxy.cc" to "ghproxy.cc",
                                "ghproxy.com" to "ghproxy.com",
                                "ghfast.top" to "ghfast.top"
                            ),
                            f.githubProxy
                        ) { v -> form = f.copy(githubProxy = v) }
                    }
                }
            }

            item {
                SectionCard("DNS 缓存") {
                    SwitchRow("启用缓存", f.cacheEnabled) { v -> form = f.copy(cacheEnabled = v) }
                    NumberField("缓存大小（1-256 MB）", f.cacheSizeMb) { v -> form = f.copy(cacheSizeMb = v) }
                    NumberField("最小 TTL（秒，0 表示不限制）", f.cacheTtlMin) { v -> form = f.copy(cacheTtlMin = v) }
                    NumberField("最大 TTL（秒，0 表示不限制）", f.cacheTtlMax) { v -> form = f.copy(cacheTtlMax = v) }
                    SwitchRow("乐观缓存", f.cacheOptimistic) { v -> form = f.copy(cacheOptimistic = v) }
                }
            }

            item {
                SectionCard("上游 DNS") {
                    ChoiceRow("加密上游", cryptoLabel(f.dnsCrypto)) {
                        choices = ChoiceSpec(
                            "加密上游",
                            listOf(
                                "off" to "关闭",
                                "alidns" to "阿里 DoH",
                                "dnspod" to "DNSPod DoH",
                                "cloudflare" to "Cloudflare DoH",
                                "custom" to "自定义"
                            ),
                            f.dnsCrypto
                        ) { v -> form = f.copy(dnsCrypto = v) }
                    }
                    if (f.dnsCrypto == "custom") {
                        OutlinedTextField(
                            value = f.dnsCryptoCustom,
                            onValueChange = { v -> form = f.copy(dnsCryptoCustom = v) },
                            label = { Text("自定义加密上游") },
                            placeholder = { Text("https:// 或 tls:// 或 quic:// 或 sdns://") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    if (current?.cryptoBlocked == true) {
                        Text(
                            text = "当前上游由自定义设置管理，加密预设不会生效。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    if (current != null && current.upstreamCurrent.isNotEmpty()) {
                        InfoRow("当前上游", current.upstreamCurrent)
                    }
                    ChoiceRow("上游来源", if (f.upstreamSource == "custom") "自定义" else "自动") {
                        choices = ChoiceSpec(
                            "上游来源",
                            listOf("auto" to "自动（插件管理）", "custom" to "自定义"),
                            f.upstreamSource
                        ) { v -> form = f.copy(upstreamSource = v) }
                    }
                    if (f.upstreamSource == "custom") {
                        OutlinedTextField(
                            value = f.upstreamCustom,
                            onValueChange = { v -> form = f.copy(upstreamCustom = v) },
                            label = { Text("自定义上游 DNS（空格分隔）") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }

            item {
                SectionCard("直连排除") {
                    Text(
                        text = "这些接口 / 客户端不经过 AdGuard Home，通常用于旁路由或特殊设备。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = f.bypassIfaces,
                        onValueChange = { v -> form = f.copy(bypassIfaces = v) },
                        label = { Text("排除接口（空格分隔）") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("br-lan eth0") }
                    )
                    OutlinedTextField(
                        value = f.bypassClients,
                        onValueChange = { v -> form = f.copy(bypassClients = v) },
                        label = { Text("排除客户端（空格分隔）") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("192.168.1.10 192.168.1.0/24") }
                    )
                    if (current != null && current.devices.isNotEmpty()) {
                        Text(
                            text = "可用接口：" + current.devices.joinToString("  "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            item {
                SectionCard("数据保留") {
                    NumberField("统计保留天数（1-3650）", f.statsDays) { v -> form = f.copy(statsDays = v) }
                    NumberField("查询日志保留天数（1-3650）", f.queryDays) { v -> form = f.copy(queryDays = v) }
                    OutlinedButton(
                        onClick = {
                            perform("保留周期已保存") {
                                client.saveRetention(f.statsDays.toIntOrNull() ?: 30, f.queryDays.toIntOrNull() ?: 30)
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("保存保留周期")
                    }
                }
            }

            item {
                Button(
                    onClick = {
                        pending = PendingAction(
                            title = "保存设置",
                            text = "将写入并应用配置，DNS 服务可能会短暂重启。确定继续？",
                            confirmLabel = "保存"
                        ) {
                            perform("设置已保存") { client.saveSettings(f.toParams()) }
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("保存设置")
                }
            }

            item {
                SectionCard("配置文件 YAML") {
                    InfoRow("路径", yamlPath)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = {
                                perform("配置文件已加载") {
                                    val yaml = withContext(Dispatchers.IO) { client.fetchYaml() }
                                    yamlText = yaml.yaml
                                    yamlPath = yaml.path
                                }
                            },
                            enabled = !busy,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("加载 YAML")
                        }
                        OutlinedButton(
                            onClick = { yamlText = null },
                            enabled = yamlText != null,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("收起")
                        }
                    }
                    val text = yamlText
                    if (text != null) {
                        OutlinedTextField(
                            value = text,
                            onValueChange = { yamlText = it },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 12,
                            textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)
                        )
                        Button(
                            onClick = {
                                val body = yamlText
                                if (body != null) {
                                    pending = PendingAction(
                                        title = "保存 YAML",
                                        text = "保存前会执行 --check-config 校验，校验通过后写入并重启服务。确定继续？",
                                        confirmLabel = "保存"
                                    ) {
                                        perform("配置文件已保存") { client.saveYaml(body) }
                                    }
                                }
                            },
                            enabled = !busy,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("校验并保存 YAML")
                        }
                    }
                }
            }

            item {
                Text(
                    text = "配置路径：${current?.configPath ?: "-"}\n面板账号：${current?.adminUser ?: "-"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    choices?.let { spec ->
        ChoiceDialog(spec.title, spec.options, spec.selected, spec.apply) { choices = null }
    }

    pending?.let { p -> ConfirmDialog(p) { pending = null } }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun ChoiceRow(label: String, value: String, onClick: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.weight(1f))
        TextButton(onClick = onClick) { Text(value) }
    }
}

@Composable
private fun NumberField(label: String, value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = { input -> onValueChange(input.filter { it.isDigit() }.take(7)) },
        label = { Text(label) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
}

private fun channelLabel(value: String): String = when (value) {
    "beta" -> "预发布版"
    "legacy" -> "旧版本"
    else -> "正式版"
}

private fun proxyLabel(value: String): String = when (value) {
    "", "none" -> "不使用"
    else -> value
}

private fun cryptoLabel(value: String): String = when (value) {
    "alidns" -> "阿里 DoH"
    "dnspod" -> "DNSPod DoH"
    "cloudflare" -> "Cloudflare DoH"
    "custom" -> "自定义"
    else -> "关闭"
}
