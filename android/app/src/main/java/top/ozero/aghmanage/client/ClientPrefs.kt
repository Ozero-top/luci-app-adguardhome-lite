package top.ozero.aghmanage.client

import android.content.Context

class ClientPrefs(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("agh_client", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(value) = prefs.edit().putBoolean("enabled", value).apply()

    var upstream: String
        get() = prefs.getString("upstream", DEFAULT_UPSTREAM) ?: DEFAULT_UPSTREAM
        set(value) = prefs.edit().putString("upstream", value).apply()

    var tier: String
        get() = prefs.getString("tier", "512") ?: "512"
        set(value) = prefs.edit().putString("tier", value).apply()

    var blockedTotal: Long
        get() = prefs.getLong("blocked_total", 0L)
        set(value) = prefs.edit().putLong("blocked_total", value).apply()

    var lastUpdate: Long
        get() = prefs.getLong("last_update", 0L)
        set(value) = prefs.edit().putLong("last_update", value).apply()

    var pausedUntil: Long
        get() = prefs.getLong("paused_until", 0L)
        set(value) = prefs.edit().putLong("paused_until", value).apply()

    var autoStart: Boolean
        get() = prefs.getBoolean("auto_start", true)
        set(value) = prefs.edit().putBoolean("auto_start", value).apply()

    /** all / allow / deny */
    var splitMode: String
        get() {
            val value = prefs.getString("split_mode", SPLIT_ALL) ?: SPLIT_ALL
            return if (value == SPLIT_ALLOW || value == SPLIT_DENY) value else SPLIT_ALL
        }
        set(value) = prefs.edit().putString("split_mode", value).apply()

    var selectedApps: Set<String>
        get() = prefs.getStringSet("selected_apps", emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet("selected_apps", value).apply()

    fun upstreamServers(): List<String> =
        upstream.split(',', ' ', ';')
            .map { it.trim() }
            .filter { it.matches(IPV4) }

    companion object {
        const val SPLIT_ALL = "all"
        const val SPLIT_ALLOW = "allow"
        const val SPLIT_DENY = "deny"

        const val DEFAULT_UPSTREAM = "223.5.5.5, 119.29.29.29"
        private val IPV4 = Regex("^\\d{1,3}(\\.\\d{1,3}){3}$")
    }
}
