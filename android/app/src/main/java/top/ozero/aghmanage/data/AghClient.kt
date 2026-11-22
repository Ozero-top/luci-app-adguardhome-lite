package top.ozero.aghmanage.data

import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class AghException(message: String) : IOException(message)

/**
 * 与路由器插件的 HTTP 客户端。
 *
 * 登录沿用 LuCI 原生表单，成功后从 Set-Cookie 取出会话号；
 * 再调用插件的 /session 接口换取 CSRF 令牌，后续写操作都要带这个令牌。
 */
class AghClient(private val profile: Profile) {

    private var cookieName = if (profile.https) "sysauth_https" else "sysauth_http"
    private var cookieValue = ""
    private var token = ""

    fun connect() {
        login()
    }

    // ===== 概览 =====

    fun fetchStatus(): DashboardStatus =
        DashboardStatus.parse(JSONObject(get("/status")))

    fun serviceAction(action: String) {
        requireOk(post("/service", mapOf("action" to action)))
    }

    fun clearStats() {
        requireOk(post("/stats_clear", emptyMap()))
    }

    fun runSelfTest(): SelfTestResult =
        SelfTestResult.parse(JSONObject(get("/selftest")))

    // ===== 设置 =====

    fun fetchSettings(): SettingsData =
        SettingsData.parse(JSONObject(get("/settings_get")))

    fun saveSettings(form: Map<String, String>) {
        requireOk(post("/settings_save", form))
    }

    fun saveRetention(days: Int, queryDays: Int) {
        requireOk(post("/retention_save", mapOf(
            "days" to days.toString(),
            "query_days" to queryDays.toString()
        )))
    }

    fun fetchYaml(): YamlData =
        YamlData.parse(JSONObject(get("/yaml_get")))

    fun saveYaml(yaml: String) {
        requireOk(post("/yaml_save", mapOf("yaml" to yaml)))
    }

    // ===== 规则 =====

    fun fetchFilters(): FiltersData {
        val json = requireOk(get("/filters_get"))
        return FiltersData.parse(json)
    }

    fun filterAction(params: Map<String, String>) {
        requireOk(post("/filters_save", params))
    }

    fun fetchQueryLog(
        limit: Int = 50,
        status: String = "",
        search: String = "",
        olderThan: String = ""
    ): QueryLogPage {
        val query = buildList {
            add("limit=$limit")
            if (status.isNotEmpty()) add("status=${enc(status)}")
            if (search.isNotEmpty()) add("search=${enc(search)}")
            if (olderThan.isNotEmpty()) add("older_than=${enc(olderThan)}")
        }.joinToString("&")
        val json = requireOk(get("/querylog_get?$query"))
        return QueryLogPage.parse(json)
    }

    // ===== 日志 =====

    fun fetchLogs(level: String = ""): String {
        val query = if (level.isEmpty()) "" else "?level=${enc(level)}"
        return get("/logs_raw$query")
    }

    // ===== 内核与插件更新 =====

    fun installCore() {
        requireOk(post("/core_install", emptyMap()))
    }

    fun coreProgress(): ProgressInfo =
        ProgressInfo.parse(JSONObject(get("/core_progress")))

    fun pluginCheck(): PluginCheckResult =
        PluginCheckResult.parse(requireOk(post("/plugin_check", emptyMap())))

    fun pluginUpdate(version: String, force: Boolean, channel: String, method: String) {
        requireOk(post("/plugin_update", mapOf(
            "version" to version,
            "force" to if (force) "1" else "0",
            "channel" to channel,
            "method" to method
        )))
    }

    fun pluginProgress(): ProgressInfo =
        ProgressInfo.parse(JSONObject(get("/plugin_progress")))

    // ===== 账号与维护 =====

    fun changePassword(password: String) {
        val hash = at.favre.lib.crypto.bcrypt.BCrypt.withDefaults()
            .hashToString(10, password.toCharArray())
        requireOk(post("/password", mapOf(
            "hash" to hash,
            "password" to password
        )))
    }

    fun scanLegacy(): LegacyScan =
        LegacyScan.parse(requireOk(get("/legacy_scan")))

    fun cleanLegacy(): LegacyCleanResult {
        val json = requireOk(post("/legacy_clean", emptyMap()))
        return LegacyCleanResult(
            ok = json.optBoolean("ok", false),
            removed = json.optInt("removed", 0),
            backup = json.optString("backup")
        )
    }

    // ===== 底层请求 =====

    @Synchronized
    private fun login() {
        val conn = open(profile.baseUrl + "/cgi-bin/luci/")
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")

        val body = "luci_username=${enc(profile.user)}&luci_password=${enc(profile.pass)}"
        conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

        val code = conn.responseCode
        val setCookie = conn.headerFields.entries
            .firstOrNull { it.key.equals("Set-Cookie", true) }
            ?.value?.firstOrNull() ?: ""
        conn.disconnect()

        if (code != HttpURLConnection.HTTP_OK && code != HttpURLConnection.HTTP_MOVED_TEMP) {
            throw AghException(
                if (code == HttpURLConnection.HTTP_FORBIDDEN) "登录被拒绝（HTTP 403）"
                else "登录失败（HTTP $code）"
            )
        }

        val match = Regex("(sysauth_https|sysauth_http)=([0-9a-fA-F]+)").find(setCookie)
            ?: throw AghException("账号或密码错误，或该地址不是 LuCI 登录页")

        cookieName = match.groupValues[1]
        cookieValue = match.groupValues[2]

        val json = JSONObject(get("/session", retry = false))
        token = json.optString("token")
        if (token.isEmpty()) {
            throw AghException("未取得会话令牌，请确认插件版本支持 /session 接口")
        }
    }

    @Synchronized
    private fun get(path: String, retry: Boolean = true): String {
        val conn = open(profile.apiBase + path)
        conn.requestMethod = "GET"
        conn.setRequestProperty("Cookie", "$cookieName=$cookieValue")
        conn.setRequestProperty("Accept", "application/json, text/plain, */*")

        val code = conn.responseCode
        val text = readBody(conn, code)
        conn.disconnect()

        if (needsLogin(code) && retry) {
            login()
            return get(path, retry = false)
        }
        return ensureSuccess(code, text)
    }

    @Synchronized
    private fun post(path: String, form: Map<String, String>, retry: Boolean = true): String {
        val conn = open(profile.apiBase + path)
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.setRequestProperty("Cookie", "$cookieName=$cookieValue")
        conn.setRequestProperty("Accept", "application/json, text/plain, */*")
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")

        val body = (form.toList() + ("token" to token))
            .joinToString("&") { "${enc(it.first)}=${enc(it.second)}" }
        conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

        val code = conn.responseCode
        val text = readBody(conn, code)
        conn.disconnect()

        if (needsLogin(code) && retry) {
            login()
            return post(path, form, retry = false)
        }
        return ensureSuccess(code, text)
    }

    /** 会话失效时 LuCI 可能返回 401/403，也可能直接 302 到登录页。 */
    private fun needsLogin(code: Int): Boolean =
        code == HttpURLConnection.HTTP_FORBIDDEN ||
            code == HttpURLConnection.HTTP_UNAUTHORIZED ||
            code == HttpURLConnection.HTTP_MOVED_TEMP

    private fun open(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 8000
            readTimeout = 30000
            instanceFollowRedirects = false
        }

    private fun readBody(conn: HttpURLConnection, code: Int): String =
        (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""

    private fun ensureSuccess(code: Int, text: String): String {
        if (code in 200..299) {
            return text
        }
        val json = runCatching { JSONObject(text) }.getOrNull()
        val message = json?.optString("error").orEmpty().ifEmpty {
            val plain = text.trim()
            if (plain.isNotEmpty() && !plain.startsWith("<") && plain.length <= 200) plain else ""
        }
        if (message.isNotEmpty()) {
            throw AghException(message)
        }
        throw AghException(
            when (code) {
                HttpURLConnection.HTTP_FORBIDDEN -> "登录已过期，请重新登录"
                HttpURLConnection.HTTP_CONFLICT -> "有任务正在运行，请稍后再试"
                else -> "请求失败（HTTP $code）"
            }
        )
    }

    private fun requireOk(text: String): JSONObject {
        val json = runCatching { JSONObject(text) }.getOrElse {
            throw AghException("返回内容格式异常")
        }
        if (json.has("ok") && !json.optBoolean("ok", false)) {
            throw AghException(json.optString("error", "操作失败"))
        }
        return json
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")
}
