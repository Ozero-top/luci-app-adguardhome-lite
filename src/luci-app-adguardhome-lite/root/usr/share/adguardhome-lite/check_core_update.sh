#!/bin/sh
# AdGuard Home 助手 - 检查内核是否有新版本（含预发布）
# 由控制器在缓存过期时后台调用，结果写入 /var/run/adguardhome_lite_core_update
#
# 数据源优先用 GitHub Releases API：只有它的 prerelease 字段能准确区分通道。
# 不能只按版本号里的 -b 判断，因为稳定版序列里也会出现 0.107.80-b.1 这类预发布标签。
# API 不可用时回退 releases.atom（仅最近 10 条），再按 -b.x 粗略区分。

CACHE="/var/run/adguardhome_lite_core_update"
REPO="AdguardTeam/AdGuardHome"
API="https://api.github.com/repos/$REPO/releases?per_page=30"
FEED="https://github.com/$REPO/releases.atom"

fetch() {
    curl -fsS --connect-timeout 6 -m 20 "$1" 2>/dev/null
}

# 从 API 返回的 JSON 中提取「标签 + prerelease 标记」，跳过 draft
parse_api() {
    awk '
    {
        line = $0
        if (line ~ /"tag_name"[[:space:]]*:/) {
            sub(/.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            tag = line
        } else if (line ~ /"draft"[[:space:]]*:/) {
            draft = (line ~ /true/) ? 1 : 0
        } else if (line ~ /"prerelease"[[:space:]]*:/) {
            pre = (line ~ /true/) ? 1 : 0
            if (tag != "") {
                if (draft != 1) print tag " " pre
                tag = ""
                draft = 0
            }
        }
    }'
}

stable=""
beta=""

data=""
for prefix in "" "https://gh-proxy.org/" "https://ghfast.top/"; do
    data=$(fetch "$prefix$API")
    [ -n "$data" ] && break
done

if [ -n "$data" ]; then
    list=$(printf '%s\n' "$data" | parse_api)
    if [ -n "$list" ]; then
        stable=$(printf '%s\n' "$list" | awk '$2 == 0 { print $1; exit }')
        beta=$(printf '%s\n' "$list" | awk '$2 == 1 { print $1; exit }')
    fi
fi

# API 被限流或不可用时回退 Atom
if [ -z "$stable" ] && [ -z "$beta" ]; then
    tags=""
    for prefix in "" "https://gh-proxy.org/" "https://ghfast.top/"; do
        _out=$(fetch "$prefix$FEED")
        [ -n "$_out" ] || continue
        tags=$(printf '%s' "$_out" | grep -o 'releases/tag/[^"]*' | sed 's#.*tag/##')
        [ -n "$tags" ] && break
    done
    if [ -n "$tags" ]; then
        stable=$(printf '%s\n' "$tags" | grep -vE -- '-b\.?[0-9]' | head -n 1)
        beta=$(printf '%s\n' "$tags" | grep -m 1 -E -- '-b\.?[0-9]')
    fi
fi

# 全部失败时保留旧结果，等待下一个 24 小时周期重试
[ -n "$stable" ] || [ -n "$beta" ] || exit 0

stable=${stable#v}
beta=${beta#v}

{
    printf 'stable=%s\n' "$stable"
    printf 'beta=%s\n' "$beta"
    printf 'time=%s\n' "$(date +%s)"
} > "$CACHE"
