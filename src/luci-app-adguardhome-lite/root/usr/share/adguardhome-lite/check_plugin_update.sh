#!/bin/sh
# AdGuard Home 助手 - 检查插件是否有新版本（含预发布）
# 由控制器在缓存过期时后台调用，结果写入 /var/run/adguardhome_lite_plugin_update
# 说明：releases.atom 包含预发布标签，且不受 api.github.com 限流影响，可走反代

CACHE="/var/run/adguardhome_lite_plugin_update"
REPO="Ozero-top/luci-app-adguardhome-lite"
FEED="https://github.com/$REPO/releases.atom"

fetch_tag() {
    _out=$(curl -fsS --connect-timeout 6 -m 12 "$1" 2>/dev/null) || return 1
    printf '%s' "$_out" | grep -o 'releases/tag/[^"]*' | head -n 1 | sed 's#.*tag/##'
}

latest=""
for prefix in "" "https://gh-proxy.org/" "https://ghfast.top/"; do
    latest=$(fetch_tag "$prefix$FEED")
    [ -n "$latest" ] && break
done

# 网络不可达时保留旧结果，等待下一个 24 小时周期重试
[ -n "$latest" ] || exit 0

latest=${latest#v}

beta=0
case "$latest" in
    *-B[0-9]*|*-b[0-9]*) beta=1 ;;
esac

{
    printf 'latest=%s\n' "$latest"
    printf 'beta=%s\n' "$beta"
    printf 'time=%s\n' "$(date +%s)"
} > "$CACHE"
