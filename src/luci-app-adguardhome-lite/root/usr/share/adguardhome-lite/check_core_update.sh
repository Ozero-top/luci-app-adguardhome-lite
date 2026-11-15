#!/bin/sh
# AdGuard Home 助手 - 检查内核是否有新版本（含预发布）
# 由控制器在缓存过期时后台调用，结果写入 /var/run/adguardhome_lite_core_update
# 说明：releases.atom 包含预发布标签，且不受 api.github.com 限流影响，可走反代

CACHE="/var/run/adguardhome_lite_core_update"
REPO="AdguardTeam/AdGuardHome"
FEED="https://github.com/$REPO/releases.atom"

fetch_tags() {
    _out=$(curl -fsS --connect-timeout 6 -m 15 "$1" 2>/dev/null) || return 1
    printf '%s' "$_out" | grep -o 'releases/tag/[^"]*' | sed 's#.*tag/##' | sed 's#^v##'
}

tags=""
for prefix in "" "https://gh-proxy.org/" "https://ghfast.top/"; do
    tags=$(fetch_tags "$prefix$FEED")
    [ -n "$tags" ] && break
done

# 网络不可达时保留旧结果，等待下一个 24 小时周期重试
[ -n "$tags" ] || exit 0

stable=$(printf '%s\n' "$tags" | grep -vE -- '-b\.?[0-9]' | head -n 1)
beta=$(printf '%s\n' "$tags" | grep -m 1 -E -- '-b\.?[0-9]')

{
    printf 'stable=%s\n' "$stable"
    printf 'beta=%s\n' "$beta"
    printf 'time=%s\n' "$(date +%s)"
} > "$CACHE"
