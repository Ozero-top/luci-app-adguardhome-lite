#!/bin/sh
# AdGuard Home 助手 - 应用 LuCI 设置
# 功能：停止服务、更新端口、重新应用 DNS 接管模式并启动服务。

. /usr/share/adguardhome-lite/common.sh

load_conf

# 「OpenClash 串联」已下线：dnsmasq 会优先采用 OpenClash 写入的默认上游，
# 过滤实际不生效，这里自动迁移到「接管 53 端口」。
if [ "$dns_mode" = "openclash" ]; then
    log_msg "「OpenClash 串联」模式已下线，已切换为「接管 53 端口」。"
    openclash_forward_del
    uci -q set "$CONF.main.dns_mode=takeover"
    uci -q commit "$CONF" 2>/dev/null
    dns_mode="takeover"
    dnsport="53"
fi

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
        clashfirst) _target_up="$(detect_real_upstream_dns)" ;;
        upstream) _target_up="$(detect_upstream_dns)" ;;
        *) _target_up="127.0.0.1" ;;
    esac

    # 兼容旧版本：auto_upstream 缺失时，current 为插件曾写入的默认值也视为可改
    _is_auto=0
    [ -n "$_auto_up" ] && [ "$_cur_up" = "$_auto_up" ] && _is_auto=1
    case "$_cur_up" in
        "127.0.0.1"|"127.0.0.1:1745"|"127.0.0.1:$clash_dns_port"|"127.0.0.1:5335"|"223.5.5.5 119.29.29.29"|"$_self_ip")
            _is_auto=1
            ;;
    esac

    if [ "$_is_auto" = "1" ] && [ "$_cur_up" != "$_target_up" ]; then
        yaml_set_list "$configpath" "upstream_dns" "$_target_up"
        uci -q set "$CONF.main.auto_upstream=$_target_up"
        log_msg "已根据 DNS 接管方式调整上游 DNS：$_target_up"
    fi

    # 本地 PTR 解析：只有接管 53 模式才可以指向 DNSMasq（1745），
    # 其它模式下 DNSMasq 又转发回 AdGuard Home，会造成反向查询环。
    _ptr_up="127.0.0.1:53"
    [ "$dns_mode" = "takeover" ] && _ptr_up="127.0.0.1:1745"
    _cur_ptr=$(yaml_get_list "$configpath" "local_ptr_upstreams")
    case "$_cur_ptr" in
        ""|"127.0.0.1"|"127.0.0.1:53"|"127.0.0.1:1745")
            if [ "$dns_mode" = "takeover" ]; then
                yaml_set_scalar "$configpath" "use_private_ptr_resolvers" "true"
                yaml_set_list "$configpath" "local_ptr_upstreams" "$_ptr_up"
            else
                yaml_set_scalar "$configpath" "use_private_ptr_resolvers" "false"
                yaml_set_list "$configpath" "local_ptr_upstreams" ""
            fi
            ;;
    esac

    # 一键化：自动写入适合 Clash fake-IP 的 DNS 参数，
    # 省得用户再进 AdGuard Home 面板逐项关闭缓存、DNSSEC 等。
    # 注意不要自动开启安全浏览（safebrowsing）：它依赖 AdGuard 的在线服务，
    # 国内网络不可达时会拖慢甚至阻塞解析，需要时请用户在面板手动开启。
    yaml_set_scalar "$configpath" "cache_enabled" "false"
    yaml_set_scalar "$configpath" "cache_optimistic" "false"
    yaml_set_scalar "$configpath" "enable_dnssec" "false"
    yaml_set_scalar "$configpath" "upstream_mode" "parallel"
    log_msg "已自动应用推荐 DNS 参数：关闭缓存/DNSSEC，并行上游。"

    # 过滤列表下载走 Clash 的 HTTP 代理（检测不到就清空），
    # 否则国内直连 GitHub 会被重置，成人规则等列表无法更新。
    _proxy="$(detect_http_proxy)"
    yaml_set_root_scalar "$configpath" "http_proxy" "$_proxy"
    if [ -n "$_proxy" ]; then
        log_msg "过滤列表下载已走 Clash 代理：$_proxy"
    else
        log_msg "未检测到可用的 Clash HTTP 代理，过滤列表将直连下载。"
    fi

    # 成人内容拦截（可选）：追加或移除 HaGeZi NSFW 规则
    _had_adult="0"
    yaml_filter_present "$configpath" "$ADULT_FILTER_URL" && _had_adult="1"
    if [ "$adult_block" = "1" ]; then
        yaml_filter_add "$configpath" "$ADULT_FILTER_URL" "$ADULT_FILTER_NAME" "$ADULT_FILTER_ID"
        [ "$_had_adult" = "1" ] || log_msg "已启用成人内容拦截（追加 HaGeZi NSFW 规则）。"
    else
        yaml_filter_remove "$configpath" "$ADULT_FILTER_URL"
        [ "$_had_adult" = "0" ] || log_msg "已关闭成人内容拦截（移除 NSFW 规则）。"
    fi

    # 前置模式下来源全是 127.0.0.1，回环地址必须跳出限速，
    # 否则一个客户端超过 20 qps 就会被 AdGuard Home 拒绝。
    # 注意：ratelimit_whitelist 只接受单个 IP，写 CIDR 会导致配置校验失败。
    if [ "$dns_mode" = "clashfirst" ]; then
        _rl=$(awk '$0 ~ "^  ratelimit:" {print $2; exit}' "$configpath" 2>/dev/null)
        _wl=$(yaml_get_list "$configpath" "ratelimit_whitelist")
        if [ -n "$_rl" ] && [ "$_rl" != "0" ] && [ -z "$_wl" ]; then
            yaml_set_list "$configpath" "ratelimit_whitelist" "127.0.0.1 ::1"
            log_msg "已把回环地址加入限速白名单（前置模式查询来源都是 127.0.0.1）。"
        fi
    fi

    # 兼容 1.1.4/1.1.5 生成的配置：把白名单里的 CIDR 改回单个 IP
    _wl_cidr=$(awk '/^  ratelimit_whitelist:/{f=1;next} f&&/^    - /{print;next} f{f=0}' "$configpath" 2>/dev/null | grep -cE '127\.0\.0\.0/8|::1/128')
    if [ "${_wl_cidr:-0}" != "0" ]; then
        yaml_fix_ratelimit_whitelist "$configpath"
        log_msg "已修正限速白名单格式（CIDR 改为单个 IP）。"
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

    # 前置模式下 AdGuard Home 先启动，再让 OpenClash 重载上游，
    # 避免重启 OpenClash 时 5335 还没有监听导致 DNS 中断。
    if [ "$dns_mode" = "clashfirst" ]; then
        clashfirst_openclash_refresh
    fi
else
    /etc/init.d/adguardhome_lite disable >/dev/null 2>&1
    log_msg "服务已停止，并已取消开机自启。"
fi

log_msg "设置应用完成。"
exit 0
