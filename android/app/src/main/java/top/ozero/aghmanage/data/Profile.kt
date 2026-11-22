package top.ozero.aghmanage.data

data class Profile(
    val host: String = "",
    val port: Int = 80,
    val https: Boolean = false,
    val user: String = "root",
    val pass: String = ""
) {
    val baseUrl: String
        get() {
            val scheme = if (https) "https" else "http"
            val defaultPort = (port == 80 && !https) || (port == 443 && https)
            val suffix = if (defaultPort) "" else ":$port"
            return "$scheme://${host.trim()}$suffix"
        }

    /** 插件 JSON 接口所在的 LuCI 路径。 */
    val apiBase: String
        get() = "$baseUrl/cgi-bin/luci/admin/services/adguardhome_lite"
}
