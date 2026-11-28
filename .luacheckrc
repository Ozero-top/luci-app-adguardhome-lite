-- LuCI 插件代码跑在 LuCI 运行时里，全局变量由框架注入，这里只保留真正需要关注的问题
std = "lua51"
max_line_length = false

globals = {
    "module", "require", "package", "luci", "uci", "nixio", "ngx",
}

-- ctx 解构已在 Round 6 收敛为只取用到的字段，恢复未使用变量检查
unused = true
unused_args = false
unused_secondaries = false
