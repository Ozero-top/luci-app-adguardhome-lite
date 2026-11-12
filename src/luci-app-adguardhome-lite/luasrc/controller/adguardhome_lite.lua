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

-- 检测 OpenClash 的 53 劫持目标端口（兼容 redirect to :PORT 与 dnat ... :PORT）
local function openclash_hijack_port()
    local out = sys.exec("nft list chain inet fw4 dstnat 2>/dev/null | grep 'OpenClash DNS Hijack' | head -n 1")
    if not out or out == "" then
        return ""
    end

    local p = out:match("redirect to :(%d+)") or out:match("dnat.*:(%d+)")
    return p or ""
end

local function openclash_running()
    return sys.call("pidof clash >/dev/null 2>&1") == 0
end

-- OpenClash 是否启用了自定义上游 DNS，且其中包含指向 AdGuard Home 的条目
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
    -- 「OpenClash 串联」已下线，历史配置在界面上按「接管 53 端口」展示
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
        adult_block = cfg("adult_block", "0") == "1",
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
    local adult = http.formvalue("adult_block") or "0"

    if adult ~= "0" and adult ~= "1" then
        json_error("成人内容拦截参数不正确。")
        return
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
    uci:set(CONF, "main", "adult_block", adult)
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
