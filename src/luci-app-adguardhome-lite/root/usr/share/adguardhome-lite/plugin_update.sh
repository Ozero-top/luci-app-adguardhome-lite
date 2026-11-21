#!/bin/sh
# AdGuard Home 管理中心 - 插件在线更新
# 用法：plugin_update.sh <版本> <cn|github> <source|package> [force]
# 结果：$RUN_plugin_update.code（0=成功）；过程写入 $RUN_plugin_update.log

RUN="/var/run/adguardhome_lite"
LOG="${RUN}_plugin_update.log"
CODE="${RUN}_plugin_update.code"
RUNNING="${RUN}_plugin_update.running"
LOCK="${RUN}_plugin_update.lock"
SHARE_DIR="/usr/share/adguardhome-lite"
SOURCE_MARK="$SHARE_DIR/install_source"

# 更新会覆盖本脚本自身，先复制到 /tmp 再执行
case "$0" in
    /tmp/agh_plugin_update.*) ;;
    *)
        if ! cp -f "$0" "/tmp/agh_plugin_update.$$" 2>/dev/null; then
            echo 1 > "$CODE"
            exit 1
        fi
        exec sh "/tmp/agh_plugin_update.$$" "$@"
        ;;
esac

. /usr/share/adguardhome-lite/common.sh
load_conf

VER="${1:-}"
CHANNEL="${2:-cn}"
METHOD="${3:-source}"
FORCE="${4:-0}"

REPO="Ozero-top/luci-app-adguardhome-lite"
GITHUB="https://github.com/$REPO"
REL="$GITHUB/releases/download/v$VER"
JSD="https://cdn.jsdelivr.net/gh/$REPO@dist"
GH1="https://gh-proxy.org"
GH2="https://ghfast.top"

TMP=""
cleanup() {
    rm -rf "$LOCK"
    rm -f "$RUNNING"
    [ -n "$TMP" ] && rm -rf "$TMP"
    case "$0" in
        /tmp/agh_plugin_update.*) rm -f "$0" ;;
    esac
}
trap cleanup EXIT INT TERM

say() {
    log_progress "$*"
}

fail() {
    say "更新失败：$*"
    echo 1 > "$CODE"
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# 防止并发更新；异常退出留下的锁超过 30 分钟自动清理
lock_age() {
    _mt="$(stat -c %Y "$LOCK" 2>/dev/null || echo "")"
    [ -n "$_mt" ] || _mt="$(date -r "$LOCK" +%s 2>/dev/null || echo "")"
    [ -n "$_mt" ] || { echo 0; return; }
    echo $(( $(date +%s) - _mt ))
}

if ! mkdir "$LOCK" 2>/dev/null; then
    if [ "$(lock_age)" -gt 1800 ]; then
        rm -rf "$LOCK"
        if ! mkdir "$LOCK" 2>/dev/null; then
            say "已有更新任务在运行，请稍后再试。"
            echo 1 > "$CODE"
            exit 1
        fi
    else
        say "已有更新任务在运行，请稍后再试。"
        echo 1 > "$CODE"
        exit 1
    fi
fi
: > "$RUNNING"

case "$VER" in
    ''|*[!0-9A-Za-z.-]*) fail "目标版本无效：$VER" ;;
esac
case "$CHANNEL" in cn|github) ;; *) CHANNEL="cn" ;; esac
case "$METHOD" in source|package) ;; *) METHOD="source" ;; esac

TMP="$(mktemp -d /tmp/agh_plugin_update.XXXXXX 2>/dev/null)" || fail "创建临时目录失败"

case "$CHANNEL" in
    github)
        ASSET_MIRRORS="$REL $GH1/$REL $GH2/$REL $JSD"
        SRC_MIRRORS="$GITHUB $GH1/$GITHUB $GH2/$GITHUB"
        ;;
    *)
        ASSET_MIRRORS="$JSD $GH1/$REL $GH2/$REL $REL"
        SRC_MIRRORS="$GH1/$GITHUB $GH2/$GITHUB $GITHUB"
        ;;
esac

say "开始更新插件：v$VER（渠道：$CHANNEL，方式：$METHOD）"
[ "$FORCE" = "1" ] && say "强制更新/降级模式"

backup_config() {
    [ "$FORCE" = "1" ] || return 0
    if [ -f /etc/config/adguardhome_lite ]; then
        cp -p /etc/config/adguardhome_lite /etc/config/adguardhome_lite.bak 2>/dev/null \
            && say "已备份配置：/etc/config/adguardhome_lite.bak"
    fi
}

# 按渠道顺序下载，失败自动切换节点
mval() {
    sed -n "s/^$1=//p" "$MANIFEST" 2>/dev/null | head -n 1
}

clear_caches() {
    rm -f "${RUN}_plugin_version" "${RUN}_plugin_update" 2>/dev/null
    rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
    rm -rf /tmp/luci-modulecache 2>/dev/null
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1
    if [ "$(uci -q get adguardhome_lite.main.enabled 2>/dev/null)" = "1" ]; then
        say "重启 AdGuard Home 服务..."
        /etc/init.d/adguardhome_lite restart >/dev/null 2>&1
    fi
}

install_package() {
    MANIFEST="$TMP/manifest-$VER.txt"
    say "读取更新清单..."
    ok=0
    for _base in $ASSET_MIRRORS; do
        say "清单节点：$_base"
        if download_file "$_base/manifest-$VER.txt" "$MANIFEST" && [ -s "$MANIFEST" ]; then
            _ver="$(mval version)"
            [ "$_ver" = "$VER" ] && { ok=1; break; }
            say "清单版本不匹配：$_ver"
        fi
    done
    [ "$ok" = "1" ] || { say "获取更新清单失败"; return 1; }

    if have apk; then
        PM="apk"
        NAME="$(mval apk)"
        SHA="$(mval apk_sha256)"
        # apk 不能安装 ipk，缺 apk 资产时直接回退源码覆盖
        ALT_NAME=""
        ALT_SHA=""
    elif have opkg; then
        PM="opkg"
        NAME="$(mval modern)"
        SHA="$(mval modern_sha256)"
        ALT_NAME="$(mval legacy)"
        ALT_SHA="$(mval legacy_sha256)"
    else
        say "未找到 opkg 或 apk"
        return 1
    fi

    try_pkg() {
        _name="$1"
        _sha="$2"
        [ -n "$_name" ] || return 1
        _file="$TMP/$_name"
        for _base in $ASSET_MIRRORS; do
            say "安装包节点：$_base"
            if ! download_file "$_base/$_name" "$_file" || [ ! -s "$_file" ]; then
                say "该节点失败，切换下一个"
                continue
            fi
            _actual="$(sha256sum "$_file" 2>/dev/null | awk '{print $1}')"
            if [ "$_actual" != "$_sha" ]; then
                say "校验失败，切换下一个节点"
                continue
            fi
            say "校验通过：$_name"
            if [ "$PM" = "apk" ]; then
                if [ "$FORCE" = "1" ]; then
                    apk add --allow-untrusted --allow-downgrade "$_file" 2>/dev/null \
                        || apk add --allow-untrusted --force-overwrite "$_file" 2>/dev/null \
                        || apk add --allow-untrusted "$_file"
                else
                    apk add --allow-untrusted "$_file" 2>/dev/null \
                        || apk add --allow-untrusted --force-overwrite "$_file"
                fi
            else
                if [ "$FORCE" = "1" ]; then
                    opkg install --force-reinstall --force-downgrade "$_file"
                else
                    opkg install --force-reinstall "$_file"
                fi
            fi
            return $?
        done
        return 1
    }

    if try_pkg "$NAME" "$SHA"; then
        rm -f "$SOURCE_MARK"
        return 0
    fi
    if [ -n "$ALT_NAME" ] && [ "$ALT_NAME" != "$NAME" ]; then
        say "主安装包失败，尝试备用包：$ALT_NAME"
        if try_pkg "$ALT_NAME" "$ALT_SHA"; then
            rm -f "$SOURCE_MARK"
            return 0
        fi
    fi
    return 1
}

install_source() {
    say "下载源码包..."
    _tar="$TMP/src.tar.gz"
    _ok=0
    for _base in $SRC_MIRRORS; do
        say "源码节点：$_base"
        if download_file "$_base/archive/refs/tags/v$VER.tar.gz" "$_tar"; then
            [ -s "$_tar" ] && { _ok=1; break; }
        fi
    done
    [ "$_ok" = "1" ] || { say "源码包下载失败"; return 1; }

    mkdir -p "$TMP/src" || return 1
    tar -xzf "$_tar" -C "$TMP/src" || { say "源码包解压失败"; return 1; }
    _src="$(find "$TMP/src" -maxdepth 5 -type d -name 'luci-app-adguardhome-lite' -path '*/src/*' | head -n 1)"
    [ -n "$_src" ] && [ -d "$_src/root" ] || { say "源码包结构不完整"; return 1; }

    say "备份现有配置..."
    _keep=""
    if [ -f /etc/config/adguardhome_lite ]; then
        _keep="$TMP/keep_adguardhome_lite"
        cp -p /etc/config/adguardhome_lite "$_keep" || return 1
    fi

    say "覆盖插件文件..."
    cp -a "$_src/root/." / || return 1
    mkdir -p /usr/lib/lua/luci /www/luci-static/resources
    cp -a "$_src/luasrc/." /usr/lib/lua/luci/ || return 1
    cp -a "$_src/htdocs/." /www/ || return 1

    if [ -n "$_keep" ] && [ -f "$_keep" ]; then
        cp -p "$_keep" /etc/config/adguardhome_lite
    fi

    chmod 755 /etc/init.d/adguardhome_lite /etc/uci-defaults/50_luci-adguardhome-lite 2>/dev/null
    chmod 755 /usr/share/adguardhome-lite/*.sh 2>/dev/null
    chmod 644 /usr/share/adguardhome-lite/AdGuardHome.yaml.template 2>/dev/null
    [ -x /etc/uci-defaults/50_luci-adguardhome-lite ] && /etc/uci-defaults/50_luci-adguardhome-lite >/dev/null 2>&1
    printf '%s\n' "$VER" > "$SHARE_DIR/install_version" 2>/dev/null
    : > "$SOURCE_MARK" 2>/dev/null
    return 0
}

backup_config

if [ "$METHOD" = "package" ]; then
    if install_package; then
        clear_caches
        say "更新完成：v$VER（安装包方式）"
        echo 0 > "$CODE"
        exit 0
    fi
    say "安装包方式失败，自动改用源码覆盖"
fi

if install_source; then
    clear_caches
    say "更新完成：v$VER（源码覆盖）"
    echo 0 > "$CODE"
    exit 0
fi

fail "所有更新方式均失败，请查看日志或手动下载安装包"
