#!/bin/sh
# AdGuard Home 助手 - 内核安装/更新脚本
# 功能：自动识别架构、下载官方最新稳定版/测试版、校验并替换内核。
# 说明：本脚本由 LuCI 概览页按钮调用，也可以手动执行。

. /usr/share/adguardhome-lite/common.sh

LOCK="/var/run/adguardhome_lite_update.lock"
PIDFILE="/var/run/adguardhome_lite_update.pid"
RESULT="/var/run/adguardhome_lite_update.code"
ARCHIVE=""
EXTRACT=""

die() {
    log_msg "错误：$*"
    exit 1
}

cleanup() {
    [ -n "$EXTRACT" ] && rm -rf "$EXTRACT"
    rm -rf "$LOCK"
    [ -n "$ARCHIVE" ] && rm -f "$ARCHIVE"
    rm -f "$PIDFILE" "/tmp/adguardhome_lite_core_check.log"
}

# 无论成功失败都写入结果码，供 LuCI 页面轮询
finish() {
    rc=$?
    echo "$rc" > "$RESULT"
    cleanup
    exit "$rc"
}

trap finish EXIT
trap 'exit 1' INT TERM

mkdir -p /var/run
rm -f "$RESULT"

# 防止重复执行
if mkdir "$LOCK" 2>/dev/null; then
    echo $$ > "$PIDFILE"
else
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        die "已有内核更新任务正在运行（PID $oldpid），请稍候。"
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || die "无法创建更新锁文件。"
    echo $$ > "$PIDFILE"
fi

load_conf

[ -n "$binpath" ] || die "内核路径为空，请到“基础设置”中检查配置。"
[ -n "$webport" ] || webport="13800"

arch=$(detect_agh_arch)
[ -n "$arch" ] || die "暂不支持当前设备架构：$(uname -m)。"

case "$channel" in
    beta)
        base_url="https://static.adguard.com/adguardhome/beta"
        channel_name="测试版"
        ;;
    *)
        base_url="https://static.adguard.com/adguardhome/release"
        channel_name="稳定版"
        ;;
esac

log_msg "开始安装 AdGuard Home 内核（${channel_name}）"
log_msg "设备架构：$arch，目标路径：$binpath"

# 尽量下载到内存盘，减少闪存写入
tmp_free=$(free_kb /tmp)
if [ -n "$tmp_free" ] && [ "$tmp_free" -lt 45000 ]; then
    log_msg "提示：/tmp 可用空间约 ${tmp_free}KB，若下载失败请改用内置存储或清理空间。"
fi

static_url="$base_url/AdGuardHome_linux_${arch}.tar.gz"
github_url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${arch}.tar.gz"

# GitHub 反代白名单，避免 UCI 中被写入任意地址
proxy_host=""
case "$github_proxy" in
    gh-proxy.org|ghproxy.cc|ghproxy.com|ghfast.top)
        proxy_host="$github_proxy"
        ;;
esac

url_list=""
if [ "$channel" = "beta" ]; then
    # 测试版只用官方 beta 通道，避免备用地址误装稳定版
    url_list="$static_url"
    log_msg "测试版使用官方 beta 下载通道。"
else
    if [ -n "$proxy_host" ]; then
        url_list="https://${proxy_host}/${github_url} $static_url $github_url"
        log_msg "已启用 GitHub 反代：$proxy_host（优先使用）"
    else
        url_list="$static_url $github_url"
    fi
fi

ARCHIVE="/tmp/adguardhome_lite_update_$$.tar.gz"
download_ok="0"
for _url in $url_list; do
    [ -n "$_url" ] || continue
    log_msg "下载地址：$_url"
    if download_file "$_url" "$ARCHIVE"; then
        # 部分反代失败时会返回 HTTP 200 的 HTML 错误页，必须校验压缩包内容
        if [ -s "$ARCHIVE" ] && tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
            download_ok="1"
            break
        fi
        log_msg "下载内容不是有效的内核压缩包，尝试下一个..."
    else
        log_msg "该地址下载失败，尝试下一个..."
    fi
    rm -f "$ARCHIVE"
done

[ "$download_ok" = "1" ] || die "下载失败，请检查路由器网络、DNS，或在“基础设置”中更换 GitHub 反代。"

[ -s "$ARCHIVE" ] || die "下载文件为空，请重试。"
tar -tzf "$ARCHIVE" >/dev/null 2>&1 || die "下载文件损坏，请重试。"

EXTRACT="/tmp/adguardhome_lite_extract_$$"
mkdir -p "$EXTRACT"
tar -xzf "$ARCHIVE" -C "$EXTRACT" || die "解压失败，可能是存储空间不足。"

newbin="$EXTRACT/AdGuardHome/AdGuardHome"
[ -f "$newbin" ] || die "安装包中未找到 AdGuardHome 可执行文件。"

chmod 755 "$newbin"

# 检查新内核能否在当前 CPU 上运行
newver=$("$newbin" --version 2>/dev/null | awk '
    NR == 1 {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[vV][0-9]/) {
                gsub(/[^vV0-9.].*/, "", $i)
                print $i
                exit
            }
        }
    }')
if [ -z "$newver" ]; then
    die "新内核无法在当前设备运行，可能是架构识别错误（识别结果：$arch）。"
fi

# 用新内核校验现有配置；避免升级后服务无法启动
if [ -s "$configpath" ]; then
    if ! "$newbin" --check-config -c "$configpath" >/tmp/adguardhome_lite_core_check.log 2>&1; then
        log_msg "$(cat /tmp/adguardhome_lite_core_check.log 2>/dev/null)"
        die "新内核无法解析现有配置文件，已取消更新。请先备份并检查配置。"
    fi
fi

newsize=$(wc -c < "$newbin" 2>/dev/null | tr -d ' ')
[ -n "$newsize" ] || die "无法读取新内核大小。"

targetdir=$(dirname "$binpath")
mkdir -p "$targetdir" || die "无法创建内核目录：$targetdir"

avail=$(free_kb "$targetdir")
need=$(( newsize / 1024 + 1024 ))
if [ -n "$avail" ] && [ "$avail" -lt "$need" ]; then
    die "目标分区空间不足：需要约 ${need}KB，可用约 ${avail}KB。请清理空间或把内核路径改为 /tmp。"
fi

# 记录当前服务状态
was_running=0
is_agh_running && was_running=1
was_enabled=$(uci -q get "$CONF.main.enabled" 2>/dev/null)
[ -n "$was_enabled" ] || was_enabled="0"

log_msg "正在停止服务并替换内核..."
/etc/init.d/adguardhome_lite stop >/dev/null 2>&1

i=0
while [ $i -lt 10 ]; do
    is_agh_running || break
    sleep 1
    i=$(( i + 1 ))
done

# 空间足够时保留一份旧内核，启动失败可自动回滚
backup=""
backup_need=$(( newsize / 1024 * 2 + 2048 ))
if [ -f "$binpath" ] && [ -n "$avail" ] && [ "$avail" -ge "$backup_need" ]; then
    if cp -f "$binpath" "$binpath.bak" 2>/dev/null; then
        backup="$binpath.bak"
    fi
fi

if ! cp -f "$newbin" "$binpath.new" 2>/dev/null; then
    die "复制内核失败，请检查目标分区空间。"
fi
chmod 755 "$binpath.new" 2>/dev/null
if ! mv -f "$binpath.new" "$binpath" 2>/dev/null; then
    rm -f "$binpath.new"
    die "替换内核失败，请检查文件权限或空间。"
fi

log_msg "内核已替换，版本：$newver，大小：$(( newsize / 1024 / 1024 ))MB"

# 如果原来在运行或已设置开机自启，则启动服务
if [ "$was_enabled" = "1" ] || [ "$was_running" = "1" ]; then
    log_msg "正在启动 AdGuard Home..."
    /etc/init.d/adguardhome_lite start >/dev/null 2>&1

    i=0
    while [ $i -lt 12 ]; do
        is_agh_running && break
        sleep 1
        i=$(( i + 1 ))
    done

    if ! is_agh_running; then
        log_msg "新内核启动失败，开始回滚..."
        /etc/init.d/adguardhome_lite stop >/dev/null 2>&1
        if [ -n "$backup" ] && [ -f "$backup" ]; then
            mv -f "$backup" "$binpath" 2>/dev/null
            /etc/init.d/adguardhome_lite start >/dev/null 2>&1
            die "新内核启动失败，已回滚到旧版本。请查看运行日志。"
        fi
        die "新内核启动失败，且没有可回滚的旧版本。请查看运行日志。"
    fi
fi

[ -n "$backup" ] && rm -f "$backup"

uci -q set "$CONF.main.core_version=$newver" 2>/dev/null
uci -q commit "$CONF" 2>/dev/null

log_msg "AdGuard Home 内核安装/更新成功：$newver"
exit 0
