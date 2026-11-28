-- LuCI 插件代码跑在 LuCI 运行时里，全局变量由框架注入，这里只保留真正需要关注的问题
std = "lua51"
max_line_length = false

-- LuCI 控制器用 module() 定义菜单与动作，这些名字由 LuCI 运行时注入或作为模块字段导出
globals = {
    "module", "require", "package", "luci", "uci", "nixio", "ngx",
    "entry", "call", "template", "translate", "index",
    "action_status", "action_selftest",
    "action_yaml_get", "action_yaml_save",
    "action_filters_get", "action_filters_save",
    "action_settings_get", "action_settings_save",
    "action_logs", "action_querylog_get", "action_retention_save",
    "action_legacy_scan", "action_legacy_clean",
    "action_session", "action_password", "action_service",
    "action_stats_clear", "action_core_install", "action_core_progress",
    "action_plugin_update", "action_plugin_check", "action_plugin_progress",
}

-- ctx 解构已在 Round 6 收敛为只取用到的字段，恢复未使用变量检查
unused = true
unused_args = false
unused_secondaries = false
