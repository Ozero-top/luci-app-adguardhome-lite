#!/bin/sh
# AdGuard Home 助手 - 检查插件是否有新版本
# 由控制器在缓存过期时后台调用，结果写入 /var/run/adguardhome_lite_plugin_update

CACHE="/var/run/adguardhome_lite_plugin_update"
REPO="Ozero-top/luci-app-adguardhome-lite"
API="https://api.github.com/repos/$REPO/releases/latest"

fetch_tag() {
    _out=$(curl -fsS --connect-timeout 6 -m 10 "$1" 2>/dev/null) || return 1
    printf '%s' "$_out" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1
}

latest=""
for prefix in "" "https://gh-proxy.org/" "https://ghfast.top/"; do
    latest=$(fetch_tag "$prefix$API")
    [ -n "$latest" ] && break
done

# 网络不可达时保留旧结果，等待下一个 24 小时周期重试
[ -n "$latest" ] || exit 0

{
    printf 'latest=%s\n' "$latest"
    printf 'time=%s\n' "$(date +%s)"
} > "$CACHE"
