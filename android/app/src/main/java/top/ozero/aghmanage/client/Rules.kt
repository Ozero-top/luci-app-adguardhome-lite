package top.ozero.aghmanage.client

import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Arrays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 域名匹配器：把规则排序后放进字符串数组，查询时按域名后缀二分查找。
 * 比 HashSet 更省内存，也比逐条通配匹配快。
 */
class DomainMatcher private constructor(
    private val blocked: Array<String>,
    private val allowed: Array<String>
) {

    val size: Int get() = blocked.size

    fun isBlocked(domain: String): Boolean {
        val name = normalize(domain)
        if (name.isEmpty()) return false
        if (matches(allowed, name)) return false
        return matches(blocked, name)
    }

    private fun matches(list: Array<String>, name: String): Boolean {
        if (list.isEmpty()) return false
        var start = 0
        while (start < name.length) {
            if (Arrays.binarySearch(list, name.substring(start)) >= 0) return true
            val dot = name.indexOf('.', start)
            if (dot < 0) return false
            start = dot + 1
            // 只剩顶级域时不再继续，避免误匹配 "com" 之类的规则
            if (name.indexOf('.', start) < 0) return false
        }
        return false
    }

    companion object {
        val EMPTY = DomainMatcher(emptyArray(), emptyArray())

        fun build(blocked: Collection<String>, allowed: Collection<String>): DomainMatcher {
            val blockedArray = blocked.toTypedArray()
            blockedArray.sort()
            val allowedArray = allowed.toTypedArray()
            allowedArray.sort()
            return DomainMatcher(blockedArray, allowedArray)
        }

        fun normalize(domain: String): String = domain.trim().lowercase().trimEnd('.')
    }
}

object RuleParser {

    private val HOSTS_PREFIXES = setOf("0.0.0.0", "127.0.0.1", "::1", "::")

    fun parse(
        reader: BufferedReader,
        blocked: MutableSet<String>,
        allowed: MutableSet<String>,
        limit: Int = RuleStore.MAX_RULES
    ) {
        reader.forEachLine { parseLine(it, blocked, allowed, limit) }
    }

    /** 白名单文件：整行都视为放行域名，避免把纯域名误加入拦截集合。 */
    fun parseAllow(reader: BufferedReader, allowed: MutableSet<String>) {
        reader.forEachLine { parseAllowLine(it, allowed) }
    }

    fun parseAllowLine(raw: String, allowed: MutableSet<String>) {
        val line = raw.trim()
        if (line.isEmpty() || line.startsWith("!") || line.startsWith("#") || line.startsWith(";")) {
            return
        }
        extract(line)?.let { allowed.add(it) }
    }

    fun parseLine(
        raw: String,
        blocked: MutableSet<String>,
        allowed: MutableSet<String>,
        limit: Int = RuleStore.MAX_RULES
    ) {
        val line = raw.trim()
        if (line.isEmpty()) return
        if (line.startsWith("!") || line.startsWith("[") ||
            line.startsWith("#") || line.startsWith(";")
        ) {
            return
        }
        if (line.startsWith("@@")) {
            extract(line.substring(2))?.let { allowed.add(it) }
            return
        }

        val parts = line.split(' ', '\t').filter { it.isNotEmpty() }
        if (parts.size >= 2 && parts[0] in HOSTS_PREFIXES) {
            for (i in 1 until parts.size) {
                val domain = extract(parts[i]) ?: continue
                if (blocked.size >= limit) return
                blocked.add(domain)
            }
            return
        }

        val domain = extract(line) ?: return
        if (blocked.size >= limit) return
        blocked.add(domain)
    }

    fun extract(raw: String): String? {
        var text = raw.trim()
        if (text.startsWith("@@")) text = text.substring(2)
        if (text.startsWith("||")) {
            text = text.substring(2)
        } else if (text.startsWith("|")) {
            text = text.substring(1)
        }
        text = text.substringBefore('^')
            .substringBefore('$')
            .substringBefore('/')
            .substringBefore('#')
            .trim()
        if (text.startsWith("*.")) text = text.substring(2)
        text = text.trim('.').lowercase()
        if (text.isEmpty() || text.length > 253 || !text.contains('.')) return null
        if (text.any { !(it.isLetterOrDigit() || it == '.' || it == '-' || it == '_') }) return null
        return text
    }
}

object RuleStore {

    const val MAX_RULES = 1_000_000

    @Volatile
    private var matcher: DomainMatcher = DomainMatcher.EMPTY

    val count: Int get() = matcher.size

    @Synchronized
    fun load(context: Context) {
        val blocked = HashSet<String>(1 shl 20)
        val allowed = HashSet<String>()

        runCatching {
            context.assets.open("basic_blocklist.txt").bufferedReader().use {
                RuleParser.parse(it, blocked, allowed)
            }
        }
        runCatching {
            val file = File(context.filesDir, "client_rules.txt")
            if (file.exists()) file.bufferedReader().use { RuleParser.parse(it, blocked, allowed) }
        }
        runCatching {
            val file = File(context.filesDir, "client_allow.txt")
            if (file.exists()) file.bufferedReader().use { RuleParser.parseAllow(it, allowed) }
        }

        matcher = DomainMatcher.build(blocked, allowed)
    }

    fun isBlocked(domain: String): Boolean = matcher.isBlocked(domain)
}

object RuleUpdater {

    private const val JS_BASE = "https://cdn.jsdelivr.net/gh/Ozero-top/AdguardHome-Rrules@dist"
    private const val GH_BASE = "https://raw.githubusercontent.com/Ozero-top/AdguardHome-Rrules/dist"

    private const val TIER = "2048"
    private val CATEGORIES = listOf("security", "chinese", "tracking", "ads", "annoyances", "intl")

    suspend fun update(
        context: Context,
        progress: (String) -> Unit
    ): Result<Int> = withContext(Dispatchers.IO) {
        val blocked = HashSet<String>(1 shl 20)
        val allowed = HashSet<String>()
        var success = 0

        CATEGORIES.forEachIndexed { index, category ->
            progress("下载 ${category}.txt（${index + 1}/${CATEGORIES.size}）")
            val text = download("$JS_BASE/$TIER/$category.txt", "$GH_BASE/$TIER/$category.txt")
            if (text == null) {
                return@forEachIndexed
            }
            text.lineSequence().forEach {
                RuleParser.parseLine(it, blocked, allowed, RuleStore.MAX_RULES)
            }
            success++
        }

        if (success == 0) {
            return@withContext Result.failure(IOException("规则下载失败，请检查手机网络后重试"))
        }

        progress("下载 allowlist.txt")
        download("$JS_BASE/allowlist.txt", "$GH_BASE/allowlist.txt")?.lineSequence()?.forEach {
            RuleParser.parseAllowLine(it, allowed)
        }

        if (blocked.isEmpty()) {
            return@withContext Result.failure(IOException("规则内容为空，请稍后重试"))
        }

        val count = blocked.size
        progress("写入 $count 条规则")
        runCatching {
            File(context.filesDir, "client_rules.txt").bufferedWriter().use { writer ->
                blocked.forEach {
                    writer.write(it)
                    writer.newLine()
                }
            }
            File(context.filesDir, "client_allow.txt").bufferedWriter().use { writer ->
                allowed.forEach {
                    writer.write(it)
                    writer.newLine()
                }
            }
            // 及时释放下载阶段的大集合，降低重新加载规则的峰值内存
            blocked.clear()
            allowed.clear()
            RuleStore.load(context)
            val prefs = ClientPrefs(context)
            prefs.lastUpdate = System.currentTimeMillis()
            prefs.tier = TIER
        }.onFailure {
            return@withContext Result.failure(IOException("保存规则失败：${it.message}"))
        }

        val total = RuleStore.count
        ClientState.update {
            it.copy(rules = total, updateMessage = "已更新 $total 条规则")
        }
        Result.success(total)
    }

    private fun download(primary: String, fallback: String): String? =
        fetch(primary) ?: fetch(fallback)

    private fun fetch(url: String): String? = try {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15000
            readTimeout = 60000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "AghManage-Android")
        }
        try {
            if (conn.responseCode in 200..299) {
                conn.inputStream.bufferedReader().readText()
            } else {
                null
            }
        } finally {
            conn.disconnect()
        }
    } catch (e: Exception) {
        null
    }
}
