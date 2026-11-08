#!/bin/sh
# AdGuard Home 一键版 - 应用 LuCI 设置
# 功能：停止服务、更新端口、重新应用 DNS 接管模式并启动服务。

. /usr/share/adguardhome-lite/common.sh

load_conf

case "$webport" in
    ''|*[!0-9]*) webport="13800" ;;
esac
if [ "$webport" -lt 1 ] || [ "$webport" -gt 65535 ] 2>/dev/null; then
    webport="13800"
fi

mkdir -p /var/run 2>/dev/null
log_msg "开始应用 AdGuard Home 设置..."

# 停止服务时会触发 service_stopped，自动恢复 DNSMasq 原始设置
if [ -x /etc/init.d/adguardhome_lite ]; then
    /etc/init.d/adguardhome_lite stop >/dev/null 2>&1
fi

# 防御性处理：procd 未成功结束进程时强制清理，确保端口修改能生效
i="0"
while [ "$i" -lt 8 ]; do
    is_agh_running || break
    sleep 1
    i=$(( i + 1 ))
done
force_stop_agh

# 已生成配置文件时，同步面板端口和 DNS 端口
if [ -s "$configpath" ]; then
    cp -f "$configpath" "$configpath.bak" 2>/dev/null
    yaml_set_scalar "$configpath" "address" "0.0.0.0:$webport"
    yaml_set_scalar "$configpath" "port" "$dnsport"

    # 只调整插件自己写入的上游；用户自定义的上游保持不变，
    # 也不再写死公共 DNS（DNSMasq 上游模式按实际环境选择 Clash / WAN DNS）。
    _cur_up=$(yaml_get_list "$configpath" "upstream_dns")
    _auto_up=$(uci -q get "$CONF.main.auto_upstream" 2>/dev/null)
    _self_ip=$(uci -q get network.lan.ipaddr 2>/dev/null)
    case "$dns_mode" in
        takeover) _target_up="127.0.0.1:1745" ;;
        openclash) _target_up="127.0.0.1:$clash_dns_port" ;;
        upstream) _target_up="$(detect_upstream_dns)" ;;
        *) _target_up="127.0.0.1" ;;
    esac

    # 兼容旧版本：auto_upstream 缺失时，current 为插件曾写入的默认值也视为可改
    _is_auto=0
    [ -n "$_auto_up" ] && [ "$_cur_up" = "$_auto_up" ] && _is_auto=1
    case "$_cur_up" in
        "127.0.0.1"|"127.0.0.1:1745"|"127.0.0.1:$clash_dns_port"|"223.5.5.5 119.29.29.29"|"$_self_ip")
            _is_auto=1
            ;;
    esac

    if [ "$_is_auto" = "1" ] && [ "$_cur_up" != "$_target_up" ]; then
        yaml_set_list "$configpath" "upstream_dns" "$_target_up"
        uci -q set "$CONF.main.auto_upstream=$_target_up"
        log_msg "已根据 DNS 接管方式调整上游 DNS：$_target_up"
    fi

    if ! check_agh_config; then
        _err=$(tail -n 3 /var/run/adguardhome_lite_check.log 2>/dev/null | tr '\n' ' ')
        log_msg "配置校验失败，已恢复备份。${_err}"
        cp -f "$configpath.bak" "$configpath" 2>/dev/null
    fi
fi

if [ "$enabled" = "1" ]; then
    /etc/init.d/adguardhome_lite enable >/dev/null 2>&1
    log_msg "正在启动 AdGuard Home..."
    /etc/init.d/adguardhome_lite start >/dev/null 2>&1
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        log_msg "启动命令返回错误码 $_rc，请到“运行日志”查看原因。"
    fi
else
    /etc/init.d/adguardhome_lite disable >/dev/null 2>&1
    log_msg "服务已停止，并已取消开机自启。"
fi

log_msg "设置应用完成。"
exit 0
