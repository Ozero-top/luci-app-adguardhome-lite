#!/bin/sh
# AdGuard Home 助手 - DNS 接管看护
# 由 procd 作为独立实例运行；AGH 连续 30 秒无法运行时回退 DNS 接管，避免全网无 DNS。
# 不调用 init.d 的停止动作，避免从看护进程递归获取 rc.common 的 procd 锁。

. /usr/share/adguardhome-lite/common.sh

DEAD=0

while true; do
    sleep 5
    load_conf

    # 用户主动停止或已回退时不动作，但保持进程存活，避免 procd 反复拉起
    if [ "$enabled" != "1" ] || [ "$mode_applied" = "none" ]; then
        DEAD=0
        continue
    fi

    if is_agh_running; then
        DEAD=0
        continue
    fi

    DEAD=$(( DEAD + 5 ))
    [ "$DEAD" -lt 30 ] && continue

    log_event error agh_not_running "AdGuard Home 连续 30 秒未运行，正在回退 DNS 接管并恢复 DNSMasq..."
    state_write last_fallback "agh_not_running_30s"

    if ! /usr/share/adguardhome-lite/dns_mode.sh revert; then
        log_event error dns_revert_failed "DNS 接管回退失败，稍后重试。"
        DEAD=0
        continue
    fi

    restart_dnsmasq
    state_write last_fallback "reverted:agh_not_running_30s:$(date '+%Y-%m-%dT%H:%M:%S')"

    # 等价于 init.d stop，但由 ubus 直接删除服务，procd 会同时结束本看护实例
    ubus call service delete '{"name":"adguardhome_lite"}' >/dev/null 2>&1
    exit 0
done
