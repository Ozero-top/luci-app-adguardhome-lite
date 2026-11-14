-- AdGuard Home 助手 - LuCI 控制器
-- 负责菜单注册、状态查询、内核安装、服务控制和密码修改。
module("luci.controller.adguardhome_lite", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local CONF = "adguardhome_lite"
local SHARE = "/usr/share/adguardhome-lite"
local RUN = "/var/run/adguardhome_lite"
local STATS_CACHE = RUN .. "_stats.json"
local VERSION_CACHE = RUN .. "_core_version"
local PLUGIN_UPDATE = RUN .. "_plugin_update"
local INSTALL_VERSION = SHARE .. "/install_version"
local RELEASE_URL = "https://github.com/Ozero-top/luci-app-adguardhome-lite/releases/latest"

-- 前置声明：action_status 会内联统计结果，定义在下方
local collect_stats

-- 读取带 TTL 的临时缓存，避免每次请求都重新执行外部命令
local function read_cache(path, ttl)
    local mtime = fs.stat(path, "mtime")
    if not mtime then
        return nil
    end
    if ttl and (os.time() - mtime) > ttl then
        return nil
    end
    local data = fs.readfile(path)
    if not data or data == "" then
        return nil
    end
    return data
end

local function cfg(opt, default)
    local v = uci:get(CONF, "main", opt)
    if v == nil then
        v = uci:get(CONF, "@adguardhome_lite[0]", opt)
    end
    if v == nil or v == "" then
        return default
    end
    return v
end

-- 老版本升级时 UCI 还没有缓存选项，读取 YAML 现有值作为界面初值，
-- 避免第一次打开页面就把用户原来的缓存状态显示错。
local CACHE_YAML_KEYS = {
    cache_enabled = "cache_enabled",
    cache_size_mb = "cache_size",
    cache_ttl_min = "cache_ttl_min",
    cache_ttl_max = "cache_ttl_max",
    cache_optimistic = "cache_optimistic"
}

local function yaml_cache_scalar(path, key)
    local data = fs.readfile(path)
    if not data then
        return nil
    end
    local v = data:match("\n  " .. key .. ":[ \t]*([^\r\n#]+)")
    if not v then
        return nil
    end
    return v:match("^%s*(.-)%s*$")
end

-- 读取 YAML 中某个两空格键的列表值（支持多行、行内 [a, b] 和单值写法），
-- 用于判断当前上游 DNS 是否仍由插件管理。
local function yaml_list_values(path, key)
    local data = fs.readfile(path)
    if not data then
        return ""
    end

    local values = {}
    local inlist = false
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        if not inlist then
            local inline = line:match("^  " .. key .. ":%s*(.-)%s*$")
            if inline then
                if inline:sub(1, 1) == "[" then
                    inline = inline:sub(2):gsub("%]%s*$", "")
                    for v in inline:gmatch("[^,]+") do
                        v = v:gsub("^%s+", ""):gsub("%s+$", ""):gsub('"', "")
                        if v ~= "" then
                            values[#values + 1] = v
                        end
                    end
                    return table.concat(values, " ")
                end
                if inline ~= "" then
                    return (inline:gsub('"', ""))
                end
                inlist = true
            end
        else
            local v = line:match("^    %- (.+)$")
            if v then
                v = v:gsub("^%s+", ""):gsub("%s+$", "")
                if v ~= "" then
                    values[#values + 1] = v
                end
            else
                break
            end
        end
    end

    return table.concat(values, " ")
end

-- 读取 filtering.safe_search.enabled（多一层嵌套）
local function yaml_safe_search_enabled(path)
    local data = fs.readfile(path)
    if not data then
        return false
    end
    local in_block = false
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^  safe_search:%s*$") then
            in_block = true
        elseif in_block then
            local v = line:match("^    enabled:%s*(%S+)")
            if v then
                return v == "true"
            end
            if line:match("^  [^ ]") then
                break
            end
        end
    end
    return false
end

-- 读取某个顶级段的二级标量，例如 statistics.interval、querylog.interval
local function yaml_section_scalar(path, section, key)
    local data = fs.readfile(path)
    if not data then
        return nil
    end
    local insec = false
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        if not insec then
            if line:match("^" .. section .. ":%s*$") then
                insec = true
            end
        else
            local v = line:match("^  " .. key .. ":%s*(.-)%s*$")
            if v then
                return v
            end
            if line:match("^[^%s]") then
                return nil
            end
        end
    end
    return nil
end

-- 写入某个顶级段的二级标量，保留文件其他内容
local function yaml_set_section_scalar(path, section, key, value)
    local data = fs.readfile(path)
    if not data then
        return false
    end

    local out = {}
    local insec = false
    local replaced = false
    for line in data:gmatch("([^\n]*)\n") do
        if not insec then
            if line:match("^" .. section .. ":%s*$") then
                insec = true
            end
            out[#out + 1] = line
        elseif line:match("^  " .. key .. ":") then
            out[#out + 1] = "  " .. key .. ": " .. value
            insec = false
            replaced = true
        elseif line:match("^[^%s]") then
            out[#out + 1] = line
            insec = false
        else
            out[#out + 1] = line
        end
    end

    if not replaced then
        return false
    end

    local f = io.open(path, "w")
    if not f then
        return false
    end
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
    return true
end


-- 缓存配置以 AdGuard Home 的 YAML 为准（AGH 面板与插件 UI 共用同一份），
-- YAML 不存在或缺少字段时才回退到 UCI / 默认值。
local function cache_option(configpath, key, default)
    local raw = yaml_cache_scalar(configpath, CACHE_YAML_KEYS[key])
    if raw ~= nil and raw ~= "" then
        raw = raw:gsub('"', "")

        if key == "cache_enabled" or key == "cache_optimistic" then
            if raw == "true" then
                return "1"
            elseif raw == "false" then
                return "0"
            end
            return default
        elseif key == "cache_size_mb" then
            local bytes = tonumber(raw)
            if bytes and bytes > 0 then
                return tostring(math.floor(bytes / 1048576 + 0.5))
            end
            return default
        end

        local n = tonumber(raw)
        if n then
            return tostring(math.floor(n))
        end
        return default
    end

    local v = uci:get(CONF, "main", key)
    if v ~= nil and v ~= "" then
        return v
    end
    return default
end

-- 排除列表（接口 / 客户端 IP）的解析与校验。
-- 这些值最终会写进 nft 规则文件，必须先做严格的白名单校验。
local function split_words(v)
    local t = {}
    for w in tostring(v or ""):gmatch("%S+") do
        t[#t + 1] = w
    end
    return t
end

local function join_words(v)
    if type(v) == "table" then
        return table.concat(v, " ")
    end
    return tostring(v or "")
end

local function valid_iface_name(name)
    return #name <= 15 and name:match("^[%w_%.%-]+$") ~= nil
end

local function valid_ipv4(addr)
    local a, b, c, d = addr:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return false
    end
    return tonumber(a) <= 255 and tonumber(b) <= 255 and tonumber(c) <= 255 and tonumber(d) <= 255
end

local function valid_ipv6(addr)
    if not addr:match("^[%x:]+$") or not addr:find(":", 1, true) then
        return false
    end
    if addr:find(":::", 1, true) then
        return false
    end
    local _, doubles = addr:gsub("::", "")
    if doubles > 1 then
        return false
    end
    local colons = select(2, addr:gsub(":", ""))
    if doubles == 1 then
        return colons >= 2 and colons <= 7
    end
    return colons == 7
end

local function valid_client_spec(spec)
    local addr, bits = spec:match("^([^/]+)/(%d+)$")
    if addr then
        if addr:find(":", 1, true) then
            return valid_ipv6(addr) and tonumber(bits) <= 128
        end
        return valid_ipv4(addr) and tonumber(bits) <= 32
    end
    if spec:find(":", 1, true) then
        return valid_ipv6(spec)
    end
    return valid_ipv4(spec)
end

-- 当前设备名，仅用于界面提示可排除的接口
-- 只取目录：/sys/class/net 下还有 bonding_masters 等普通文件，不是网卡；
-- 内核自带的空隧道/占位设备不会有客户端接入，也一并跳过。
local IGNORED_IFACE_PATTERNS = {
    "^lo$", "^dummy%d+$", "^sit%d+$", "^ip6tnl%d+$", "^tunl%d+$",
    "^gre%d+$", "^gretap%d+$", "^erspan%d+$", "^ip6gre%d+$",
    "^ip6_vti%d+$", "^teql%d+$", "^siit%d+$", "^utun%d*$",
}

local function iface_ignored(name)
    for _, pat in ipairs(IGNORED_IFACE_PATTERNS) do
        if name:match(pat) then
            return true
        end
    end
    return false
end

local function net_devices()
    local out = sys.exec("for d in /sys/class/net/*; do [ -d \"$d\" ] && echo \"${d##*/}\"; done") or ""
    local list = {}
    for name in out:gmatch("[^\n]+") do
        if not iface_ignored(name) and valid_iface_name(name) then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

local function is_enabled()
    local v = cfg("enabled", "0")
    return v == "1" or v == 1 or v == true
end

local function core_version(binpath)
    if not fs.access(binpath, "x") then
        return ""
    end

    -- 优先使用缓存：只要内核文件没变，就直接复用上次结果，
    -- 避免每次刷新页面都启动一次 30MB 的内核查版本。
    local bin_mtime = fs.stat(binpath, "mtime")
    local cache_mtime = fs.stat(VERSION_CACHE, "mtime")
    if bin_mtime and cache_mtime and cache_mtime >= bin_mtime then
        local cached = fs.readfile(VERSION_CACHE)
        if cached and cached ~= "" then
            return (cached:gsub("%s+$", ""))
        end
    end

    local out = sys.exec(string.format("%q --version 2>/dev/null | head -n 1", binpath))
    if not out or out == "" then
        return ""
    end

    local ver = out:match("[vV][%d%.]+") or ""
    if ver ~= "" then
        fs.writefile(VERSION_CACHE, ver)
    end
    return ver
end

local function version_parts(v)
    local parts = {}
    for n in tostring(v or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

local function version_newer(latest, current)
    if latest == "" or current == "" then
        return false
    end

    local a, b = version_parts(latest), version_parts(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then
            return x > y
        end
    end
    return false
end

-- 插件版本：取包管理器与 install.sh 记录中较新的一个，兼容 ipk 与脚本安装混用
local function plugin_version()
    local cached = read_cache(RUN .. "_plugin_version", 3600)
    if cached and cached ~= "" then
        return cached
    end

    local candidates = {}

    local out = sys.exec("opkg list-installed 2>/dev/null | awk '$1 == \"luci-app-adguardhome-lite\" { print $3; exit }'") or ""
    out = out:gsub("%s+", "")
    if out ~= "" then
        candidates[#candidates + 1] = out
    end

    out = sys.exec("apk info -v luci-app-adguardhome-lite 2>/dev/null | head -n 1") or ""
    local ver = out:match("%d+%.%d+%.%d+[%w%.%-]*")
    if ver then
        candidates[#candidates + 1] = ver
    end

    local v = (fs.readfile(INSTALL_VERSION) or ""):gsub("%s+", "")
    if v:match("^%d+%.%d+") then
        candidates[#candidates + 1] = v
    end

    local best = ""
    for i = 1, #candidates do
        if best == "" or version_newer(candidates[i], best) then
            best = candidates[i]
        end
    end

    if best ~= "" then
        fs.writefile(RUN .. "_plugin_version", best)
    end
    return best
end

-- 插件更新检查：结果缓存 24 小时，过期后在后台重新检查，不阻塞状态接口
local function plugin_update_info()
    local cache = fs.readfile(PLUGIN_UPDATE) or ""
    local latest = cache:match("latest=([^\n]*)") or ""
    local checked = tonumber(cache:match("time=(%d+)"))

    if not checked or (os.time() - checked) > 86400 then
        -- 先写占位时间，避免每次轮询都重复启动检查任务
        fs.writefile(PLUGIN_UPDATE, "latest=" .. latest .. "\ntime=" .. os.time() .. "\n")
        sys.exec("sh " .. SHARE .. "/check_plugin_update.sh >/dev/null 2>&1 &")
    end

    local current = plugin_version()
    return {
        current = current,
        latest = latest,
        update = version_newer(latest, current),
        url = RELEASE_URL
    }
end

local function service_running(binpath)
    if not binpath or binpath == "" then
        return false
    end

    if sys.call(string.format("pgrep -f %q >/dev/null 2>&1", binpath)) == 0 then
        return true
    end

    return sys.call(string.format("ps w 2>/dev/null | grep -v grep | grep -F %q >/dev/null 2>&1", binpath)) == 0
end

-- 检测 Clash 的 53 劫持目标端口（兼容 redirect to :PORT 与 dnat ... :PORT）
local function openclash_hijack_port()
    local out = sys.exec("nft list chain inet fw4 dstnat 2>/dev/null | grep 'Clash DNS Hijack' | head -n 1")
    if not out or out == "" then
        return ""
    end

    local p = out:match("redirect to :(%d+)") or out:match("dnat.*:(%d+)")
    return p or ""
end

local function openclash_running()
    return sys.call("pidof clash >/dev/null 2>&1") == 0
end

-- Clash 是否启用了自定义上游 DNS，且其中包含指向 AdGuard Home 的条目
local function openclash_upstream_agh(port)
    local found = false
    pcall(function()
        uci:foreach("openclash", "dns_servers", function(s)
            local enabled = tostring(s.enabled or "1")
            local sport = tostring(s.port or "")
            if enabled ~= "0" and s.group == "nameserver"
                and s.ip == "127.0.0.1" and sport == tostring(port) then
                found = true
            end
        end)
    end)
    return found
end

local function read_number(path)
    local v = fs.readfile(path)
    if not v then
        return nil
    end
    v = v:match("[-]?%d+")
    return v and tonumber(v) or nil
end

local function update_running()
    if not fs.access(RUN .. "_update.lock") then
        return false
    end

    local pid = read_number(RUN .. "_update.pid")
    if pid and pid > 0 and sys.call("kill -0 " .. tostring(pid) .. " >/dev/null 2>&1") == 0 then
        return true
    end

    -- 刚创建锁但 PID 尚未写入时，给任务一个短暂的启动时间
    local mtime = fs.stat(RUN .. "_update.lock", "mtime")
    if mtime and (os.time() - mtime) < 60 then
        return true
    end

    -- 锁文件已过期，清理后允许重新执行
    fs.remove(RUN .. "_update.lock")
    fs.remove(RUN .. "_update.pid")
    return false
end

local function action_running()
    if not fs.access(RUN .. "_action.running") then
        return false
    end

    local mtime = fs.stat(RUN .. "_action.running", "mtime")
    if mtime and (os.time() - mtime) > 300 then
        fs.remove(RUN .. "_action.running")
        return false
    end

    return true
end

local function start_action(cmd)
    fs.writefile(RUN .. "_action.code", "")
    fs.writefile(RUN .. "_action.running", "1")
    sys.exec("( " .. cmd .. "; rc=$?; echo $rc > " .. RUN .. "_action.code; rm -f " .. RUN .. "_action.running ) >" .. RUN .. "_action.log 2>&1 &")
end

local function check_token()
    local token = http.formvalue("token")
    if not token then
        return false
    end

    -- 与 LuCI 分发器使用同一个会话令牌。延迟 require，避免菜单扫描阶段初始化上下文失败。
    local expected = context and context.authtoken
    if not expected then
        local ok, disp = pcall(require, "luci.dispatcher")
        if ok and disp and disp.context then
            expected = disp.context.authtoken
        end
    end
    if expected then
        return token == expected
    end

    local ok, csrf = pcall(require, "luci.csrf")
    if ok and csrf and type(csrf.check) == "function" then
        return csrf.check(token)
    end

    return false
end

local function require_post()
    if not check_token() then
        http.status(403)
        http.prepare_content("text/plain; charset=utf-8")
        http.write("安全校验失败，请刷新页面后重试。")
        return false
    end

    return true
end

local function json_error(msg, code)
    http.status(code or 400)
    http.prepare_content("application/json")
    http.write_json({ ok = false, error = msg })
end

function index()
    local root = entry(
        { "admin", "services", "adguardhome_lite" },
        template("adguardhome_lite/wrapper"),
        "AdGuard Home 助手",
        60
    )
    root.dependent = true
    root.acl_depends = { "luci-app-adguardhome-lite" }

    -- 右侧独立页面在 iframe 中渲染，彻底隔离 LuCI 主题样式
    entry({ "admin", "services", "adguardhome_lite", "frame" }, template("adguardhome_lite/panel")).leaf = true

    -- 独立管理页面的 JSON 接口（不出现在菜单中）
    entry({ "admin", "services", "adguardhome_lite", "status" }, call("action_status")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "stats" }, call("action_stats")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "stats_clear" }, call("action_stats_clear")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "filters_get" }, call("action_filters_get")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "filters_save" }, call("action_filters_save")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "querylog_get" }, call("action_querylog_get")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "retention_save" }, call("action_retention_save")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "core_install" }, call("action_core_install")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "core_progress" }, call("action_core_progress")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "service" }, call("action_service")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "password" }, call("action_password")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "logs_raw" }, call("action_logs")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "settings_get" }, call("action_settings_get")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "settings_save" }, call("action_settings_save")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "yaml_get" }, call("action_yaml_get")).leaf = true
    entry({ "admin", "services", "adguardhome_lite", "yaml_save" }, call("action_yaml_save")).leaf = true
end

function action_status()
    local binpath = cfg("binpath", "/usr/bin/AdGuardHome/AdGuardHome")
    local configpath = cfg("config", "/etc/AdGuardHome.yaml")
    local workdir = cfg("workdir", "/etc/AdGuardHome")
    local dns_mode = cfg("dns_mode", "takeover")
    -- 「Clash 串联」已下线，历史配置在界面上按「接管 53 端口」展示
    if dns_mode == "openclash" then
        dns_mode = "takeover"
    end
    local dnsport = 5333
    if dns_mode == "takeover" then
        dnsport = 53
    elseif dns_mode == "clashfirst" then
        dnsport = 5335
    end
    local webport = tonumber(cfg("webport", "13800")) or 13800
    local password = cfg("adminpass", "admin123")
    local hijack_port = openclash_hijack_port()

    local data = {
        core = fs.access(binpath, "x") and true or false,
        version = core_version(binpath),
        running = service_running(binpath),
        enabled = is_enabled(),
        dns_mode = dns_mode,
        dns_port = dnsport,
        web_port = webport,
        config_path = configpath,
        config_exists = fs.access(configpath) and true or false,
        workdir = workdir,
        admin_user = cfg("adminuser", "admin"),
        admin_pass = password,
        channel = cfg("channel", "stable"),
        github_proxy = cfg("github_proxy", "gh-proxy.org"),
        mode_applied = cfg("mode_applied", "none"),
        openclash_hijack = hijack_port ~= "",
        openclash_hijack_port = hijack_port,
        openclash_running = openclash_running(),
        openclash_redirect = uci:get("openclash", "config", "enable_redirect_dns") or "",
        openclash_custom_dns = uci:get("openclash", "config", "enable_custom_dns") or "",
        openclash_upstream_agh = openclash_upstream_agh(dnsport),
        clash_dns_port = uci:get("openclash", "config", "dns_port") or "",
        dnsmasq_port = uci:get("dhcp", "@dnsmasq[0]", "port") or "53",
        -- 只有「接管 53」才需要检查收回规则，其它模式跳过 nft 调用
        dns_redirect = (dns_mode == "takeover")
            and (sys.call("nft list chain inet fw4 agh_dns_redirect 2>/dev/null | grep -q 'redirect to :53'") == 0)
            or false,
        agh_bypassed = cfg("agh_bypassed", "0"),
        update_running = update_running(),
        action_running = action_running(),
        action_code = read_number(RUN .. "_action.code"),
        plugin = plugin_update_info()
    }

    -- 统计跟着状态一起返回，前端一次请求即可刷新两块内容
    data.stats = collect_stats()

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json(data)
end

-- 从 AdGuard Home 本地接口读取过滤统计，插件页面无需打开控制台。
-- 结果缓存 8 秒：页面 10 秒轮询时每次都能拿到新数据，又不会重复请求。
collect_stats = function()
    local cached = read_cache(STATS_CACHE, 8)
    if cached then
        local ok, jsonc = pcall(require, "luci.jsonc")
        if ok then
            local parsed = jsonc.parse(cached)
            if type(parsed) == "table" then
                return parsed
            end
        end
    end

    local webport = tonumber(cfg("webport", "13800")) or 13800
    local auth = string.format("%s:%s", cfg("adminuser", "admin"), cfg("adminpass", "admin123"))
    local url = string.format("http://127.0.0.1:%d/control/stats", webport)
    local raw = sys.exec(string.format("curl -s -m 3 -u %q %s 2>/dev/null", auth, url))

    if not raw or raw == "" then
        return { ok = false, error = "AdGuard Home 未运行或统计接口不可用。" }
    end

    local ok_req, jsonc = pcall(require, "luci.jsonc")
    if not ok_req then
        return { ok = false, error = "缺少 luci-lib-jsonc，无法解析统计结果。" }
    end

    local stats = jsonc.parse(raw)
    if type(stats) ~= "table" then
        return { ok = false, error = "统计接口返回格式异常。" }
    end

    -- 防护/安全浏览/家长控制等开关直接读 YAML，省掉一次 HTTP 请求
    local yaml_text = fs.readfile(cfg("config", "/etc/AdGuardHome.yaml")) or ""

    local data = {
        ok = true,
        queries = stats.num_dns_queries or 0,
        blocked = stats.num_blocked_filtering or 0,
        malware = stats.num_replaced_safebrowsing or 0,
        adult = stats.num_replaced_parental or 0,
        safesearch = stats.num_replaced_safesearch or 0,
        avg = stats.avg_processing_time or 0,
        protection = yaml_text:match("\n  protection_enabled:%s*true") ~= nil,
        safebrowsing = yaml_text:match("\n  safebrowsing_enabled:%s*true") ~= nil,
        parental = yaml_text:match("\n  parental_enabled:%s*true") ~= nil,
        adult_filter = yaml_text:find("nsfw.txt", 1, true) ~= nil,
        top_blocked = {}
    }

    local top = stats.top_blocked_domains
    if type(top) == "table" then
        for i = 1, math.min(#top, 5) do
            local item = top[i]
            if type(item) == "table" then
                for domain, count in pairs(item) do
                    data.top_blocked[#data.top_blocked + 1] = { domain = domain, count = count }
                end
            end
        end
    end

    local encoded = jsonc.stringify(data)
    if encoded and encoded ~= "" then
        fs.writefile(STATS_CACHE, encoded)
    end

    return data
end

function action_stats()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json(collect_stats())
end

-- 清空 AdGuard Home 统计：调用官方 /control/stats_reset，并删除插件侧缓存
function action_stats_clear()
    if not require_post() then
        return
    end

    local webport = tonumber(cfg("webport", "13800")) or 13800
    local auth = string.format("%s:%s", cfg("adminuser", "admin"), cfg("adminpass", "admin123"))
    local url = string.format("http://127.0.0.1:%d/control/stats_reset", webport)
    local code = sys.exec(string.format(
        "curl -s -m 5 -o /dev/null -w '%%{http_code}' -X POST -u %q %s 2>/dev/null", auth, url))

    if code ~= "200" then
        json_error("清空统计失败，AdGuard Home 可能未运行。")
        return
    end

    sys.call("rm -f " .. STATS_CACHE)
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

-- 调用本机 AdGuard Home 控制接口，返回 HTTP 状态码和响应体
local function agh_api(path, method, body)
    local auth = string.format("%s:%s", cfg("adminuser", "admin"), cfg("adminpass", "admin123"))
    local port = tonumber(cfg("webport", "13800")) or 13800
    local url = string.format("http://127.0.0.1:%d%s", port, path)
    local req = "/tmp/agh_api_req.json"
    local res = "/tmp/agh_api_res.json"

    local cmd = string.format("curl -s -m 8 -o %s -w '%%{http_code}' -u %q", res, auth)
    if method == "POST" then
        if body then
            local f = io.open(req, "w")
            if f then
                f:write(body)
                f:close()
            end
            cmd = cmd .. " -H 'Content-Type: application/json' -X POST --data-binary @" .. req
        else
            cmd = cmd .. " -X POST"
        end
    end

    local code = sys.exec(cmd .. " " .. url .. " 2>/dev/null") or ""
    local resp = fs.readfile(res) or ""
    os.remove(req)
    os.remove(res)
    return code, resp
end

local function interval_days(value, default)
    local n, unit = tostring(value or ""):match("^(%d+)%s*([dhms])$")
    n = tonumber(n)
    if not n or n < 1 then
        return default
    end
    if unit == "h" then
        return math.max(1, math.floor(n / 24 + 0.5))
    elseif unit == "s" then
        return math.max(1, math.floor(n / 86400 + 0.5))
    end
    return n
end

function action_filters_get()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")

    local code, resp = agh_api("/control/filtering/status", "GET")
    if code ~= "200" then
        http.write_json({ ok = false, error = "读取过滤规则失败，请确认 AdGuard Home 正在运行。" })
        return
    end

    local okc, jsonc = pcall(require, "luci.jsonc")
    local data = okc and jsonc.parse(resp) or nil
    if not data then
        http.write_json({ ok = false, error = "解析过滤规则失败。" })
        return
    end

    -- AGH 的 /control/status 不返回这三个开关的状态，直接读 YAML 才准确。
    local fconfig = cfg("config", "/etc/AdGuardHome.yaml")
    local safesearch = yaml_safe_search_enabled(fconfig)
    local parental = (yaml_section_scalar(fconfig, "filtering", "parental_enabled") or "") == "true"
    local safebrowsing = (yaml_section_scalar(fconfig, "filtering", "safebrowsing_enabled") or "") == "true"

    -- AdGuard Home 把黑名单和白名单分成两个数组，这里合并返回并标记来源，
    -- 否则白名单订阅在插件里既看不到也删不掉。
    local filters = {}
    for _, f in ipairs(data.filters or {}) do
        if type(f) == "table" then
            f.whitelist = false
            filters[#filters + 1] = f
        end
    end
    for _, f in ipairs(data.whitelist_filters or {}) do
        if type(f) == "table" then
            f.whitelist = true
            filters[#filters + 1] = f
        end
    end

    http.write_json({
        ok = true,
        -- AGH 返回的字段名是 enabled，不是 filtering_enabled
        filtering_enabled = (data.enabled == true) or (data.filtering_enabled == true),
        filters = filters,
        user_rules = data.user_rules or {},
        safesearch = safesearch,
        parental = parental,
        safebrowsing = safebrowsing
    })
end

function action_filters_save()
    if not require_post() then
        return
    end

    local act = http.formvalue("action") or ""
    local okc, jsonc = pcall(require, "luci.jsonc")
    if not okc then
        json_error("缺少 luci-lib-jsonc，无法操作过滤规则。")
        return
    end

    local path, body
    if act == "add" then
        local url = (http.formvalue("url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local whitelist = http.formvalue("whitelist") == "1"
        if url == "" then
            json_error("请填写订阅地址。")
            return
        end
        -- AdGuard Home 只接受 http(s) 订阅地址，file:// 会在它那边报错
        if not url:match("^https?://%S+$") then
            json_error("订阅地址需以 http:// 或 https:// 开头。")
            return
        end
        if name == "" then
            name = url
        end
        path = "/control/filtering/add_url"
        body = jsonc.stringify({ name = name, url = url, whitelist = whitelist })
    elseif act == "toggle" then
        local url = http.formvalue("url") or ""
        local name = http.formvalue("name") or url
        local enabled = http.formvalue("enabled") == "1"
        local whitelist = http.formvalue("whitelist") == "1"
        if url == "" then
            json_error("缺少规则地址。")
            return
        end
        path = "/control/filtering/set_url"
        body = jsonc.stringify({
            url = url,
            whitelist = whitelist,
            data = { name = name, url = url, enabled = enabled, whitelist = whitelist }
        })
    elseif act == "remove" then
        local url = http.formvalue("url") or ""
        local whitelist = http.formvalue("whitelist") == "1"
        if url == "" then
            json_error("缺少规则地址。")
            return
        end
        path = "/control/filtering/remove_url"
        body = jsonc.stringify({ url = url, whitelist = whitelist })
    elseif act == "rules" then
        local raw = http.formvalue("rules") or ""
        local rules = {}
        for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                rules[#rules + 1] = line
            end
        end
        path = "/control/filtering/set_rules"
        body = jsonc.stringify({ rules = rules })
    elseif act == "feature" then
        local feature = http.formvalue("feature") or ""
        local value = http.formvalue("value") == "1"
        local allowed = { filtering = true, safesearch = true, parental = true, safebrowsing = true }
        if not allowed[feature] then
            json_error("不支持的开关。")
            return
        end

        if feature == "filtering" then
            -- filtering 没有单独的 enable/disable，走 config 接口
            local _, sresp = agh_api("/control/filtering/status", "GET")
            local st = jsonc.parse(sresp)
            local interval = st and tonumber(st.interval) or 24
            path = "/control/filtering/config"
            body = jsonc.stringify({ enabled = value, interval = interval })
        else
            path = string.format("/control/%s/%s", feature, value and "enable" or "disable")
        end
    else
        json_error("不支持的操作。")
        return
    end

    local code, resp = agh_api(path, "POST", body)
    if code ~= "200" then
        local detail = tostring(resp or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if #detail > 120 then
            detail = detail:sub(1, 120) .. "..."
        end
        if detail == "" then
            json_error("操作失败，AdGuard Home 可能未运行。")
        else
            json_error("操作失败：" .. detail)
        end
        return
    end

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_querylog_get()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")

    local code, resp = agh_api("/control/querylog?limit=20", "GET")
    if code ~= "200" then
        http.write_json({ ok = false, error = "读取查询日志失败，请确认 AdGuard Home 正在运行。" })
        return
    end

    local okc, jsonc = pcall(require, "luci.jsonc")
    local data = okc and jsonc.parse(resp) or nil
    local items = {}
    if data and data.data then
        for _, e in ipairs(data.data) do
            local q = e.question or {}
            local first = q[1] or q
            local client = e.client or ""
            if e.client_info and e.client_info.name and e.client_info.name ~= "" then
                client = e.client_info.name
            end
            items[#items + 1] = {
                time = e.time or "",
                client = client,
                domain = first.name or "",
                qtype = first.type or "",
                status = e.status or (e.result and e.result.status) or "",
                reason = e.reason or "",
                upstream = e.upstream or ""
            }
        end
    end

    http.write_json({ ok = true, data = items })
end

function action_retention_save()
    if not require_post() then
        return
    end

    local days = tonumber(http.formvalue("days") or "30")
    local query_days = tonumber(http.formvalue("query_days") or "30")
    if not days or days ~= math.floor(days) or days < 1 or days > 3650 then
        json_error("统计保留天数必须是 1-3650 之间的整数。")
        return
    end
    if not query_days or query_days ~= math.floor(query_days) or query_days < 1 or query_days > 3650 then
        json_error("查询日志保留天数必须是 1-3650 之间的整数。")
        return
    end

    local configpath = cfg("config", "/etc/AdGuardHome.yaml")
    if not fs.access(configpath) then
        json_error("尚未生成 AdGuard Home 配置文件。")
        return
    end

    if not yaml_set_section_scalar(configpath, "statistics", "interval", days .. "d")
        or not yaml_set_section_scalar(configpath, "querylog", "interval", query_days .. "d") then
        json_error("写入保留周期失败。")
        return
    end

    start_action("sh " .. SHARE .. "/apply_settings.sh")
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_core_install()
    if not require_post() then
        return
    end

    if update_running() then
        json_error("内核正在安装或更新，请等待当前任务完成。", 409)
        return
    end

    fs.writefile(RUN .. "_update.log", "正在启动内核安装任务...\n")
    fs.remove(RUN .. "_update.code")
    sys.exec("sh " .. SHARE .. "/update_core.sh >" .. RUN .. "_update.log 2>&1 &")

    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_core_progress()
    local log = fs.readfile(RUN .. "_update.log") or ""
    if #log > 24000 then
        log = string.sub(log, -24000)
    end

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({
        running = update_running(),
        log = log,
        code = read_number(RUN .. "_update.code")
    })
end

function action_service()
    if not require_post() then
        return
    end

    if update_running() then
        json_error("内核正在安装或更新，请稍候再操作服务。", 409)
        return
    end

    local act = http.formvalue("action") or ""
    local allowed = {
        start = true, stop = true, restart = true,
        enable = true, disable = true, bootstrap = true
    }
    if not allowed[act] then
        json_error("不支持的操作。")
        return
    end

    if act == "enable" or act == "bootstrap" or act == "start" then
        uci:set(CONF, "main", "enabled", "1")
        uci:commit(CONF)
        start_action("sh " .. SHARE .. "/apply_settings.sh")
    elseif act == "disable" or act == "stop" then
        uci:set(CONF, "main", "enabled", "0")
        uci:commit(CONF)
        start_action("sh " .. SHARE .. "/apply_settings.sh")
    elseif act == "restart" then
        start_action("/etc/init.d/adguardhome_lite restart")
    end

    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_password()
    if not require_post() then
        return
    end

    local hash = http.formvalue("hash") or ""
    local password = http.formvalue("password") or ""

    if #password < 8 then
        json_error("新密码至少需要 8 个字符。")
        return
    end
    if password:match("%c") then
        json_error("新密码不能包含换行等控制字符。")
        return
    end
    if #hash < 50 or not hash:match("^%$2[aby]%$%d%d%$[%w%./]+$") then
        json_error("密码哈希格式不正确，请刷新页面后重试。")
        return
    end
    if not fs.access(cfg("config", "/etc/AdGuardHome.yaml")) then
        json_error("配置文件尚未生成，请先启用服务。")
        return
    end

    local hashfile = RUN .. "_new_hash"
    local passfile = RUN .. "_new_pass"
    fs.writefile(hashfile, hash)
    fs.writefile(passfile, password)
    sys.call("chmod 600 " .. hashfile .. " " .. passfile .. " >/dev/null 2>&1")

    start_action("sh " .. SHARE .. "/set_password.sh")

    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_settings_get()
    local binpath = cfg("binpath", "/usr/bin/AdGuardHome/AdGuardHome")
    local configpath = cfg("config", "/etc/AdGuardHome.yaml")
    local mode = cfg("dns_mode", "takeover")
    if mode == "openclash" then
        mode = "takeover"
    end

    local cache_enabled = cache_option(configpath, "cache_enabled", "1")
    local cache_size_mb = tonumber(cache_option(configpath, "cache_size_mb", "16")) or 16
    local cache_ttl_min = tonumber(cache_option(configpath, "cache_ttl_min", "0")) or 0
    local cache_ttl_max = tonumber(cache_option(configpath, "cache_ttl_max", "0")) or 0
    local cache_optimistic = cache_option(configpath, "cache_optimistic", "0")

    local dns_crypto = cfg("dns_crypto", "off")
    local dns_crypto_custom = cfg("dns_crypto_custom", "")

    -- 加密预设只在「Clash 前置」且上游由插件管理时才会写入；
    -- 用户自定义上游时给界面提示，避免以为已经生效。
    local crypto_blocked = false
    if dns_crypto ~= "off" and dns_crypto ~= "" and mode == "clashfirst" then
        if cfg("upstream_source", "auto") == "custom" then
            crypto_blocked = true
        else
            local cur_up = yaml_list_values(configpath, "upstream_dns")
            local auto_up = uci:get(CONF, "main", "auto_upstream") or ""
            local self_ip = uci:get("network", "lan", "ipaddr") or ""
            local clash_port = cfg("clash_dns_port", "7874")
            local managed = false

            if auto_up ~= "" and cur_up == auto_up then
                managed = true
            end

            local known = {
                "",
                "127.0.0.1",
                "127.0.0.1:53",
                "127.0.0.1:1745",
                "127.0.0.1:5335",
                "127.0.0.1:" .. clash_port,
                "223.5.5.5 119.29.29.29"
            }
            for _, v in ipairs(known) do
                if cur_up == v then
                    managed = true
                    break
                end
            end
            if self_ip ~= "" and cur_up == self_ip then
                managed = true
            end

            crypto_blocked = not managed
        end
    end

    local upstream_source = cfg("upstream_source", "auto")
    if upstream_source ~= "custom" then
        upstream_source = "auto"
    end
    local upstream_custom = cfg("upstream_custom", "")
    local upstream_current = yaml_list_values(configpath, "upstream_dns")
    local stats_retention_days = interval_days(yaml_section_scalar(configpath, "statistics", "interval"), 30)
    local querylog_retention_days = interval_days(yaml_section_scalar(configpath, "querylog", "interval"), 30)

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({
        ok = true,
        enabled = is_enabled(),
        dns_mode = mode,
        webport = tonumber(cfg("webport", "13800")) or 13800,
        binpath = binpath,
        workdir = cfg("workdir", "/etc/AdGuardHome"),
        channel = cfg("channel", "stable"),
        github_proxy = cfg("github_proxy", "gh-proxy.org"),
        cache_enabled = cache_enabled == "1",
        cache_size_mb = cache_size_mb,
        cache_ttl_min = cache_ttl_min,
        cache_ttl_max = cache_ttl_max,
        cache_optimistic = cache_optimistic == "1",
        dns_crypto = dns_crypto,
        dns_crypto_custom = dns_crypto_custom,
        crypto_blocked = crypto_blocked,
        upstream_source = upstream_source,
        upstream_custom = upstream_custom,
        upstream_current = upstream_current,
        stats_retention_days = stats_retention_days,
        querylog_retention_days = querylog_retention_days,
        bypass_ifaces = join_words(uci:get(CONF, "main", "bypass_ifaces")),
        bypass_clients = join_words(uci:get(CONF, "main", "bypass_clients")),
        devices = net_devices(),
        openclash_installed = uci:get("openclash", "config") ~= nil,
        admin_user = cfg("adminuser", "admin"),
        admin_pass = cfg("adminpass", "admin123"),
        config_path = configpath,
        core = fs.access(binpath, "x") and true or false,
        version = core_version(binpath),
        running = service_running(binpath)
    })
end

function action_settings_save()
    if not require_post() then
        return
    end
    if update_running() then
        json_error("内核正在安装或更新，请等待完成后再保存设置。", 409)
        return
    end

    local enabled = http.formvalue("enabled") or "0"
    local mode = http.formvalue("dns_mode") or "takeover"
    local webport = http.formvalue("webport") or "13800"
    local binpath = http.formvalue("binpath") or "/usr/bin/AdGuardHome/AdGuardHome"
    local workdir = http.formvalue("workdir") or "/etc/AdGuardHome"
    local channel = http.formvalue("channel") or "stable"
    local proxy = http.formvalue("github_proxy") or "gh-proxy.org"
    local cache_enabled = http.formvalue("cache_enabled") or "1"
    local cache_size_raw = http.formvalue("cache_size_mb") or "16"
    local cache_ttl_min_raw = http.formvalue("cache_ttl_min") or "0"
    local cache_ttl_max_raw = http.formvalue("cache_ttl_max") or "0"
    local cache_optimistic = http.formvalue("cache_optimistic") or "0"
    local dns_crypto = http.formvalue("dns_crypto") or "off"
    local dns_crypto_custom = http.formvalue("dns_crypto_custom") or ""
    dns_crypto_custom = dns_crypto_custom:gsub("^%s+", ""):gsub("%s+$", "")
    local bypass_ifaces_raw = http.formvalue("bypass_ifaces") or ""
    local bypass_clients_raw = http.formvalue("bypass_clients") or ""

    if cache_enabled ~= "0" and cache_enabled ~= "1" then
        json_error("DNS 缓存开关参数不正确。")
        return
    end
    if cache_optimistic ~= "0" and cache_optimistic ~= "1" then
        json_error("乐观缓存参数不正确。")
        return
    end

    local cache_size_mb = tonumber(cache_size_raw)
    if not cache_size_mb or cache_size_mb ~= math.floor(cache_size_mb) or cache_size_mb < 1 or cache_size_mb > 256 then
        json_error("缓存大小必须是 1-256MB 之间的整数。")
        return
    end

    local cache_ttl_min = tonumber(cache_ttl_min_raw)
    local cache_ttl_max = tonumber(cache_ttl_max_raw)
    if not cache_ttl_min or cache_ttl_min ~= math.floor(cache_ttl_min) or cache_ttl_min < 0 or cache_ttl_min > 604800 then
        json_error("最小 TTL 必须是 0-604800 秒之间的整数。")
        return
    end
    if not cache_ttl_max or cache_ttl_max ~= math.floor(cache_ttl_max) or cache_ttl_max < 0 or cache_ttl_max > 604800 then
        json_error("最大 TTL 必须是 0-604800 秒之间的整数。")
        return
    end
    if cache_ttl_max > 0 and cache_ttl_min > cache_ttl_max then
        json_error("最小 TTL 不能大于最大 TTL；最大 TTL 为 0 表示不限制。")
        return
    end
    if cache_enabled == "0" then
        cache_optimistic = "0"
    end

    local allowed_crypto = {
        off = true, alidns = true, dnspod = true, cloudflare = true, custom = true
    }
    if not allowed_crypto[dns_crypto] then
        json_error("加密上游参数不正确。")
        return
    end
    if dns_crypto == "custom" then
        if dns_crypto_custom == "" then
            json_error("请填写自定义加密上游地址。")
            return
        end
        local valid_scheme = dns_crypto_custom:match("^https://%S+$")
            or dns_crypto_custom:match("^tls://%S+$")
            or dns_crypto_custom:match("^quic://%S+$")
            or dns_crypto_custom:match("^sdns://%S+$")
        if not valid_scheme then
            json_error("自定义加密上游需以 https://、tls://、quic:// 或 sdns:// 开头，且不能包含空格。")
            return
        end
    end

    if enabled ~= "0" and enabled ~= "1" then
        json_error("启用状态参数不正确。")
        return
    end

    local allowed_modes = {
        takeover = true, upstream = true, none = true, clashfirst = true
    }
    local allowed_bins = {
        ["/usr/bin/AdGuardHome/AdGuardHome"] = true,
        ["/tmp/AdGuardHome/AdGuardHome"] = true
    }
    local allowed_works = {
        ["/etc/AdGuardHome"] = true,
        ["/tmp/AdGuardHome"] = true
    }
    local allowed_channels = { stable = true, beta = true }
    local allowed_proxies = {
        none = true, ["gh-proxy.org"] = true, ["ghproxy.cc"] = true,
        ["ghproxy.com"] = true, ["ghfast.top"] = true
    }

    if not allowed_modes[mode] then
        json_error("DNS 接管方式不正确。")
        return
    end
    if not allowed_bins[binpath] then
        json_error("内核安装位置不正确。")
        return
    end
    if not allowed_works[workdir] then
        json_error("工作目录不正确。")
        return
    end
    if not allowed_channels[channel] then
        json_error("更新通道不正确。")
        return
    end
    if not allowed_proxies[proxy] then
        json_error("GitHub 反代选项不正确。")
        return
    end

    local upstream_source = http.formvalue("upstream_source") or "auto"
    local upstream_custom = http.formvalue("upstream_custom") or ""
    upstream_custom = upstream_custom:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    if upstream_source ~= "auto" and upstream_source ~= "custom" then
        json_error("上游 DNS 来源参数不正确。")
        return
    end
    if upstream_source == "custom" then
        if upstream_custom == "" then
            json_error("请填写自定义上游 DNS，或把来源改回「自动」。")
            return
        end
        if #upstream_custom > 1024 then
            json_error("自定义上游 DNS 过长，请精简后再保存。")
            return
        end
        for item in upstream_custom:gmatch("%S+") do
            local addr = item:gsub("^%[[^%]]*%]", "")
            local valid = addr:match("^https://%S+$")
                or addr:match("^tls://%S+$")
                or addr:match("^quic://%S+$")
                or addr:match("^sdns://%S+$")
                or addr:match("^[%w%._:%-]+$")
            if not valid then
                json_error("上游 DNS 格式不正确：" .. item)
                return
            end
        end
    end

    local ifaces, iface_seen = {}, {}
    for _, name in ipairs(split_words(bypass_ifaces_raw)) do
        if name == "lo" then
            json_error("不能把 lo（回环接口）设为排除接口。")
            return
        end
        if not valid_iface_name(name) then
            json_error("接口名不合法：" .. name .. "（仅支持字母、数字、下划线、点和短横线，最长 15 字符）。")
            return
        end
        if not iface_seen[name] then
            iface_seen[name] = true
            ifaces[#ifaces + 1] = name
        end
    end

    local clients, client_seen = {}, {}
    for _, spec in ipairs(split_words(bypass_clients_raw)) do
        if not valid_client_spec(spec) then
            json_error("客户端地址不合法：" .. spec .. "（支持 IPv4 / IPv6 地址或 CIDR）。")
            return
        end
        if not client_seen[spec] then
            client_seen[spec] = true
            clients[#clients + 1] = spec
        end
    end

    if #ifaces > 32 or #clients > 64 then
        json_error("排除项过多，接口最多 32 个、客户端最多 64 个。")
        return
    end

    local port = tonumber(webport)
    if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
        json_error("管理面板端口必须是 1-65535 之间的整数。")
        return
    end
    if port == 53 or port == 1745 or port == 5333 or port == 5335 then
        json_error("管理面板端口不能使用 53、1745、5333 或 5335。")
        return
    end

    if enabled == "1" and not fs.access(binpath, "x") then
        json_error("所选位置尚未安装内核，请先到概览页安装内核。")
        return
    end

    uci:set(CONF, "main", "enabled", enabled)
    uci:set(CONF, "main", "dns_mode", mode)
    uci:set(CONF, "main", "webport", tostring(port))
    uci:set(CONF, "main", "binpath", binpath)
    uci:set(CONF, "main", "workdir", workdir)
    uci:set(CONF, "main", "channel", channel)
    uci:set(CONF, "main", "github_proxy", proxy)
    uci:set(CONF, "main", "upstream_source", upstream_source)
    uci:set(CONF, "main", "upstream_custom", upstream_custom)
    uci:set(CONF, "main", "cache_enabled", cache_enabled)
    uci:set(CONF, "main", "cache_size_mb", tostring(cache_size_mb))
    uci:set(CONF, "main", "cache_ttl_min", tostring(cache_ttl_min))
    uci:set(CONF, "main", "cache_ttl_max", tostring(cache_ttl_max))
    uci:set(CONF, "main", "cache_optimistic", cache_optimistic)
    uci:set(CONF, "main", "dns_crypto", dns_crypto)
    uci:set(CONF, "main", "dns_crypto_custom", dns_crypto_custom)
    uci:delete(CONF, "main", "bypass_ifaces")
    for i = 1, #ifaces do
        uci:add_list(CONF, "main", "bypass_ifaces", ifaces[i])
    end
    uci:delete(CONF, "main", "bypass_clients")
    for i = 1, #clients do
        uci:add_list(CONF, "main", "bypass_clients", clients[i])
    end
    uci:commit(CONF)

    start_action("sh " .. SHARE .. "/apply_settings.sh")

    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_yaml_get()
    local configpath = cfg("config", "/etc/AdGuardHome.yaml")
    local yaml = fs.readfile(configpath) or ""

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({
        ok = true,
        path = configpath,
        enabled = is_enabled(),
        running = service_running(cfg("binpath", "/usr/bin/AdGuardHome/AdGuardHome")),
        yaml = yaml
    })
end

function action_yaml_save()
    if not require_post() then
        return
    end

    local yaml = http.formvalue("yaml")
    if not yaml then
        json_error("未收到配置内容。")
        return
    end
    if #yaml > 1048576 then
        json_error("配置文件过大，最大支持 1MB。")
        return
    end

    yaml = yaml:gsub("\r\n", "\n")
    local configpath = cfg("config", "/etc/AdGuardHome.yaml")
    local binpath = cfg("binpath", "/usr/bin/AdGuardHome/AdGuardHome")
    if not fs.access(binpath, "x") then
        json_error("尚未安装内核，无法校验配置。")
        return
    end

    local tmp = "/tmp/adguardhome_lite_yaml_test.yaml"
    fs.writefile(tmp, yaml)
    local rc = sys.call(string.format("%q --check-config -c %q >/var/run/adguardhome_lite_yaml_check.log 2>&1", binpath, tmp))
    if rc ~= 0 then
        local err = fs.readfile("/var/run/adguardhome_lite_yaml_check.log") or "未知错误"
        if #err > 1000 then
            err = string.sub(err, -1000)
        end
        json_error("配置校验失败：\n" .. err, 422)
        return
    end

    local old = fs.readfile(configpath) or ""
    fs.writefile(configpath .. ".bak", old)
    if not fs.writefile(configpath, yaml) then
        json_error("写入配置文件失败。")
        return
    end
    sys.call("chmod 600 " .. configpath .. " >/dev/null 2>&1")

    if is_enabled() then
        start_action("/etc/init.d/adguardhome_lite restart")
    end

    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

function action_logs()
    local syslog = sys.exec("logread 2>/dev/null | grep -i 'adguard' | tail -n 300") or ""
    local update = fs.readfile(RUN .. "_update.log") or ""
    local action = fs.readfile(RUN .. "_action.log") or ""

    http.header("Cache-Control", "no-store")
    http.prepare_content("text/plain; charset=utf-8")
    http.write("===== 系统日志（包含 AdGuard 关键字，最近 300 行） =====\n")
    http.write(syslog)
    http.write("\n\n===== 内核安装/更新日志 =====\n")
    http.write(update)
    http.write("\n\n===== 最近一次服务操作日志 =====\n")
    http.write(action)
end
