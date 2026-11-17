-- 纯函数单元测试：lua5.1 tests/lua/test_util.lua
package.path = "src/luci-app-adguardhome-lite/luasrc/?.lua;" .. package.path
local util = require "model.adguardhome_lite.util"

local failed = 0
local total = 0

local function check(name, actual, expected)
    total = total + 1
    if actual ~= expected then
        failed = failed + 1
        io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(actual), tostring(expected)))
    end
end

-- 地址校验
check("ipv4 ok", util.valid_ipv4("192.168.1.1"), true)
check("ipv4 overflow", util.valid_ipv4("192.168.1.256"), false)
check("ipv4 short", util.valid_ipv4("1.2.3"), false)
check("ipv6 full", util.valid_ipv6("2001:db8::1"), true)
check("ipv6 triple colon", util.valid_ipv6("2001:::1"), false)
check("ipv6 bad char", util.valid_ipv6("2001:db8::zz"), false)

-- 客户端规格
check("client ip", util.valid_client_spec("10.0.0.1"), true)
check("client cidr", util.valid_client_spec("10.0.0.0/8"), true)
check("client cidr overflow", util.valid_client_spec("10.0.0.0/33"), false)
check("client v6", util.valid_client_spec("fd00::1"), true)

-- 接口名
check("iface ok", util.valid_iface_name("br-guest"), true)
check("iface too long", util.valid_iface_name("abcdefghijklmnop"), false)
check("iface bad char", util.valid_iface_name("br guest"), false)

-- 版本比较
check("stable newer than beta", util.version_newer("0.107.59", "0.107.59-b.2"), true)
check("beta newer than older stable", util.version_newer("0.108.0-b.1", "0.107.59"), true)
check("same version", util.version_newer("0.107.59", "0.107.59"), false)
check("numeric compare", util.version_newer("0.107.100", "0.107.99"), true)
check("clean tag", util.clean_tag(" v1.2.3 "), "1.2.3")

-- 词表
check("split", table.concat(util.split_words("a bb  ccc"), ","), "a,bb,ccc")
check("join table", util.join_words({"a", "bb"}), "a bb")
check("join scalar", util.join_words(nil), "")

-- reason code 注册表
local codes = require "model.adguardhome_lite.codes"
check("known code", codes.known("update_busy"), true)
check("unknown code", codes.known("not_a_code"), false)
check("warn level", codes.level("update_busy"), "warn")
check("default level", codes.level("not_a_code"), "error")

if failed > 0 then
    io.stderr:write(string.format("%d/%d checks failed\n", failed, total))
    os.exit(1)
end

print(string.format("%d checks passed", total))
