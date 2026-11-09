#!/bin/sh
# AdGuard Home 一键版 - DNS 接管模式管理
# 用法：dns_mode.sh apply|revert|status
# 说明：自动保存和恢复 DNSMasq 原始设置，关闭服务或切换模式时不会破坏上网。

. /usr/share/adguardhome-lite/common.sh

load_conf

ACTION="${1:-apply}"

get_uci() {
    uci -q get "$1" 2>/dev/null
}

# 保存 DNSMasq 的原始设置，仅在尚未保存时执行一次
save_original() {
    [ "$(get_uci "$CONF.main.old_captured")" = "1" ] && return 0

    old_has_port="0"
    old_port="$(get_uci dhcp.@dnsmasq[0].port)"
    [ -n "$old_port" ] && old_has_port="1"

    old_has_noresolv="0"
    old_noresolv="$(get_uci dhcp.@dnsmasq[0].noresolv)"
    [ -n "$old_noresolv" ] && old_has_noresolv="1"

    old_has_resolvfile="0"
    old_resolvfile="$(get_uci dhcp.@dnsmasq[0].resolvfile)"
    [ -n "$old_resolvfile" ] && old_has_resolvfile="1"

    old_has_server="0"
    old_servers="$(get_uci dhcp.@dnsmasq[0].server)"
    [ -n "$old_servers" ] && old_has_server="1"

    uci -q set "$CONF.main.old_has_port=$old_has_port"
    uci -q delete "$CONF.main.old_port"
    [ "$old_has_port" = "1" ] && uci -q set "$CONF.main.old_port=$old_port"

    uci -q set "$CONF.main.old_has_noresolv=$old_has_noresolv"
    uci -q delete "$CONF.main.old_noresolv"
    [ "$old_has_noresolv" = "1" ] && uci -q set "$CONF.main.old_noresolv=$old_noresolv"

    uci -q set "$CONF.main.old_has_resolvfile=$old_has_resolvfile"
    uci -q delete "$CONF.main.old_resolvfile"
    [ "$old_has_resolvfile" = "1" ] && uci -q set "$CONF.main.old_resolvfile=$old_resolvfile"

    uci -q set "$CONF.main.old_has_server=$old_has_server"
    uci -q delete "$CONF.main.old_server"
    if [ "$old_has_server" = "1" ]; then
        for _s in $old_servers; do
            uci -q add_list "$CONF.main.old_server=$_s"
        done
    fi

    uci -q set "$CONF.main.old_captured=1"
    uci -q commit "$CONF" 2>/dev/null
}

# 恢复 DNSMasq 原始设置，并清除保存的备份值
restore_original() {
    [ "$(get_uci "$CONF.main.old_captured")" = "1" ] || return 0

    if [ "$(get_uci "$CONF.main.old_has_port")" = "1" ]; then
        uci -q set "dhcp.@dnsmasq[0].port=$(get_uci "$CONF.main.old_port")"
    else
        uci -q delete dhcp.@dnsmasq[0].port
    fi

    if [ "$(get_uci "$CONF.main.old_has_noresolv")" = "1" ]; then
        uci -q set "dhcp.@dnsmasq[0].noresolv=$(get_uci "$CONF.main.old_noresolv")"
    else
        uci -q delete dhcp.@dnsmasq[0].noresolv
    fi

    if [ "$(get_uci "$CONF.main.old_has_resolvfile")" = "1" ]; then
        uci -q set "dhcp.@dnsmasq[0].resolvfile=$(get_uci "$CONF.main.old_resolvfile")"
    else
        uci -q delete dhcp.@dnsmasq[0].resolvfile
    fi

    uci -q delete dhcp.@dnsmasq[0].server
    if [ "$(get_uci "$CONF.main.old_has_server")" = "1" ]; then
        for _s in $(get_uci "$CONF.main.old_server"); do
            uci -q add_list "dhcp.@dnsmasq[0].server=$_s"
        done
    fi

    uci -q commit dhcp 2>/dev/null

    uci -q delete "$CONF.main.old_captured"
    uci -q delete "$CONF.main.old_has_port"
    uci -q delete "$CONF.main.old_port"
    uci -q delete "$CONF.main.old_has_noresolv"
    uci -q delete "$CONF.main.old_noresolv"
    uci -q delete "$CONF.main.old_has_resolvfile"
    uci -q delete "$CONF.main.old_resolvfile"
    uci -q delete "$CONF.main.old_has_server"
    uci -q delete "$CONF.main.old_server"
    uci -q commit "$CONF" 2>/dev/null
}

# 仅清除保存的备份值，不改动 DNSMasq 当前设置
clear_original() {
    uci -q delete "$CONF.main.old_captured"
    uci -q delete "$CONF.main.old_has_port"
    uci -q delete "$CONF.main.old_port"
    uci -q delete "$CONF.main.old_has_noresolv"
    uci -q delete "$CONF.main.old_noresolv"
    uci -q delete "$CONF.main.old_has_resolvfile"
    uci -q delete "$CONF.main.old_resolvfile"
    uci -q delete "$CONF.main.old_has_server"
    uci -q delete "$CONF.main.old_server"
    uci -q commit "$CONF" 2>/dev/null
}

# 修改 AdGuard Home 配置文件中的 DNS 端口，并确认写入成功
patch_agh_port() {
    [ -s "$configpath" ] || return 0

    yaml_set_scalar "$configpath" "port" "$dnsport" || return 1
    grep -q "^  port: $dnsport$" "$configpath" || return 1
    return 0
}

# 判断当前 DNSMasq 是否已经是目标模式
mode_is_applied() {
    [ "$mode_applied" = "$dns_mode" ] || return 1

    case "$dns_mode" in
        upstream)
            [ "$(get_uci dhcp.@dnsmasq[0].noresolv)" = "1" ] || return 1
            echo "$(get_uci dhcp.@dnsmasq[0].server)" | grep -q '127.0.0.1#5333' || return 1
            ;;
        takeover)
            _port="$(get_uci dhcp.@dnsmasq[0].port)"
            [ -n "$_port" ] && [ "$_port" != "53" ] || return 1
            ;;
        openclash)
            openclash_forward_present || return 1
            grep -q "^  port: $dnsport$" "$configpath" || return 1
            # DNSMasq 永远保持 53，绝不跟随劫持端口（避免与 Clash 的 7874 抢端口）
            _dp="$(get_uci dhcp.@dnsmasq[0].port)"
            [ -n "$_dp" ] || _dp="53"
            [ "$_dp" = "53" ] || return 1
            ;;
        clashfirst)
            grep -q "^  port: $dnsport$" "$configpath" || return 1
            # 未安装 OpenClash 时无法自动写上游，只要端口正确就视为已应用
            if uci -q get openclash.config >/dev/null 2>&1; then
                [ -n "$(get_uci "$CONF.main.oc_agh_sid")" ] || return 1
            fi
            ;;
        none)
            ;;
    esac
    return 0
}

mode_name() {
    case "$dns_mode" in
        takeover) echo "接管 53 端口模式（DNSMasq 移至 1745）" ;;
        openclash) echo "OpenClash 串联模式（DNSMasq 53 → AdGuard Home 5333 → Clash 7874）" ;;
        clashfirst) echo "OpenClash 前置模式（Clash 7874 → AdGuard Home 5335 → 真实 DNS）" ;;
        none) echo "仅面板模式（不接管 DNS）" ;;
        *) echo "DNSMasq 上游模式（AdGuard Home 监听 5333）" ;;
    esac
}

apply_mode() {
    case "$dns_mode" in
        upstream|takeover|none|openclash|clashfirst) ;;
        *) dns_mode="upstream" ;;
    esac

    if ! uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
        log_msg "未找到 DNSMasq 配置，跳过 DNS 接管设置。"
        patch_agh_port
        uci -q set "$CONF.main.mode_applied=$dns_mode"
        uci -q commit "$CONF" 2>/dev/null
        return 0
    fi

    if mode_is_applied; then
        if ! patch_agh_port; then
            log_msg "无法写入 AdGuard Home DNS 端口，正在恢复 DNSMasq 设置..."
            revert_mode
            return 1
        fi
        log_msg "DNS 接管方式未变化：$(mode_name)，跳过 DNSMasq 修改。"
        return 0
    fi

    # 从「OpenClash 前置」切到其它模式时，必须先把 Clash 上游还原，
    # 否则 Clash 仍指向 AdGuard Home，而 AdGuard Home 又转给 Clash，形成查询环。
    if [ "$mode_applied" = "clashfirst" ] && [ "$dns_mode" != "clashfirst" ]; then
        clashfirst_openclash_restore
        clashfirst_openclash_refresh &
    fi

    # 先恢复原始状态，再基于原始状态应用新模式，保证来回切换不叠加。
    # OpenClash 串联模式不长期接管 DNSMasq 设置，因此不保存/恢复原始值。
    if [ "$dns_mode" = "openclash" ]; then
        [ "$mode_applied" = "openclash" ] || restore_original
    else
        restore_original
        save_original
    fi

    # 端口写入失败时立即取消接管，避免 DNSMasq 与 AdGuard Home 端口不一致导致断网
    if ! patch_agh_port; then
        log_msg "无法将 AdGuard Home DNS 端口写为 $dnsport，已取消本次 DNS 接管。"
        restore_original
        uci -q set "$CONF.main.mode_applied=none"
        uci -q commit "$CONF" 2>/dev/null
        return 1
    fi

    case "$dns_mode" in
        upstream)
            uci -q delete dhcp.@dnsmasq[0].server
            uci -q add_list 'dhcp.@dnsmasq[0].server=127.0.0.1#5333'
            uci -q set dhcp.@dnsmasq[0].noresolv=1
            uci -q delete dhcp.@dnsmasq[0].resolvfile
            ;;
        takeover)
            _port="$(get_uci dhcp.@dnsmasq[0].port)"
            if [ -z "$_port" ] || [ "$_port" = "53" ]; then
                uci -q set dhcp.@dnsmasq[0].port=1745
            fi
            ;;
        openclash)
            # 保留 OpenClash 的 53 劫持，但 DNSMasq 必须留在 53：
            # 这样即使 OpenClash 重启/更新导致劫持规则消失，客户端仍有 DNS。
            if ! openclash_forward_add; then
                log_msg "无法写入 DNSMasq 转发规则，已取消 OpenClash 串联模式。"
                restore_original
                uci -q set "$CONF.main.mode_applied=none"
                uci -q commit "$CONF" 2>/dev/null
                return 1
            fi
            ensure_safe_dnsmasq_layout
            ;;
        clashfirst)
            _oc_rc=0
            clashfirst_openclash_apply || _oc_rc=$?
            case "$_oc_rc" in
                0) log_msg "已将 OpenClash 自定义上游 DNS 设为 127.0.0.1:$dnsport" ;;
                2) log_msg "未检测到 OpenClash：请手动把 Clash 上游 DNS 设为 127.0.0.1:$dnsport" ;;
                3) log_msg "当前 OpenClash 不支持自定义上游：请手动把上游 DNS 设为 127.0.0.1:$dnsport" ;;
                *) log_msg "写入 OpenClash 上游失败：请手动把上游 DNS 设为 127.0.0.1:$dnsport" ;;
            esac

            # 前置模式不改 DNSMasq 转发，只确保它留在 53
            if [ "$(get_uci dhcp.@dnsmasq[0].port)" != "53" ]; then
                uci -q set dhcp.@dnsmasq[0].port=53
            fi
            ensure_clashfirst_chain
            ;;
        none)
            ;;
    esac

    uci -q commit dhcp 2>/dev/null
    uci -q set "$CONF.main.mode_applied=$dns_mode"
    uci -q commit "$CONF" 2>/dev/null

    restart_dnsmasq
    log_msg "已应用 $(mode_name)"
    return 0
}

# 保证 DNSMasq 始终监听 53。
# 说明：DNSMasq 一旦跟随 OpenClash 的劫持端口（例如 53 → 7874），
# 就会与 Clash 抢 7874 导致 DNSMasq 启动失败、全网断 DNS。
# 因此这里只允许 DNSMasq 留在 53，不再跟随任何劫持端口。
ensure_safe_dnsmasq_layout() {
    _hj="$(openclash_hijack_port)"
    _cur="$(get_uci dhcp.@dnsmasq[0].port)"
    _bp="0"

    if [ "$_cur" != "53" ]; then
        uci -q set dhcp.@dnsmasq[0].port=53
        uci -q commit dhcp 2>/dev/null
        restart_dnsmasq
        sleep 1
        log_msg "DNSMasq 已恢复监听 53。"
    fi

    if [ -z "$_hj" ]; then
        log_msg "未检测到 OpenClash DNS 劫持，DNSMasq 转发规则生效（53 → AdGuard Home）。"
    elif [ "$_hj" = "53" ] || [ "$_hj" = "$dnsport" ]; then
        log_msg "OpenClash 劫持目标为 $_hj，链路正常。"
    else
        _bp="1"
        log_msg "OpenClash 把 53 直接劫持到 $_hj，查询不再经过 DNSMasq，AdGuard Home 会被绕过。"
        if [ "$_hj" = "$clash_dns_port" ]; then
            log_msg "建议改用「OpenClash 前置」模式：让 Clash 把上游 DNS 交给 AdGuard Home。"
        fi
    fi

    uci -q set "$CONF.main.agh_bypassed=$_bp"
    uci -q commit "$CONF" 2>/dev/null
}

# OpenClash 前置模式：检查 OpenClash 的 DNS 劫持是否开启，
# 未开启时客户端查询不会经过 Clash，AdGuard Home 自然收不到查询。
ensure_clashfirst_chain() {
    _rd="$(get_uci openclash.config.enable_redirect_dns)"
    _bp="0"
    if [ -z "$_rd" ] || [ "$_rd" = "0" ]; then
        _bp="1"
        log_msg "OpenClash DNS 劫持未开启：请在 OpenClash 中开启 DNS 劫持，否则查询会绕过 AdGuard Home。"
    fi

    uci -q set "$CONF.main.agh_bypassed=$_bp"
    uci -q commit "$CONF" 2>/dev/null
}

# 恢复后检查上游是否可用：指向已停止的本地端口时自动回退，避免 DNSMasq 无法解析。
repair_dnsmasq_upstream() {
    [ "$(get_uci dhcp.@dnsmasq[0].noresolv)" = "1" ] || return 0

    _servers="$(get_uci dhcp.@dnsmasq[0].server)"
    [ -n "$_servers" ] || return 0

    _alive=0
    for _s in $_servers; do
        case "$_s" in
            127.0.0.1#*|::1#*|localhost#*)
                _p="${_s##*#}"
                port_listening "$_p" && _alive=1
                ;;
            *)
                _alive=1
                ;;
        esac
        [ "$_alive" = "1" ] && break
    done
    [ "$_alive" = "1" ] && return 0

    if port_listening "$clash_dns_port"; then
        log_msg "DNSMasq 上游不可用（$_servers），已切换为 Clash DNS。"
        uci -q delete dhcp.@dnsmasq[0].server
        uci -q add_list "dhcp.@dnsmasq[0].server=127.0.0.1#$clash_dns_port"
    else
        log_msg "DNSMasq 上游不可用（$_servers），已回退到 WAN DNS。"
        uci -q delete dhcp.@dnsmasq[0].server
        uci -q set dhcp.@dnsmasq[0].noresolv=0
        if [ -s /tmp/resolv.conf.d/resolv.conf.auto ]; then
            uci -q set dhcp.@dnsmasq[0].resolvfile=/tmp/resolv.conf.d/resolv.conf.auto
        else
            uci -q delete dhcp.@dnsmasq[0].resolvfile
        fi
    fi

    uci -q commit dhcp 2>/dev/null
    restart_dnsmasq
    sleep 1
}

revert_mode() {
    _had="$(get_uci "$CONF.main.old_captured")"
    _applied="$(get_uci "$CONF.main.mode_applied")"
    _oc="0"
    openclash_forward_present && _oc="1"
    _old_port="$(get_uci dhcp.@dnsmasq[0].port)"

    if [ "$_applied" = "clashfirst" ]; then
        clashfirst_openclash_restore
    fi

    if [ "$_applied" = "openclash" ]; then
        # 串联模式未接管 DNSMasq：只移除转发规则并清理可能遗留的备份记录。
        openclash_forward_del
        clear_original
    else
        restore_original
        openclash_forward_del
    fi

    uci -q set "$CONF.main.mode_applied=none"
    uci -q commit "$CONF" 2>/dev/null

    # 保证 53 端口始终有 DNS 服务：
    # - DNSMasq 必须留在 53（有劫持时也不再跟随劫持端口）；
    # - 如果 OpenClash 已停止，53 仍由 DNSMasq 提供服务，避免客户端无 DNS。
    ensure_safe_dnsmasq_layout

    # 关闭插件后不再有“被绕过”状态，避免面板残留提示
    uci -q set "$CONF.main.agh_bypassed=0"
    uci -q commit "$CONF" 2>/dev/null

    if [ "$_applied" = "clashfirst" ]; then
        # 恢复 OpenClash 上游后需要重载，否则 Clash 仍指向已停止的 5335
        clashfirst_openclash_refresh &
    fi

    _new_port="$(get_uci dhcp.@dnsmasq[0].port)"
    if [ "$_had" = "1" ] || [ "$_oc" = "1" ] || [ "$_old_port" != "$_new_port" ]; then
        restart_dnsmasq
        sleep 1
        # 恢复后如果上游指向已停止的本地端口，自动回退到 WAN DNS，避免断网
        repair_dnsmasq_upstream
        if ! nslookup www.baidu.com 127.0.0.1 >/dev/null 2>&1; then
            log_msg "提示：DNSMasq 解析仍失败，请检查 OpenClash 运行状态或 WAN DNS。"
        fi
        log_msg "已恢复 DNSMasq 原始设置"
    fi
}

show_status() {
    echo "dns_mode=$dns_mode"
    echo "mode_applied=$mode_applied"
    echo "agh_dns_port=$dnsport"
    echo "dnsmasq_port=$(get_uci dhcp.@dnsmasq[0].port)"
    echo "dnsmasq_noresolv=$(get_uci dhcp.@dnsmasq[0].noresolv)"
    echo "dnsmasq_server=$(get_uci dhcp.@dnsmasq[0].server)"
    echo "clash_dns_port=$clash_dns_port"
    echo "openclash_hijack_port=$(openclash_hijack_port)"
    echo "openclash_redirect=$(get_uci openclash.config.enable_redirect_dns)"
    echo "openclash_custom_dns=$(get_uci openclash.config.enable_custom_dns)"
    echo "agh_bypassed=$(get_uci "$CONF.main.agh_bypassed")"
    echo "openclash_forward=$(openclash_forward_present && echo yes || echo no)"
}

case "$ACTION" in
    apply) apply_mode ;;
    revert) revert_mode ;;
    status) show_status ;;
    *)
        echo "用法：$0 apply|revert|status"
        exit 1
        ;;
esac

exit 0
