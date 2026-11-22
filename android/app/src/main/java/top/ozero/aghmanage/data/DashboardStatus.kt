package top.ozero.aghmanage.data

import org.json.JSONObject

data class DashboardStatus(
    val running: Boolean,
    val enabled: Boolean,
    val dnsMode: String,
    val coreVersion: String,
    val webPort: Int,
    val queries: Long,
    val blocked: Long,
    val avgMs: Double,
    val coreInstalled: Boolean,
    val dnsPort: Int,
    val coreLatest: String,
    val coreUpdate: Boolean,
    val pluginVersion: String,
    val pluginLatest: String,
    val pluginUpdate: Boolean,
    val pluginUrl: String,
    val updateRunning: Boolean,
    val actionRunning: Boolean,
    val channel: String,
    val coreChannel: String
) {
    val blockedPercent: Double
        get() = if (queries > 0) blocked * 100.0 / queries else 0.0

    companion object {
        fun parse(json: JSONObject): DashboardStatus {
            val stats = json.optJSONObject("stats") ?: JSONObject()
            val coreUpdate = json.optJSONObject("core_update") ?: JSONObject()
            val plugin = json.optJSONObject("plugin") ?: JSONObject()
            return DashboardStatus(
                running = json.optBoolean("running", false),
                enabled = json.optBoolean("enabled", false),
                dnsMode = json.optString("dns_mode", ""),
                coreVersion = json.optString("version", ""),
                webPort = json.optInt("web_port", 13800),
                queries = stats.optLong("queries", 0L),
                blocked = stats.optLong("blocked", 0L),
                avgMs = stats.optDouble("avg", 0.0),
                coreInstalled = json.optBoolean("core", false),
                dnsPort = json.optInt("dns_port", 53),
                coreLatest = coreUpdate.optString("latest"),
                coreUpdate = coreUpdate.optBoolean("update", false),
                pluginVersion = plugin.optString("current"),
                pluginLatest = plugin.optString("latest"),
                pluginUpdate = plugin.optBoolean("update", false),
                pluginUrl = plugin.optString("url"),
                updateRunning = json.optBoolean("update_running", false),
                actionRunning = json.optBoolean("action_running", false),
                channel = json.optString("channel", "stable"),
                coreChannel = json.optString("core_channel")
            )
        }
    }
}
