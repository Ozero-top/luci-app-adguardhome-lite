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
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.data.AghClient
import top.ozero.aghmanage.data.FilterItem
import top.ozero.aghmanage.data.FiltersData

@Composable
fun RulesScreen(client: AghClient) {
    var data by remember { mutableStateOf<FiltersData?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageIsError by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableStateOf(0) }
    var pending by remember { mutableStateOf<PendingAction?>(null) }
    var showAdd by remember { mutableStateOf(false) }
    var addName by remember { mutableStateOf("") }
    var addUrl by remember { mutableStateOf("") }
    var addWhitelist by remember { mutableStateOf(false) }
    var rulesText by remember { mutableStateOf("") }
    var rulesInitialized by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val feedback = rememberFeedback()

    LaunchedEffect(message, messageIsError) {
        message?.let { feedback(it, messageIsError) }
    }

    suspend fun load() {
        try {
            val fetched = withContext(Dispatchers.IO) { client.fetchFilters() }
            data = fetched
            if (!rulesInitialized) {
                rulesText = fetched.userRules.joinToString("\n")
                rulesInitialized = true
            }
            loadError = null
        } catch (e: Exception) {
            loadError = e.message ?: "读取规则失败"
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
                reloadKey++
            }
        }
    }

    LaunchedEffect(reloadKey) { load() }

    val current = data

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            ScreenTitle(
                title = "过滤规则",
                subtitle = current?.let { "订阅 ${it.filters.size} 个 · 自定义 ${it.userRules.size} 条" }
                    ?: "读取中…",
                trailing = { TextButton(onClick = { reloadKey++ }) { Text("刷新") } }
            )
        }
        if (busy) {
            item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        }
        item { NoticeText(loadError, error = true) }
        item { NoticeText(message, error = messageIsError) }

        if (current == null) {
            item { SectionCard { Text("正在读取过滤规则…", style = MaterialTheme.typography.bodyMedium) } }
        } else {
            val adult = current.adultFilter()
            val adultOn = adult?.enabled == true
            item {
                SectionCard("功能开关") {
                    FeatureRow("过滤总开关", current.filteringEnabled, !busy) { on ->
                        perform("已更新") {
                            client.filterAction(feature("filtering", on))
                        }
                    }
                    FeatureRow("安全搜索", current.safeSearch, !busy) { on ->
                        perform("已更新") {
                            client.filterAction(feature("safesearch", on))
                        }
                    }
                    FeatureRow("家长控制", current.parental, !busy) { on ->
                        perform("已更新") {
                            if (on && adultOn) {
                                adult?.let { removeAdultFilter(client, it) }
                            }
                            client.filterAction(feature("parental", on))
                        }
                    }
                    FeatureRow("成人内容", adultOn, !busy) { on ->
                        perform("已更新") {
                            if (on && current.parental) {
                                client.filterAction(feature("parental", false))
                            }
                            if (on) {
                                enableAdultFilter(client, adult)
                            } else {
                                adult?.let { removeAdultFilter(client, it) }
                            }
                        }
                    }
                    Text(
                        text = "「成人内容」与「家长控制」互斥，开启一个会自动关闭另一个。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    FeatureRow("安全浏览", current.safeBrowsing, !busy) { on ->
                        perform("已更新") {
                            client.filterAction(feature("safebrowsing", on))
                        }
                    }
                }
            }

            item {
                SectionCard("预置规则档位") {
                    Text(
                        text = "按路由器内存选择内置规则组合，切换会自动添加 / 移除对应列表。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("512" to "512 MB", "1024" to "1 GB", "2048" to "2 GB").forEach { (tier, label) ->
                            OutlinedButton(
                                onClick = {
                                    pending = PendingAction(
                                        title = "切换预置档位",
                                        text = "将应用 $label 内存档的规则列表，并移除其它档位的内置列表。确定继续？",
                                        confirmLabel = "应用"
                                    ) {
                                        perform("档位已切换") {
                                            client.filterAction(mapOf("action" to "trim", "tier" to tier))
                                        }
                                    }
                                },
                                enabled = !busy,
                                modifier = Modifier.weight(1f)
                            ) {
                                Text(label)
                            }
                        }
                    }
                }
            }

            item {
                SectionCard("预置下载源") {
                    ChoiceChips(
                        label = "规则列表下载源",
                        options = listOf(
                            "jsdelivr" to "jsDelivr",
                            "github" to "GitHub 直连",
                            "custom" to "自建备用"
                        ),
                        selected = current.presetSource
                    ) { source ->
                        if (source != current.presetSource) {
                            pending = PendingAction(
                                title = "切换下载源",
                                text = "将把已有内置列表迁移到新下载源并重新下载，确定继续？",
                                confirmLabel = "切换"
                            ) {
                                perform("下载源已切换") {
                                    client.filterAction(mapOf("action" to "preset_source", "source" to source))
                                }
                            }
                        }
                    }
                }
            }

            if (current.filters.isNotEmpty()) {
                item {
                    Text(
                        text = "订阅列表",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold
                    )
                }
                items(current.filters, key = { "${it.whitelist}-${it.url}" }) { item ->
                    FilterCard(
                        item = item,
                        enabled = !busy,
                        onToggle = { checked ->
                            perform("已更新订阅") {
                                client.filterAction(mapOf(
                                    "action" to "toggle",
                                    "url" to item.url,
                                    "name" to item.name,
                                    "enabled" to if (checked) "1" else "0",
                                    "whitelist" to if (item.whitelist) "1" else "0"
                                ))
                            }
                        },
                        onRemove = {
                            pending = PendingAction(
                                title = "删除订阅",
                                text = "将删除「${item.name}」，确定继续？",
                                confirmLabel = "删除",
                                destructive = true
                            ) {
                                perform("已删除订阅") {
                                    client.filterAction(mapOf(
                                        "action" to "remove",
                                        "url" to item.url,
                                        "whitelist" to if (item.whitelist) "1" else "0"
                                    ))
                                }
                            }
                        }
                    )
                }
            }

            item {
                SectionCard("添加订阅") {
                    OutlinedButton(
                        onClick = { showAdd = true },
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("添加规则订阅")
                    }
                }
            }

            item {
                SectionCard("自定义规则") {
                    Text(
                        text = "每行一条，支持 AdGuard Home 过滤语法。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = rulesText,
                        onValueChange = { rulesText = it },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 6,
                        textStyle = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    )
                    Button(
                        onClick = {
                            pending = PendingAction(
                                title = "保存自定义规则",
                                text = "将用当前编辑框内容覆盖 AdGuard Home 的自定义规则列表。确定继续？",
                                confirmLabel = "保存"
                            ) {
                                perform("自定义规则已保存") {
                                    client.filterAction(mapOf("action" to "rules", "rules" to rulesText))
                                }
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("保存自定义规则")
                    }
                }
            }
        }
    }

    pending?.let { p -> ConfirmDialog(p) { pending = null } }

    if (showAdd) {
        AlertDialog(
            onDismissRequest = { showAdd = false },
            title = { Text("添加订阅") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = addName,
                        onValueChange = { addName = it },
                        label = { Text("名称（可留空）") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = addUrl,
                        onValueChange = { addUrl = it },
                        label = { Text("订阅地址") },
                        placeholder = { Text("https://…") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("加入白名单", style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.weight(1f))
                        Switch(checked = addWhitelist, onCheckedChange = { addWhitelist = it })
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = addUrl.isNotBlank() && !busy,
                    onClick = {
                        val url = addUrl.trim()
                        val name = addName.trim()
                        val whitelist = addWhitelist
                        showAdd = false
                        addName = ""
                        addUrl = ""
                        addWhitelist = false
                        perform("已添加订阅") {
                            client.filterAction(mapOf(
                                "action" to "add",
                                "url" to url,
                                "name" to name,
                                "whitelist" to if (whitelist) "1" else "0"
                            ))
                        }
                    }
                ) {
                    Text("添加")
                }
            },
            dismissButton = {
                TextButton(onClick = { showAdd = false }) { Text("取消") }
            }
        )
    }
}

private fun feature(key: String, on: Boolean) = mapOf(
    "action" to "feature",
    "feature" to key,
    "value" to if (on) "1" else "0"
)

private const val ADULT_FILTER_URL =
    "https://cdn.jsdelivr.net/gh/Ozero-top/AdguardHome-Rrules@dist/manual/nsfw.txt"
private const val ADULT_FILTER_NAME = "HaGeZi NSFW（成人内容）"

private val ADULT_FILTER_URLS = setOf(
    ADULT_FILTER_URL,
    "https://raw.githubusercontent.com/Ozero-top/AdguardHome-Rrules/refs/heads/dist/manual/nsfw.txt",
    "https://raw.githubusercontent.com/Ozero-top/AdguardHome-Rrules/dist/manual/nsfw.txt",
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt"
)

private fun FiltersData.adultFilter(): FilterItem? =
    filters.firstOrNull { !it.whitelist && it.url in ADULT_FILTER_URLS }

private fun removeAdultFilter(client: AghClient, filter: FilterItem) {
    client.filterAction(
        mapOf(
            "action" to "remove",
            "url" to filter.url,
            "whitelist" to "0"
        )
    )
}

private fun enableAdultFilter(client: AghClient, existing: FilterItem?) {
    if (existing == null) {
        client.filterAction(
            mapOf(
                "action" to "add",
                "url" to ADULT_FILTER_URL,
                "name" to ADULT_FILTER_NAME,
                "whitelist" to "0"
            )
        )
        return
    }
    if (existing.enabled) return

    if (existing.url == ADULT_FILTER_URL) {
        client.filterAction(
            mapOf(
                "action" to "toggle",
                "url" to existing.url,
                "name" to existing.name.ifEmpty { ADULT_FILTER_NAME },
                "whitelist" to "0",
                "enabled" to "1"
            )
        )
        return
    }

    // 旧地址先移除，再按 CDN 地址重新添加；AGH 的 set_url 不支持直接改地址
    removeAdultFilter(client, existing)
    client.filterAction(
        mapOf(
            "action" to "add",
            "url" to ADULT_FILTER_URL,
            "name" to ADULT_FILTER_NAME,
            "whitelist" to "0"
        )
    )
}

@Composable
private fun FeatureRow(label: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

@Composable
private fun FilterCard(
    item: FilterItem,
    enabled: Boolean,
    onToggle: (Boolean) -> Unit,
    onRemove: () -> Unit
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = item.name.ifEmpty { item.url },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                if (item.whitelist) {
                    StatusPill("白名单", ok = true)
                }
            }
            Text(
                text = item.url,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "${formatNumber(item.rulesCount)} 条规则",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onRemove, enabled = enabled) {
                    Text("删除", color = MaterialTheme.colorScheme.error)
                }
                Switch(checked = item.enabled, onCheckedChange = onToggle, enabled = enabled)
            }
        }
    }
}
