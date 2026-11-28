-- YAML 模块单元测试：lua5.1 tests/lua/test_yaml.lua
-- 只测纯文本函数，避免依赖 nixio（CI 与 Windows 都没有）
package.path = "src/luci-app-adguardhome-lite/luasrc/?.lua;" .. package.path
local yaml = require "model.adguardhome_lite.yaml"

local failed = 0
local total = 0

local function check(name, actual, expected)
    total = total + 1
    if actual ~= expected then
        failed = failed + 1
        io.stderr:write(string.format("FAIL %s: got [%s], want [%s]\n",
            name, tostring(actual), tostring(expected)))
    end
end

local SAMPLE = [[
http:
  address: 0.0.0.0:13800
  session_ttl: 720h
dns:
  port: 53
  cache_enabled: true
  cache_size: 67108864
  cache_ttl_min: 60
  upstream_dns:
    - 127.0.0.1:1745
    - "223.5.5.5"
filtering:
  protection_enabled: true
  safebrowsing_enabled: false
  safe_search:
    enabled: true
statistics:
  interval: 24h
querylog:
  interval: 90d
]]

-- 顶层区块标量
check("http.address", yaml.scalar_text(SAMPLE, "http", "address"), "0.0.0.0:13800")
check("dns.port", yaml.scalar_text(SAMPLE, "dns", "port"), "53")
check("dns.cache_enabled", yaml.scalar_text(SAMPLE, "dns", "cache_enabled"), "true")
check("statistics.interval", yaml.scalar_text(SAMPLE, "statistics", "interval"), "24h")
check("querylog.interval", yaml.scalar_text(SAMPLE, "querylog", "interval"), "90d")

-- 三层嵌套
check("safe_search.enabled", yaml.scalar_text(SAMPLE, "filtering", "safe_search", "enabled"), "true")
check("missing key", yaml.scalar_text(SAMPLE, "dns", "not_exists"), nil)
check("missing section", yaml.scalar_text(SAMPLE, "nope", "port"), nil)

-- 引号与注释剥离
local QUOTED = [[
dns:
  upstream_dns:
    - "127.0.0.1:5335"
  bind_hosts:
    - 0.0.0.0   # 监听所有地址
  name: 'my-agh'
]]
check("strip comment", yaml.list_text(QUOTED, "dns", "bind_hosts"), "0.0.0.0")
check("single quote", yaml.scalar_text(QUOTED, "dns", "name"), "my-agh")
check("quoted list item", yaml.list_text(QUOTED, "dns", "upstream_dns"), "127.0.0.1:5335")

-- 列表三种写法
check("block list", yaml.list_text(SAMPLE, "dns", "upstream_dns"), "127.0.0.1:1745 223.5.5.5")
local INLINE = "dns:\n  upstream_dns: [1.1.1.1, 8.8.8.8]\n"
check("inline list", yaml.list_text(INLINE, "dns", "upstream_dns"), "1.1.1.1 8.8.8.8")
local SINGLE = "dns:\n  upstream_dns: 127.0.0.1:7874\n"
check("scalar list", yaml.list_text(SINGLE, "dns", "upstream_dns"), "127.0.0.1:7874")
check("empty list", yaml.list_text("dns:\n  upstream_dns: []\n", "dns", "upstream_dns"), "")

-- Tab 缩进等价于空格
local TABBED = "dns:\n\tport: 5353\n\tupstream_dns:\n\t\t- 9.9.9.9\n"
check("tab scalar", yaml.scalar_text(TABBED, "dns", "port"), "5353")
check("tab list", yaml.list_text(TABBED, "dns", "upstream_dns"), "9.9.9.9")

-- 区块写入：只改目标键，其余内容逐字保留
local updated = yaml.set_section_text(SAMPLE, "statistics", "interval", "30d")
check("write hits", updated ~= nil, true)
check("write applied", yaml.scalar_text(updated, "statistics", "interval"), "30d")
check("write keeps others", yaml.scalar_text(updated, "querylog", "interval"), "90d")
check("write keeps tail newline", updated:sub(-1), "\n")
check("write missing key", yaml.set_section_text(SAMPLE, "statistics", "missing", "x"), nil)
check("write missing section", yaml.set_section_text(SAMPLE, "nope", "interval", "x"), nil)

-- 写入不应越界改到下一个区块的同名键
local TWO = "statistics:\n  interval: 24h\nquerylog:\n  interval: 90d\n"
local two_out = yaml.set_section_text(TWO, "statistics", "interval", "7d")
check("write scoped", yaml.scalar_text(two_out, "querylog", "interval"), "90d")
check("write scoped target", yaml.scalar_text(two_out, "statistics", "interval"), "7d")

-- 重复写入幂等
local once = yaml.set_section_text(SAMPLE, "querylog", "interval", "30d")
local twice = yaml.set_section_text(once, "querylog", "interval", "30d")
check("write idempotent", once == twice, true)

if failed > 0 then
    io.stderr:write(string.format("%d/%d checks failed\n", failed, total))
    os.exit(1)
end

print(string.format("%d checks passed", total))
