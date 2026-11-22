package top.ozero.aghmanage.data

import org.json.JSONArray
import org.json.JSONObject

data class FilterItem(
    val id: Long,
    val name: String,
    val url: String,
    val enabled: Boolean,
    val whitelist: Boolean,
    val rulesCount: Long,
    val lastUpdated: String
)

data class FiltersData(
    val filteringEnabled: Boolean,
    val filters: List<FilterItem>,
    val userRules: List<String>,
    val presetSource: String,
    val safeSearch: Boolean,
    val parental: Boolean,
    val safeBrowsing: Boolean
) {
    companion object {
        fun parse(obj: JSONObject): FiltersData {
            val array = obj.optJSONArray("filters") ?: JSONArray()
            val filters = ArrayList<FilterItem>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                filters += FilterItem(
                    id = item.optLong("id", 0L),
                    name = item.optString("name").ifEmpty { item.optString("url") },
                    url = item.optString("url"),
                    enabled = item.optBoolean("enabled", true),
                    whitelist = item.optBoolean("whitelist", false),
                    rulesCount = item.optLong("rules_count", 0L),
                    lastUpdated = item.optString("last_updated")
                )
            }
            val rulesArray = obj.optJSONArray("user_rules") ?: JSONArray()
            val rules = ArrayList<String>(rulesArray.length())
            for (i in 0 until rulesArray.length()) {
                rules += rulesArray.optString(i)
            }
            return FiltersData(
                filteringEnabled = obj.optBoolean("filtering_enabled", false),
                filters = filters,
                userRules = rules,
                presetSource = obj.optString("preset_source", "jsdelivr"),
                safeSearch = obj.optBoolean("safesearch", false),
                parental = obj.optBoolean("parental", false),
                safeBrowsing = obj.optBoolean("safebrowsing", false)
            )
        }
    }
}

data class SettingsData(
    val enabled: Boolean,
    val dnsMode: String,
    val webPort: Int,
    val binPath: String,
    val workDir: String,
    val channel: String,
    val githubProxy: String,
    val cacheEnabled: Boolean,
    val cacheSizeMb: Int,
    val cacheTtlMin: Int,
    val cacheTtlMax: Int,
    val cacheOptimistic: Boolean,
    val dnsCrypto: String,
    val dnsCryptoCustom: String,
    val cryptoBlocked: Boolean,
    val upstreamSource: String,
    val upstreamCustom: String,
    val upstreamCurrent: String,
    val statsRetentionDays: Int,
    val querylogRetentionDays: Int,
    val bypassIfaces: String,
    val bypassClients: String,
    val devices: List<String>,
    val adminUser: String,
    val adminPass: String,
    val configPath: String,
    val coreInstalled: Boolean,
    val coreVersion: String,
    val running: Boolean
) {
    /** 用于 settings_save，可覆盖更新通道。 */
    fun toSaveParams(targetChannel: String = channel): Map<String, String> = mapOf(
        "enabled" to if (enabled) "1" else "0",
        "dns_mode" to dnsMode,
        "webport" to webPort.toString(),
        "binpath" to binPath,
        "workdir" to workDir,
        "channel" to targetChannel,
        "github_proxy" to githubProxy,
        "cache_enabled" to if (cacheEnabled) "1" else "0",
        "cache_size_mb" to cacheSizeMb.toString(),
        "cache_ttl_min" to cacheTtlMin.toString(),
        "cache_ttl_max" to cacheTtlMax.toString(),
        "cache_optimistic" to if (cacheOptimistic) "1" else "0",
        "dns_crypto" to dnsCrypto,
        "dns_crypto_custom" to dnsCryptoCustom,
        "upstream_source" to upstreamSource,
        "upstream_custom" to upstreamCustom,
        "bypass_ifaces" to bypassIfaces,
        "bypass_clients" to bypassClients
    )

    companion object {
        fun parse(obj: JSONObject): SettingsData {
            val devicesArray = obj.optJSONArray("devices") ?: JSONArray()
            val devices = ArrayList<String>(devicesArray.length())
            for (i in 0 until devicesArray.length()) {
                devices += devicesArray.optString(i)
            }
            return SettingsData(
                enabled = obj.optBoolean("enabled", false),
                dnsMode = obj.optString("dns_mode", "takeover"),
                webPort = obj.optInt("webport", 13800),
                binPath = obj.optString("binpath", "/usr/bin/AdGuardHome/AdGuardHome"),
                workDir = obj.optString("workdir", "/etc/AdGuardHome"),
                channel = obj.optString("channel", "stable"),
                githubProxy = obj.optString("github_proxy", "gh-proxy.org"),
                cacheEnabled = obj.optBoolean("cache_enabled", true),
                cacheSizeMb = obj.optInt("cache_size_mb", 16),
                cacheTtlMin = obj.optInt("cache_ttl_min", 0),
                cacheTtlMax = obj.optInt("cache_ttl_max", 0),
                cacheOptimistic = obj.optBoolean("cache_optimistic", false),
                dnsCrypto = obj.optString("dns_crypto", "off"),
                dnsCryptoCustom = obj.optString("dns_crypto_custom"),
                cryptoBlocked = obj.optBoolean("crypto_blocked", false),
                upstreamSource = obj.optString("upstream_source", "auto"),
                upstreamCustom = obj.optString("upstream_custom"),
                upstreamCurrent = obj.optString("upstream_current"),
                statsRetentionDays = obj.optInt("stats_retention_days", 30),
                querylogRetentionDays = obj.optInt("querylog_retention_days", 30),
                bypassIfaces = obj.optString("bypass_ifaces"),
                bypassClients = obj.optString("bypass_clients"),
                devices = devices,
                adminUser = obj.optString("admin_user", "admin"),
                adminPass = obj.optString("admin_pass"),
                configPath = obj.optString("config_path", "/etc/AdGuardHome.yaml"),
                coreInstalled = obj.optBoolean("core", false),
                coreVersion = obj.optString("version"),
                running = obj.optBoolean("running", false)
            )
        }
    }
}

data class QueryLogEntry(
    val time: String,
    val client: String,
    val clientName: String,
    val domain: String,
    val qtype: String,
    val status: String,
    val blocked: Boolean,
    val reason: String,
    val upstream: String,
    val rule: String,
    val filterName: String,
    val elapsedMs: String
)

data class QueryLogPage(
    val items: List<QueryLogEntry>,
    val more: Boolean,
    val cursor: String
) {
    companion object {
        fun parse(obj: JSONObject): QueryLogPage {
            val array = obj.optJSONArray("data") ?: JSONArray()
            val items = ArrayList<QueryLogEntry>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                items += QueryLogEntry(
                    time = item.optString("time"),
                    client = item.optString("client"),
                    clientName = item.optString("client_name"),
                    domain = item.optString("domain"),
                    qtype = item.optString("qtype"),
                    status = item.optString("status"),
                    blocked = item.optBoolean("blocked", false),
                    reason = item.optString("reason"),
                    upstream = item.optString("upstream"),
                    rule = item.optString("rule"),
                    filterName = item.optString("filter_name"),
                    elapsedMs = item.optString("elapsed_ms")
                )
            }
            return QueryLogPage(
                items = items,
                more = obj.optBoolean("more", false),
                cursor = obj.optString("cursor")
            )
        }
    }
}

data class SelfCheck(
    val id: String,
    val label: String,
    val detail: String,
    val ok: Boolean
)

data class SelfTestResult(
    val ok: Boolean,
    val dnsPort: Int,
    val checks: List<SelfCheck>
) {
    companion object {
        fun parse(obj: JSONObject): SelfTestResult {
            val array = obj.optJSONArray("checks") ?: JSONArray()
            val checks = ArrayList<SelfCheck>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                checks += SelfCheck(
                    id = item.optString("id"),
                    label = item.optString("label"),
                    detail = item.optString("detail"),
                    ok = item.optBoolean("ok", false)
                )
            }
            return SelfTestResult(
                ok = obj.optBoolean("ok", false),
                dnsPort = obj.optInt("dns_port", 53),
                checks = checks
            )
        }
    }
}

data class LegacyItem(
    val kind: String,
    val name: String,
    val path: String,
    val note: String
)

data class LegacyScan(
    val ok: Boolean,
    val count: Int,
    val items: List<LegacyItem>
) {
    companion object {
        fun parse(obj: JSONObject): LegacyScan {
            val array = obj.optJSONArray("items") ?: JSONArray()
            val items = ArrayList<LegacyItem>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                items += LegacyItem(
                    kind = item.optString("kind"),
                    name = item.optString("name"),
                    path = item.optString("path"),
                    note = item.optString("note")
                )
            }
            return LegacyScan(
                ok = obj.optBoolean("ok", false),
                count = obj.optInt("count", items.size),
                items = items
            )
        }
    }
}

data class LegacyCleanResult(
    val ok: Boolean,
    val removed: Int,
    val backup: String
)

data class ProgressInfo(
    val running: Boolean,
    val log: String,
    val code: Int?
) {
    companion object {
        fun parse(obj: JSONObject): ProgressInfo = ProgressInfo(
            running = obj.optBoolean("running", false),
            log = obj.optString("log"),
            code = if (obj.has("code") && !obj.isNull("code")) obj.optInt("code") else null
        )
    }
}

data class PluginCheckResult(
    val current: String,
    val latest: String,
    val update: Boolean
) {
    companion object {
        fun parse(obj: JSONObject): PluginCheckResult = PluginCheckResult(
            current = obj.optString("current"),
            latest = obj.optString("latest"),
            update = obj.optBoolean("update", false)
        )
    }
}

data class YamlData(
    val path: String,
    val enabled: Boolean,
    val running: Boolean,
    val yaml: String
) {
    companion object {
        fun parse(obj: JSONObject): YamlData = YamlData(
            path = obj.optString("path", "/etc/AdGuardHome.yaml"),
            enabled = obj.optBoolean("enabled", false),
            running = obj.optBoolean("running", false),
            yaml = obj.optString("yaml")
        )
    }
}
