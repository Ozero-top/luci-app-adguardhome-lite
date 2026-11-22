package top.ozero.aghmanage.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.data.AghClient
import top.ozero.aghmanage.data.QueryLogEntry

@Composable
fun LogsScreen(client: AghClient) {
    var tab by remember { mutableStateOf(0) }

    Column(Modifier.fillMaxSize()) {
        TabRow(
            selectedTabIndex = tab,
            containerColor = MaterialTheme.colorScheme.background
        ) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("系统日志") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("查询日志") })
        }
        if (tab == 0) SystemLogPane(client) else QueryLogPane(client)
    }
}

@Composable
private fun SystemLogPane(client: AghClient) {
    var level by remember { mutableStateOf("") }
    var text by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshKey by remember { mutableStateOf(0) }

    LaunchedEffect(level, refreshKey) {
        busy = true
        try {
            text = withContext(Dispatchers.IO) { client.fetchLogs(level) }
            error = null
        } catch (e: Exception) {
            error = e.message ?: "读取日志失败"
        } finally {
            busy = false
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("" to "全部", "error" to "错误", "warn" to "警告", "info" to "信息").forEach { (key, label) ->
                FilterChip(
                    selected = level == key,
                    onClick = { level = key },
                    label = { Text(label) }
                )
            }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { refreshKey++ }, enabled = !busy) { Text("刷新") }
        }

        NoticeText(error, error = true)

        Card(Modifier.fillMaxWidth().weight(1f)) {
            SelectionContainer {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(12.dp)
                ) {
                    Text(
                        text = when {
                            text.isNotEmpty() -> text
                            busy -> "读取中…"
                            else -> "暂无日志"
                        },
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        lineHeight = 16.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun QueryLogPane(client: AghClient) {
    var status by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<QueryLogEntry>>(emptyList()) }
    var cursor by remember { mutableStateOf("") }
    var more by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var loadedOnce by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    suspend fun load(reset: Boolean, statusValue: String, searchValue: String) {
        if (loading) return
        loading = true
        try {
            val page = withContext(Dispatchers.IO) {
                client.fetchQueryLog(
                    limit = 50,
                    status = statusValue,
                    search = searchValue.trim(),
                    olderThan = if (reset) "" else cursor
                )
            }
            entries = if (reset) page.items else entries + page.items
            cursor = page.cursor
            more = page.more
            error = null
        } catch (e: Exception) {
            error = e.message ?: "读取查询日志失败"
        } finally {
            loading = false
            loadedOnce = true
        }
    }

    LaunchedEffect(Unit) { load(true, "", "") }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("" to "全部", "blocked" to "已拦截", "allowed" to "已放行").forEach { (key, label) ->
                FilterChip(
                    selected = status == key,
                    onClick = {
                        status = key
                        scope.launch { load(true, key, search) }
                    },
                    label = { Text(label) }
                )
            }
        }

        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            label = { Text("搜索域名") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            trailingIcon = {
                TextButton(onClick = { scope.launch { load(true, status, search) } }) {
                    Text("搜索")
                }
            }
        )

        NoticeText(error, error = true)

        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(entries) { entry ->
                QueryLogCard(entry)
            }
            if (more) {
                item {
                    OutlinedButton(
                        onClick = { scope.launch { load(false, status, search) } },
                        enabled = !loading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(if (loading) "加载中…" else "加载更多")
                    }
                }
            }
            if (!loading && loadedOnce && entries.isEmpty()) {
                item {
                    Text(
                        text = "没有匹配的查询记录",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun QueryLogCard(entry: QueryLogEntry) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text(
                    text = entry.domain.ifEmpty { "(未知域名)" },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                StatusPill(if (entry.blocked) "拦截" else "放行", ok = !entry.blocked)
            }
            val meta = buildList {
                add(formatQueryTime(entry.time))
                add(entry.clientName.ifEmpty { entry.client })
                if (entry.qtype.isNotEmpty()) add(entry.qtype)
                if (entry.elapsedMs.isNotEmpty()) add("${entry.elapsedMs}ms")
            }.filter { it.isNotEmpty() }.joinToString(" · ")
            Text(
                text = meta,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (entry.rule.isNotEmpty() || entry.filterName.isNotEmpty()) {
                Text(
                    text = listOf(entry.rule, entry.filterName).filter { it.isNotEmpty() }.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (entry.reason.isNotEmpty()) {
                Text(
                    text = entry.reason,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
