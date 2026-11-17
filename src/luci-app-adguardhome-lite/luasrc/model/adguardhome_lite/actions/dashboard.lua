-- AdGuard Home 助手 - dashboard 动作
-- 依赖由控制器通过 ctx 注入，保持原有行为不变。

local M = {}

function M.status(ctx)
    local fs, http, sys, uci, util, codes, agh, selftest, split_words, join_words, valid_iface_name, valid_client_spec, version_newer, clean_tag, CONF, SHARE, RUN, STATS_CACHE, VERSION_CACHE, CORE_UPDATE, PLUGIN_UPDATE, INSTALL_VERSION, RELEASE_URL, collect_stats, read_cache, cfg, CACHE_YAML_KEYS, yaml_cache_scalar, yaml_list_values, yaml_safe_search_enabled, yaml_section_scalar, yaml_set_section_scalar, cache_option, IGNORED_IFACE_PATTERNS, iface_ignored, net_devices, is_enabled, core_version, core_update_info, plugin_version, plugin_update_info, service_running, openclash_hijack_port, openclash_running, openclash_upstream_agh, passwall_enabled, passwall_dns_port, read_number, update_running, action_running, start_action, check_token, require_post, default_reason, json_error, state_value, agh_client, agh_request, agh_api, interval_days = ctx.fs, ctx.http, ctx.sys, ctx.uci, ctx.util, ctx.codes, ctx.agh, ctx.selftest, ctx.split_words, ctx.join_words, ctx.valid_iface_name, ctx.valid_client_spec, ctx.version_newer, ctx.clean_tag, ctx.CONF, ctx.SHARE, ctx.RUN, ctx.STATS_CACHE, ctx.VERSION_CACHE, ctx.CORE_UPDATE, ctx.PLUGIN_UPDATE, ctx.INSTALL_VERSION, ctx.RELEASE_URL, ctx.collect_stats, ctx.read_cache, ctx.cfg, ctx.CACHE_YAML_KEYS, ctx.yaml_cache_scalar, ctx.yaml_list_values, ctx.yaml_safe_search_enabled, ctx.yaml_section_scalar, ctx.yaml_set_section_scalar, ctx.cache_option, ctx.IGNORED_IFACE_PATTERNS, ctx.iface_ignored, ctx.net_devices, ctx.is_enabled, ctx.core_version, ctx.core_update_info, ctx.plugin_version, ctx.plugin_update_info, ctx.service_running, ctx.openclash_hijack_port, ctx.openclash_running, ctx.openclash_upstream_agh, ctx.passwall_enabled, ctx.passwall_dns_port, ctx.read_number, ctx.update_running, ctx.action_running, ctx.start_action, ctx.check_token, ctx.require_post, ctx.default_reason, ctx.json_error, ctx.state_value, ctx.agh_client, ctx.agh_request, ctx.agh_api, ctx.interval_days
    local binpath = cfg("binpath", "/usr/bin/AdGuardHome/AdGuardHome")
    local configpath = cfg("config", "/etc/AdGuardHome.yaml")
    local workdir = cfg("workdir", "/etc/AdGuardHome")
    local dns_mode = cfg("dns_mode", "takeover")
    -- 「Clash 串联」已下线，历史配置在界面上按「接管 53 端口」展示
    if dns_mode == "openclash" then
        dns_mode = "takeover"
    end
    local dnsport = 5333
    if dns_mode == "takeover" or dns_mode == "passwall" then
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
        core_update = core_update_info(binpath, cfg("channel", "stable")),
        core_channel = cfg("core_channel", ""),
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
        -- 只有「接管 53」和「PassWall 前置」需要检查收回规则，其它模式跳过 nft 调用
        dns_redirect = (dns_mode == "takeover" or dns_mode == "passwall")
            and (sys.call("nft list chain inet fw4 agh_dns_redirect 2>/dev/null | grep -q 'redirect to :53'") == 0)
            or false,
        passwall_enabled = passwall_enabled(),
        passwall_dns_port = passwall_dns_port(),
        upstream_current = yaml_list_values(configpath, "upstream_dns"),
        upstream_source = cfg("upstream_source", "auto"),
        agh_bypassed = cfg("agh_bypassed", "0"),
        update_running = update_running(),
        action_running = action_running(),
        action_code = read_number(RUN .. "_action.code"),
        last_apply = state_value("last_apply"),
        last_update = state_value("last_update"),
        last_fallback = state_value("last_fallback"),
        plugin = plugin_update_info()
    }

    -- 统计跟着状态一起返回，前端一次请求即可刷新两块内容
    data.stats = collect_stats()

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json(data)
end

function M.stats(ctx)
    local fs, http, sys, uci, util, codes, agh, selftest, split_words, join_words, valid_iface_name, valid_client_spec, version_newer, clean_tag, CONF, SHARE, RUN, STATS_CACHE, VERSION_CACHE, CORE_UPDATE, PLUGIN_UPDATE, INSTALL_VERSION, RELEASE_URL, collect_stats, read_cache, cfg, CACHE_YAML_KEYS, yaml_cache_scalar, yaml_list_values, yaml_safe_search_enabled, yaml_section_scalar, yaml_set_section_scalar, cache_option, IGNORED_IFACE_PATTERNS, iface_ignored, net_devices, is_enabled, core_version, core_update_info, plugin_version, plugin_update_info, service_running, openclash_hijack_port, openclash_running, openclash_upstream_agh, passwall_enabled, passwall_dns_port, read_number, update_running, action_running, start_action, check_token, require_post, default_reason, json_error, state_value, agh_client, agh_request, agh_api, interval_days = ctx.fs, ctx.http, ctx.sys, ctx.uci, ctx.util, ctx.codes, ctx.agh, ctx.selftest, ctx.split_words, ctx.join_words, ctx.valid_iface_name, ctx.valid_client_spec, ctx.version_newer, ctx.clean_tag, ctx.CONF, ctx.SHARE, ctx.RUN, ctx.STATS_CACHE, ctx.VERSION_CACHE, ctx.CORE_UPDATE, ctx.PLUGIN_UPDATE, ctx.INSTALL_VERSION, ctx.RELEASE_URL, ctx.collect_stats, ctx.read_cache, ctx.cfg, ctx.CACHE_YAML_KEYS, ctx.yaml_cache_scalar, ctx.yaml_list_values, ctx.yaml_safe_search_enabled, ctx.yaml_section_scalar, ctx.yaml_set_section_scalar, ctx.cache_option, ctx.IGNORED_IFACE_PATTERNS, ctx.iface_ignored, ctx.net_devices, ctx.is_enabled, ctx.core_version, ctx.core_update_info, ctx.plugin_version, ctx.plugin_update_info, ctx.service_running, ctx.openclash_hijack_port, ctx.openclash_running, ctx.openclash_upstream_agh, ctx.passwall_enabled, ctx.passwall_dns_port, ctx.read_number, ctx.update_running, ctx.action_running, ctx.start_action, ctx.check_token, ctx.require_post, ctx.default_reason, ctx.json_error, ctx.state_value, ctx.agh_client, ctx.agh_request, ctx.agh_api, ctx.interval_days
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json(collect_stats())
end

function M.stats_clear(ctx)
    local fs, http, sys, uci, util, codes, agh, selftest, split_words, join_words, valid_iface_name, valid_client_spec, version_newer, clean_tag, CONF, SHARE, RUN, STATS_CACHE, VERSION_CACHE, CORE_UPDATE, PLUGIN_UPDATE, INSTALL_VERSION, RELEASE_URL, collect_stats, read_cache, cfg, CACHE_YAML_KEYS, yaml_cache_scalar, yaml_list_values, yaml_safe_search_enabled, yaml_section_scalar, yaml_set_section_scalar, cache_option, IGNORED_IFACE_PATTERNS, iface_ignored, net_devices, is_enabled, core_version, core_update_info, plugin_version, plugin_update_info, service_running, openclash_hijack_port, openclash_running, openclash_upstream_agh, passwall_enabled, passwall_dns_port, read_number, update_running, action_running, start_action, check_token, require_post, default_reason, json_error, state_value, agh_client, agh_request, agh_api, interval_days = ctx.fs, ctx.http, ctx.sys, ctx.uci, ctx.util, ctx.codes, ctx.agh, ctx.selftest, ctx.split_words, ctx.join_words, ctx.valid_iface_name, ctx.valid_client_spec, ctx.version_newer, ctx.clean_tag, ctx.CONF, ctx.SHARE, ctx.RUN, ctx.STATS_CACHE, ctx.VERSION_CACHE, ctx.CORE_UPDATE, ctx.PLUGIN_UPDATE, ctx.INSTALL_VERSION, ctx.RELEASE_URL, ctx.collect_stats, ctx.read_cache, ctx.cfg, ctx.CACHE_YAML_KEYS, ctx.yaml_cache_scalar, ctx.yaml_list_values, ctx.yaml_safe_search_enabled, ctx.yaml_section_scalar, ctx.yaml_set_section_scalar, ctx.cache_option, ctx.IGNORED_IFACE_PATTERNS, ctx.iface_ignored, ctx.net_devices, ctx.is_enabled, ctx.core_version, ctx.core_update_info, ctx.plugin_version, ctx.plugin_update_info, ctx.service_running, ctx.openclash_hijack_port, ctx.openclash_running, ctx.openclash_upstream_agh, ctx.passwall_enabled, ctx.passwall_dns_port, ctx.read_number, ctx.update_running, ctx.action_running, ctx.start_action, ctx.check_token, ctx.require_post, ctx.default_reason, ctx.json_error, ctx.state_value, ctx.agh_client, ctx.agh_request, ctx.agh_api, ctx.interval_days
    if not require_post() then
        return
    end

    local code = agh_request("/control/stats_reset", "POST")

    if code ~= "200" then
        json_error("清空统计失败，AdGuard Home 可能未运行。", nil, "stats_clear_failed")
        return
    end

    sys.call("rm -f " .. STATS_CACHE)
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({ ok = true })
end

return M
