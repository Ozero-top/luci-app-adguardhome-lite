#!/bin/sh
# AdGuard Home 一键版 - 公共函数库
# 本文件只被插件内的其他脚本引用，请不要直接执行。

CONF="adguardhome_lite"
AGH_SHARE="/usr/share/adguardhome-lite"
AGH_RUN="/var/run/adguardhome_lite"
AGH_UPDATE_LOG="/var/run/adguardhome_lite_update.log"
AGH_ACTION_LOG="/var/run/adguardhome_lite_action.log"

# 加载 OpenWrt 的 UCI shell 函数库
if [ -f /lib/functions.sh ]; then
    . /lib/functions.sh
fi

# 同时输出到系统日志和当前标准输出，方便在 LuCI 中查看进度
log_msg() {
    logger -t adguardhome_lite "$*" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] $*"
}

# 读取插件配置。所有变量均使用全局变量，供调用脚本直接使用。
load_conf() {
    if command -v config_load >/dev/null 2>&1; then
        config_load "$CONF" 2>/dev/null
    fi

    config_get enabled "main" enabled "0"
    config_get dns_mode "main" dns_mode "takeover"
    config_get webport "main" webport "13800"
    config_get binpath "main" binpath "/usr/bin/AdGuardHome/AdGuardHome"
    config_get configpath "main" config "/etc/AdGuardHome.yaml"
    config_get workdir "main" workdir "/etc/AdGuardHome"
    config_get channel "main" channel "stable"
    config_get github_proxy "main" github_proxy "gh-proxy.org"
    config_get adminuser "main" adminuser "admin"
    config_get adminpass "main" adminpass "admin123"
    config_get mode_applied "main" mode_applied "none"

    # OpenClash 的 DNS 端口（默认 7874），用于串联模式的上游
    clash_dns_port="$(uci -q get openclash.config.dns_port 2>/dev/null)"
    case "$clash_dns_port" in
        ''|*[!0-9]*) clash_dns_port="7874" ;;
    esac

    case "$dns_mode" in
        takeover) dnsport="53" ;;
        *) dnsport="5333" ;;
    esac
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# 解析 IPv4 地址；可指定公共 DNS，用于绕过 OpenClash/Clash 等 fake-IP DNS
resolve_ipv4() {
    _rhost="$1"
    _rdns="$2"

    if [ -n "$_rdns" ]; then
        _rout=$(nslookup "$_rhost" "$_rdns" 2>/dev/null)
    else
        _rout=$(nslookup "$_rhost" 2>/dev/null)
    fi

    echo "$_rout" | awk '$1 == "Address:" && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }'
}

# 下载文件；OpenWrt 上按可用性自动选择下载器
# 如果检测到 fake-IP DNS（198.18.0.0/16 等），使用 curl --resolve 指定真实 IP，
# 避免 OpenClash/Clash 的 fake-IP 路由异常导致下载超时。
download_file() {
    _url="$1"
    _out="$2"

    if have_cmd curl; then
        _scheme="${_url%%://*}"
        _rest="${_url#*://}"
        _hostport="${_rest%%/*}"
        _host="${_hostport%%:*}"
        _port="443"
        [ "$_scheme" = "http" ] && _port="80"
        case "$_hostport" in
            *:*) _port="${_hostport##*:}" ;;
        esac

        _resolve_opts=""
        if [ -n "$_host" ]; then
            _sys_ip=$(resolve_ipv4 "$_host")
            _real_ip=""

            # fake-IP 或系统 DNS 解析失败时，改用公共 DNS 获取真实 IP
            case "$_sys_ip" in
                198.18.*|198.19.*|"")
                    _real_ip=$(resolve_ipv4 "$_host" "223.5.5.5")
                    [ -n "$_real_ip" ] || _real_ip=$(resolve_ipv4 "$_host" "119.29.29.29")
                    case "$_real_ip" in
                        198.18.*|198.19.*) _real_ip="" ;;
                    esac
                    ;;
            esac

            if [ -n "$_real_ip" ]; then
                _resolve_opts="--resolve $_host:$_port:$_real_ip"
                log_msg "检测到 fake-IP DNS，使用真实 IP 下载：$_host -> $_real_ip"

                # GitHub 下载可能跳转到这些域名，提前映射真实 IP
                for _rh in objects.githubusercontent.com release-assets.githubusercontent.com; do
                    _rip=$(resolve_ipv4 "$_rh" "223.5.5.5")
                    case "$_rip" in
                        198.18.*|198.19.*|"") _rip="" ;;
                    esac
                    [ -n "$_rip" ] && _resolve_opts="$_resolve_opts --resolve $_rh:443:$_rip"
                done
            fi
        fi

        curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 2 $_resolve_opts -o "$_out" "$_url"
    elif have_cmd wget-ssl; then
        wget-ssl -q --timeout=15 --tries=2 -O "$_out" "$_url"
    elif have_cmd wget; then
        wget -q -T 15 -O "$_out" "$_url"
    elif have_cmd uclient-fetch; then
        uclient-fetch -q -T 15 -O "$_out" "$_url"
    else
        return 127
    fi
}

# 根据设备 CPU 架构匹配 AdGuard Home 官方发布包后缀
# 优先使用 opkg 的架构信息，因为部分 MIPS 设备 uname -m 无法区分大小端
detect_agh_arch() {
    _opkg_arch=$(opkg info kernel 2>/dev/null | awk -F '[: _]' '/^Architecture:/ {print $2; exit}')

    case "$_opkg_arch" in
        mipsel|mipsle) echo "mipsle_softfloat"; return ;;
        mips64el|mips64le) echo "mips64le_softfloat"; return ;;
        mips64) echo "mips64_softfloat"; return ;;
        mips) echo "mips_softfloat"; return ;;
        aarch64|arm64) echo "arm64"; return ;;
        x86_64|amd64) echo "amd64"; return ;;
        i386|i486|i586|i686) echo "386"; return ;;
        riscv64) echo "riscv64"; return ;;
        ppc64le) echo "ppc64le"; return ;;
    esac

    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64) echo "amd64" ;;
        i386|i486|i586|i686|x86) echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv8l|armv7l|armv7) echo "armv7" ;;
        armv6l|armv6) echo "armv6" ;;
        armv5tel|armv5l|armv5|arm) echo "armv5" ;;
        mips64el|mips64le) echo "mips64le_softfloat" ;;
        mips64) echo "mips64_softfloat" ;;
        mipsel|mipsle) echo "mipsle_softfloat" ;;
        mips) echo "mips_softfloat" ;;
        riscv64) echo "riscv64" ;;
        ppc64le|powerpc64le) echo "ppc64le" ;;
        *) echo "" ;;
    esac
}

# 获取目录可用空间（单位：KB）
free_kb() {
    df -k "$1" 2>/dev/null | awk 'NR==2 {gsub(/[^0-9].*/, "", $4); print $4 + 0}'
}

check_agh_config() {
    [ -x "$binpath" ] || return 0
    [ -f "$configpath" ] || return 1
    "$binpath" --check-config -c "$configpath" >/var/run/adguardhome_lite_check.log 2>&1
}

is_agh_running() {
    [ -n "$binpath" ] || return 1

    if have_cmd pgrep; then
        pgrep -f "$binpath" >/dev/null 2>&1 && return 0
    fi

    ps w 2>/dev/null | grep -v grep | grep -F "$binpath" >/dev/null 2>&1
}

# 强制结束残留的 AdGuard Home 进程（procd 停止失败或手动启动时使用）
force_stop_agh() {
    is_agh_running || return 0

    log_msg "检测到残留 AdGuard Home 进程，正在强制结束..."
    if have_cmd pgrep; then
        _pids=$(pgrep -f "$binpath" 2>/dev/null)
    else
        _pids=$(ps w 2>/dev/null | grep -v grep | grep -F "$binpath" | awk '{print $1}')
    fi

    for _pid in $_pids; do
        [ "$_pid" = "$$" ] && continue
        kill "$_pid" 2>/dev/null
    done

    sleep 2
    is_agh_running || return 0

    if have_cmd pgrep; then
        _pids=$(pgrep -f "$binpath" 2>/dev/null)
    else
        _pids=$(ps w 2>/dev/null | grep -v grep | grep -F "$binpath" | awk '{print $1}')
    fi
    for _pid in $_pids; do
        [ "$_pid" = "$$" ] && continue
        kill -9 "$_pid" 2>/dev/null
    done
}

restart_dnsmasq() {
    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
    fi
}

# 判断本机是否有进程监听指定端口（TCP 或 UDP）
port_listening() {
    _lp="$1"
    [ -n "$_lp" ] || return 1
    netstat -lntu 2>/dev/null | grep -qE "[:.]$_lp[[:space:]]"
}

# WAN 下发的上游 DNS（排除本机回环与 fake-IP 地址）
wan_dns_servers() {
    [ -s /tmp/resolv.conf.d/resolv.conf.auto ] || return 0
    awk '/^nameserver /{print $2}' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null \
        | grep -vE '^(127\.|::1|0\.0\.0\.0|fe80|198\.18\.)' \
        | head -n 2 | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# 计算可用于 AdGuard Home 的外部上游 DNS，避免指向自身或已停止的服务。
# 优先 Clash DNS，其次 WAN 下发的 DNS，最后才回退公共 DNS。
detect_upstream_dns() {
    if port_listening "$clash_dns_port"; then
        echo "127.0.0.1:$clash_dns_port"
        return
    fi

    _wan_dns="$(wan_dns_servers)"
    if [ -n "$_wan_dns" ]; then
        echo "$_wan_dns"
        return
    fi

    echo "223.5.5.5 119.29.29.29"
}

# OpenClash 是否仍在劫持 53 端口（返回重定向目标端口）
openclash_hijack_port() {
    have_cmd nft || return 0
    nft list chain inet fw4 dstnat 2>/dev/null \
        | grep 'OpenClash DNS Hijack' \
        | sed -n 's/.*redirect to :\([0-9][0-9]*\).*/\1/p' \
        | head -n 1
}

# 让 OpenClash 重新生成防火墙劫持规则（不重启 Clash 内核）
# 仅在 Clash 正在运行时执行，避免 OpenClash 未启动时无谓等待。
openclash_reload_rules() {
    [ -x /etc/init.d/openclash ] || return 1
    pidof clash >/dev/null 2>&1 || return 1

    /etc/init.d/openclash reload manual >/dev/null 2>&1

    _ri=0
    while [ "$_ri" -lt 10 ]; do
        sleep 1
        [ -n "$(openclash_hijack_port)" ] && return 0
        _ri=$(( _ri + 1 ))
    done
    return 1
}

# OpenClash 串联模式：在 /etc/dnsmasq.conf 写入默认转发规则，
# 让 DNSMasq 把所有域名查询交给 AdGuard Home，同时保留 OpenClash 的 DNS 劫持。
OC_CONF="/etc/dnsmasq.conf"
OC_BEGIN="# BEGIN adguardhome-lite-openclash"
OC_END="# END adguardhome-lite-openclash"

openclash_forward_present() {
    [ -f "$OC_CONF" ] && grep -qF "$OC_BEGIN" "$OC_CONF"
}

openclash_forward_del() {
    [ -f "$OC_CONF" ] || return 0
    grep -qF "$OC_BEGIN" "$OC_CONF" || return 0

    awk -v b="$OC_BEGIN" -v e="$OC_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip != 1 { print }
    ' "$OC_CONF" > "$OC_CONF.tmp.$$" && mv -f "$OC_CONF.tmp.$$" "$OC_CONF"
}

openclash_forward_add() {
    [ -f "$OC_CONF" ] || return 1
    openclash_forward_del

    {
        printf '\n%s\n' "$OC_BEGIN"
        # strict-order 保证优先查询 AdGuard Home；不可用时才回退到原 DNSMasq 上游
        printf 'strict-order\n'
        printf 'server=/#/127.0.0.1#%s\n' "$dnsport"
        printf '%s\n' "$OC_END"
    } >> "$OC_CONF"
}

# 读取 YAML 中某个两空格缩进的列表，返回空格分隔的一行
yaml_get_list() {
    _file="$1"
    _key="$2"
    [ -f "$_file" ] || return 1

    awk -v k="$_key" '
        $0 ~ "^  " k ":" { inlist = 1; next }
        inlist == 1 && /^    - / { sub(/^    - /, ""); print; next }
        { if (inlist == 1) inlist = 0 }
    ' "$_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# 修改 YAML 中某个两空格缩进的标量，例如 dns.port、http.address
yaml_set_scalar() {
    _file="$1"
    _key="$2"
    _value="$3"
    [ -f "$_file" ] || return 1

    awk -v k="$_key" -v v="$_value" '
        $0 ~ "^  " k ":" { print "  " k ": " v; next }
        { print }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}

# 替换 YAML 中某个两空格缩进的列表（列表项为四空格 "- "）
yaml_set_list() {
    _file="$1"
    _key="$2"
    _values="$3"
    [ -f "$_file" ] || return 1

    awk -v k="$_key" -v vals="$_values" '
        BEGIN { n = split(vals, a, " ") }
        $0 ~ "^  " k ":" {
            print "  " k ":"
            for (i = 1; i <= n; i++) print "    - " a[i]
            skip = 1
            next
        }
        skip == 1 && /^    - / { next }
        { skip = 0; print }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}
