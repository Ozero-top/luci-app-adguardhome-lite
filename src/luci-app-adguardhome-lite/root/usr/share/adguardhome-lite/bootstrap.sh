#!/bin/sh
# AdGuard Home 一键版 - 首次配置生成脚本
# 功能：从内置默认配置模板生成 /etc/AdGuardHome.yaml，并同步面板端口、DNS 端口和上游 DNS。
# 说明：仅在配置文件不存在时由 init 脚本自动调用，一般无需手动执行。

. /usr/share/adguardhome-lite/common.sh

TEMPLATE="/usr/share/adguardhome-lite/AdGuardHome.yaml.template"
DEFAULT_ADMIN="admin"
DEFAULT_PASS="admin123"

fail_bootstrap() {
    log_msg "错误：$*"
    # 首次配置失败时不要留下半成品配置，否则下次启动会跳过自动生成
    rm -f "$configpath" "$configpath.pre_tun"
    exit 1
}

load_conf

[ -x "$binpath" ] || fail_bootstrap "尚未安装内核，请先在概览页安装内核。"
[ -s "$configpath" ] && exit 0
[ -f "$TEMPLATE" ] || fail_bootstrap "缺少默认配置模板：$TEMPLATE"

case "$webport" in
    ''|*[!0-9]*) webport="13800" ;;
esac
if [ "$webport" -lt 1 ] || [ "$webport" -gt 65535 ] 2>/dev/null; then
    webport="13800"
fi

mkdir -p "$workdir" "$(dirname "$configpath")" 2>/dev/null

log_msg "正在从内置模板生成首次配置..."
cp -f "$TEMPLATE" "$configpath" || fail_bootstrap "复制默认配置模板失败。"
chmod 600 "$configpath" 2>/dev/null

# 同步面板端口和 DNS 端口
yaml_set_scalar "$configpath" "address" "0.0.0.0:$webport"
yaml_set_scalar "$configpath" "port" "$dnsport"

# 上游 DNS 适配：避免 AdGuard Home 与自身 53 端口形成回环
case "$dns_mode" in
    takeover)
        # DNSMasq 已被移到 1745，指向 DNSMasq 继续解析，避免指向自身 53
        upstream="127.0.0.1:1745"
        upstream_note="DNSMasq（1745）"
        ;;
    openclash)
        # OpenClash 串联：DNSMasq 把查询转发给 AdGuard Home，再交给 Clash 的 DNS
        upstream="127.0.0.1:$clash_dns_port"
        upstream_note="Clash DNS（$clash_dns_port）"
        ;;
    upstream)
        # DNSMasq 在 53 且转发给 AdGuard Home，本机 53 会形成回环，
        # 改用实际的 Clash DNS 或 WAN 下发的 DNS，避免写死公共 DNS。
        upstream="$(detect_upstream_dns)"
        upstream_note="系统上游 DNS（$upstream）"
        ;;
    *)
        # 仅面板模式：DNSMasq 保持 53，可直接作为本地上游
        upstream="127.0.0.1"
        upstream_note="系统 DNSMasq（53）"
        ;;
esac
yaml_set_list "$configpath" "upstream_dns" "$upstream"

# 记录自动写入的上游，后续切换模式时只改动插件自己写入的值
uci -q set "$CONF.main.auto_upstream=$upstream"

if ! check_agh_config; then
    _err=$(tail -n 5 /var/run/adguardhome_lite_check.log 2>/dev/null | tr '\n' ' ')
    fail_bootstrap "默认配置校验失败：${_err}"
fi

uci -q set "$CONF.main.adminuser=$DEFAULT_ADMIN"
uci -q set "$CONF.main.adminpass=$DEFAULT_PASS"
uci -q commit "$CONF" 2>/dev/null

log_msg "首次配置生成完成：面板端口 $webport，DNS 端口 $dnsport，上游 DNS $upstream_note。"
log_msg "默认管理员：$DEFAULT_ADMIN，默认密码：$DEFAULT_PASS（建议首次登录后修改）。"
exit 0
