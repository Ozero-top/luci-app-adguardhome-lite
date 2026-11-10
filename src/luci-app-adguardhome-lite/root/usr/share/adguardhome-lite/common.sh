#!/bin/sh
# AdGuard Home 助手 - 公共函数库
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
    config_get adult_block "main" adult_block "0"
    config_get mode_applied "main" mode_applied "none"

    # OpenClash 的 DNS 端口（默认 7874），用于串联模式的上游
    clash_dns_port="$(uci -q get openclash.config.dns_port 2>/dev/null)"
    case "$clash_dns_port" in
        ''|*[!0-9]*) clash_dns_port="7874" ;;
    esac

    case "$dns_mode" in
        takeover) dnsport="53" ;;
        clashfirst) dnsport="5335" ;;
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

# “OpenClash 前置”模式使用的真实上游：AdGuard Home 位于 Clash 之后，
# 上游必须是真实 DNS，绝不能是 Clash（7874）或本机 53，否则会形成查询环。
detect_real_upstream_dns() {
    _wan_dns="$(wan_dns_servers)"
    if [ -n "$_wan_dns" ]; then
        echo "$_wan_dns"
        return
    fi

    echo "223.5.5.5 119.29.29.29"
}

# OpenClash 是否仍在劫持 53 端口（返回重定向目标端口）
# 兼容两种规则写法：redirect to :7874 和 dnat [ip] to 127.0.0.1:7874
openclash_hijack_port() {
    have_cmd nft || return 0

    _oc_line=$(nft list chain inet fw4 dstnat 2>/dev/null | grep 'OpenClash DNS Hijack' | head -n 1)
    [ -n "$_oc_line" ] || return 0

    _oc_port=$(echo "$_oc_line" | sed -n 's/.*redirect to :\([0-9][0-9]*\).*/\1/p')
    if [ -z "$_oc_port" ]; then
        _oc_port=$(echo "$_oc_line" | sed -n 's/.*dnat.*:\([0-9][0-9]*\).*/\1/p')
    fi
    echo "$_oc_port"
}

# DNSMasq 实际读取的 conf-dir：优先从 OpenWrt 生成的临时配置解析，
# 回退到 /tmp/dnsmasq.d（与 OpenClash 使用的位置一致）。
dnsmasq_confdir() {
    _dcd=""
    for _dcf in /tmp/etc/dnsmasq.conf.*; do
        [ -f "$_dcf" ] || continue
        _dcv=$(sed -n 's/^conf-dir=\([^,]*\).*/\1/p' "$_dcf" 2>/dev/null | head -n 1)
        if [ -n "$_dcv" ]; then
            _dcd="$_dcv"
            break
        fi
    done
    [ -n "$_dcd" ] || _dcd="/tmp/dnsmasq.d"
    echo "$_dcd"
}

# dnsmasq 2.86 起支持 server=/#/，旧版本只能用 server=/./ 表示所有域名
dnsmasq_hash_rule_supported() {
    _dvv=$(dnsmasq --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -n 1)
    [ -n "$_dvv" ] || return 0

    _dvmaj=${_dvv%%.*}
    _dvrest=${_dvv#*.}
    _dvmin=${_dvrest%%.*}
    [ "$_dvmaj" -ge 3 ] 2>/dev/null && return 0
    if [ "$_dvmaj" -eq 2 ] 2>/dev/null && [ "$_dvmin" -ge 86 ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# OpenClash 串联模式：在 DNSMasq 的 conf-dir 写入带标记的默认转发规则，
# 让 DNSMasq 把域名查询交给 AdGuard Home。
# 不再写 /etc/dnsmasq.conf：OpenWrt 上该文件不会被 DNSMasq 读取。
OC_CONF="/etc/dnsmasq.conf"
OC_FILE="adguardhome-lite.conf"
OC_BEGIN="# BEGIN adguardhome-lite-openclash"
OC_END="# END adguardhome-lite-openclash"

oc_conf_path() {
    echo "$(dnsmasq_confdir)/$OC_FILE"
}

openclash_forward_present() {
    _ocp="$(oc_conf_path)"
    [ -f "$_ocp" ] && grep -qF "$OC_BEGIN" "$_ocp" && return 0
    [ -f "$OC_CONF" ] && grep -qF "$OC_BEGIN" "$OC_CONF" && return 0
    return 1
}

openclash_forward_del() {
    _ocp="$(oc_conf_path)"
    [ -f "$_ocp" ] && rm -f "$_ocp"

    [ -f "$OC_CONF" ] || return 0
    grep -qF "$OC_BEGIN" "$OC_CONF" || return 0

    awk -v b="$OC_BEGIN" -v e="$OC_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip != 1 { print }
    ' "$OC_CONF" > "$OC_CONF.tmp.$$" && mv -f "$OC_CONF.tmp.$$" "$OC_CONF"
}

openclash_forward_add() {
    _ocdir="$(dnsmasq_confdir)"
    mkdir -p "$_ocdir" 2>/dev/null || return 1

    openclash_forward_del

    {
        printf '%s\n' "$OC_BEGIN"
        # strict-order：DNSMasq 有多个上游时按顺序优先查询 AdGuard Home，
        # 避免轮询到 WAN DNS 造成过滤被绕过；AdGuard Home 不可用时仍可回退。
        printf 'strict-order\n'
        if dnsmasq_hash_rule_supported; then
            printf 'server=/#/127.0.0.1#%s\n' "$dnsport"
        else
            printf 'server=/./127.0.0.1#%s\n' "$dnsport"
        fi
        printf '%s\n' "$OC_END"
    } > "$_ocdir/$OC_FILE"
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
            if (n == 0 || vals == "") {
                print "  " k ": []"
                skip = 1
                next
            }
            print "  " k ":"
            for (i = 1; i <= n; i++) print "    - " a[i]
            skip = 1
            next
        }
        skip == 1 && /^    - / { next }
        { skip = 0; print }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}

# 修正 ratelimit_whitelist 格式：AdGuard Home 只接受单个 IP，不接受 CIDR。
# 旧版本曾写入 127.0.0.0/8、::1/128，会导致 --check-config 失败、服务无法启动。
yaml_fix_ratelimit_whitelist() {
    _file="$1"
    [ -f "$_file" ] || return 1
    grep -q 'ratelimit_whitelist' "$_file" 2>/dev/null || return 0

    awk '
        /^  ratelimit_whitelist:/ { inblk = 1; print; next }
        inblk && /^    - / {
            gsub(/127\.0\.0\.0\/8/, "127.0.0.1")
            gsub(/::1\/128/, "::1")
            print
            next
        }
        inblk { inblk = 0 }
        { print }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}

# 修改 YAML 中顶格（0 缩进）的标量，例如 http_proxy
yaml_set_root_scalar() {
    _file="$1"
    _key="$2"
    _value="$3"
    [ -f "$_file" ] || return 1

    awk -v k="$_key" -v v="$_value" '
        $0 ~ "^" k ":" { print k ": \"" v "\""; next }
        { print }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}

###
# filters 列表的增删（用于可选的成人内容拦截规则）
###

ADULT_FILTER_URL="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt"
ADULT_FILTER_NAME="HaGeZi NSFW（成人内容）"
ADULT_FILTER_ID="1794300001"

# 过滤列表下载走 Clash 的 HTTP 代理：国内直连 GitHub 常被重置，
# 交给 Clash 代理后 AGH 才能正常更新规则。
detect_http_proxy() {
    _hp="$(uci -q get openclash.config.http_port 2>/dev/null)"
    case "$_hp" in
        ''|*[!0-9]*) _hp="" ;;
    esac
    if [ -n "$_hp" ] && port_listening "$_hp"; then
        echo "http://127.0.0.1:$_hp"
        return
    fi
    echo ""
}

# 判断 filters 中是否已存在指定 URL
yaml_filter_present() {
    _file="$1"
    _url="$2"
    [ -f "$_file" ] || return 1
    grep -qF "url: $_url" "$_file"
}

# 在 filters: 列表末尾追加一条规则（已存在则跳过）
yaml_filter_add() {
    _file="$1"
    _url="$2"
    _name="$3"
    _id="$4"
    [ -f "$_file" ] || return 1
    yaml_filter_present "$_file" "$_url" && return 0

    awk -v url="$_url" -v name="$_name" -v id="$_id" '
        { line[NR] = $0 }
        END {
            start = 0
            for (i = 1; i <= NR; i++) {
                if (line[i] ~ /^filters:/) { start = i; break }
            }
            if (start == 0) exit 1

            # 找到 filters 段最后一个列表项的最后一行
            last = start
            for (i = start + 1; i <= NR; i++) {
                if (line[i] ~ /^[^ ]/ && line[i] != "") break
                if (line[i] ~ /^  - / || line[i] ~ /^    [a-z_]+:/) last = i
            }

            for (i = 1; i <= NR; i++) {
                print line[i]
                if (i == last) {
                    print "  - enabled: true"
                    print "    url: " url
                    print "    name: " name
                    print "    id: " id
                }
            }
        }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}

# 从 filters: 列表中删除指定 URL 的规则（不存在则跳过）
yaml_filter_remove() {
    _file="$1"
    _url="$2"
    [ -f "$_file" ] || return 0
    yaml_filter_present "$_file" "$_url" || return 0

    awk -v url="$_url" '
        { line[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (line[i] ~ /^  - /) {
                    end = i
                    for (j = i + 1; j <= NR; j++) {
                        if (line[j] ~ /^    /) end = j
                        else break
                    }
                    hit = 0
                    for (j = i; j <= end; j++) {
                        if (index(line[j], "url: " url) > 0) hit = 1
                    }
                    if (hit) { i = end; continue }
                }
                print line[i]
            }
        }
    ' "$_file" > "$_file.tmp.$$" && mv -f "$_file.tmp.$$" "$_file"
}

###
# OpenClash 前置（clashfirst）模式：让 Clash 的 DNS 上游只指向 AdGuard Home
###

clashfirst_disable_upstream() {
    _nds_sid="$1"
    config_get _nds_grp "$_nds_sid" group ""
    # nameserver 和 fallback 都会给 Clash 提供绕过 AdGuard Home 的解析路径
    case "$_nds_grp" in
        nameserver|fallback) ;;
        *) return 0 ;;
    esac
    config_get_bool _nds_en "$_nds_sid" enabled 1
    [ "$_nds_en" = "0" ] && return 0

    uci -q set "openclash.$_nds_sid.enabled=0"
    _oc_disabled="$_oc_disabled $_nds_sid"
}

# 关闭 OpenClash 原有 nameserver 组，仅保留指向 AdGuard Home 的上游。
# 返回值：0 成功；2 未安装 OpenClash；3 OpenClash 版本不支持自定义 DNS。
clashfirst_openclash_apply() {
    uci -q get openclash.config >/dev/null 2>&1 || return 2
    uci -q get openclash.config.enable_custom_dns >/dev/null 2>&1 || return 3

    # 清理上一次可能残留的设置（不重启 OpenClash）
    clashfirst_openclash_restore >/dev/null 2>&1

    _old_cd=$(uci -q get openclash.config.enable_custom_dns)
    [ -n "$_old_cd" ] || _old_cd="0"
    _old_wan=$(uci -q get openclash.config.append_wan_dns)
    [ -n "$_old_wan" ] || _old_wan="0"

    _oc_disabled=""
    config_load openclash 2>/dev/null
    config_foreach clashfirst_disable_upstream dns_servers

    _sid=$(uci add openclash dns_servers) || return 1
    # 注意不要写成 foo='bar'，否则引号会进入 UCI 值，OpenClash 读不到合法值
    uci -q set "openclash.$_sid.group=nameserver"
    uci -q set "openclash.$_sid.ip=127.0.0.1"
    uci -q set "openclash.$_sid.port=$dnsport"
    uci -q set "openclash.$_sid.type=udp"
    uci -q set "openclash.$_sid.enabled=1"
    uci -q set openclash.config.enable_custom_dns=1
    # 不再追加 WAN DNS，否则 Clash 会同时查询运营商 DNS，部分查询绕过过滤
    uci -q set openclash.config.append_wan_dns=0

    uci -q set "$CONF.main.oc_agh_sid=$_sid"
    uci -q set "$CONF.main.oc_old_custom_dns=$_old_cd"
    uci -q set "$CONF.main.oc_old_append_wan_dns=$_old_wan"
    uci -q set "$CONF.main.oc_disabled_sids=$_oc_disabled"

    uci -q commit openclash 2>/dev/null
    uci -q commit "$CONF" 2>/dev/null
    return 0
}

# 恢复 OpenClash 的原有 DNS 上游设置
clashfirst_openclash_restore() {
    _r_sid=$(uci -q get "$CONF.main.oc_agh_sid")
    _r_sids=$(uci -q get "$CONF.main.oc_disabled_sids")
    _r_old=$(uci -q get "$CONF.main.oc_old_custom_dns")
    _r_wan=$(uci -q get "$CONF.main.oc_old_append_wan_dns")

    [ -n "$_r_sid" ] || [ -n "$_r_sids" ] || [ -n "$_r_old" ] || [ -n "$_r_wan" ] || return 0

    [ -n "$_r_sid" ] && uci -q delete "openclash.$_r_sid"
    for _r_s in $_r_sids; do
        uci -q set "openclash.$_r_s.enabled=1"
    done
    if [ -n "$_r_old" ]; then
        uci -q set "openclash.config.enable_custom_dns=$_r_old"
    fi
    if [ -n "$_r_wan" ]; then
        uci -q set "openclash.config.append_wan_dns=$_r_wan"
    fi

    uci -q delete "$CONF.main.oc_agh_sid"
    uci -q delete "$CONF.main.oc_disabled_sids"
    uci -q delete "$CONF.main.oc_old_custom_dns"
    uci -q delete "$CONF.main.oc_old_append_wan_dns"

    uci -q commit openclash 2>/dev/null
    uci -q commit "$CONF" 2>/dev/null
    return 0
}

# 让 OpenClash 重新生成 DNS 配置使自定义上游生效；仅在 Clash 已运行时重启。
clashfirst_openclash_refresh() {
    # OpenClash 的“快速启动”会在配置未变时跳过 yml_change.sh，
    # 导致自定义上游不生效；无论 Clash 是否在运行，都要先让缓存失效。
    rm -f /tmp/openclash.change /tmp/openclash_tpl_cache

    pidof clash >/dev/null 2>&1 || return 0
    [ -x /etc/init.d/openclash ] || return 0

    log_msg "正在重启 OpenClash 以应用自定义上游 DNS..."
    /etc/init.d/openclash restart >/dev/null 2>&1
    return 0
}
