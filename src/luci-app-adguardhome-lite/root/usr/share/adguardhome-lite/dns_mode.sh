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
            _hp="$(openclash_hijack_port)"
            if [ -n "$_hp" ]; then
                [ "$(get_uci dhcp.@dnsmasq[0].port)" = "$_hp" ] || return 1
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
        openclash) echo "OpenClash 串联模式（保留 DNS 劫持，DNSMasq 转发给 AdGuard Home）" ;;
        none) echo "仅面板模式（不接管 DNS）" ;;
        *) echo "DNSMasq 上游模式（AdGuard Home 监听 5333）" ;;
    esac
}

apply_mode() {
    case "$dns_mode" in
        upstream|takeover|none|openclash) ;;
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
            uci -q set dhcp.@dnsmasq[0].noresolv='1'
            uci -q delete dhcp.@dnsmasq[0].resolvfile
            ;;
        takeover)
            _port="$(get_uci dhcp.@dnsmasq[0].port)"
            if [ -z "$_port" ] || [ "$_port" = "53" ]; then
                uci -q set dhcp.@dnsmasq[0].port='1745'
            fi
            ;;
        openclash)
            # 保留 OpenClash 的 53 劫持：DNSMasq 端口与劫持目标保持一致，
            # 再用 /#/ 规则把默认查询转发给 AdGuard Home（监听 5333）。
            _hijack_port="$(openclash_hijack_port)"
            if [ -n "$_hijack_port" ]; then
                uci -q set "dhcp.@dnsmasq[0].port=$_hijack_port"
            fi
            if ! openclash_forward_add; then
                log_msg "无法写入 DNSMasq 转发规则，已取消 OpenClash 串联模式。"
                restore_original
                uci -q set "$CONF.main.mode_applied=none"
                uci -q commit "$CONF" 2>/dev/null
                return 1
            fi
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

revert_mode() {
    _had="$(get_uci "$CONF.main.old_captured")"
    _applied="$(get_uci "$CONF.main.mode_applied")"
    _oc="0"
    openclash_forward_present && _oc="1"

    if [ "$_applied" = "openclash" ]; then
        # 串联模式未接管 DNSMasq：保留当前端口（与 OpenClash 劫持目标一致），
        # 只移除转发规则并清理可能遗留的备份记录。
        openclash_forward_del
        clear_original
    else
        restore_original
        openclash_forward_del
    fi

    uci -q set "$CONF.main.mode_applied=none"
    uci -q commit "$CONF" 2>/dev/null

    if [ "$_had" = "1" ] || [ "$_oc" = "1" ]; then
        restart_dnsmasq
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
