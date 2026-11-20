#!/bin/sh
# AdGuard Home 助手 - 检查插件是否有新版本
# 由控制器在缓存过期时后台调用，结果写入 /var/run/adguardhome_lite_plugin_update
# 说明：插件 Release 都是正式版，没有正式版 / 预发布版之分；
#       用 releases.atom 取最新标签，且不受 api.github.com 限流影响，可走反代

CACHE="/var/run/adguardhome_lite_plugin_update"
LOCK="/var/run/adguardhome_lite_plugin_update.lock"
REPO="Ozero-top/luci-app-adguardhome-lite"
FEED="https://github.com/$REPO/releases.atom"

# 避免多个页面同时刷新时重复请求 GitHub
if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

fetch_tag() {
    _out=$(curl -fsS --connect-timeout 6 -m 12 "$1" 2>/dev/null) || return 1
    printf '%s' "$_out" | grep -o 'releases/tag/[^"]*' | head -n 1 | sed 's#.*tag/##'
}

latest=""
for prefix in "" "https://gh-proxy.org/" "https://ghfast.top/"; do
    latest=$(fetch_tag "$prefix$FEED")
    [ -n "$latest" ] && break
done

# 网络不可达时不写缓存，控制器会在一小时后重试
[ -n "$latest" ] || exit 0

latest=${latest#v}

{
    printf 'latest=%s\n' "$latest"
    printf 'time=%s\n' "$(date +%s)"
} > "$CACHE"
