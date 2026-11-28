#!/usr/bin/env python3
"""可靠性不变量：看护回退、更新锁、完整性校验、持久化状态、卸载恢复。"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"
INIT = (SRC / "root" / "etc" / "init.d" / "adguardhome_lite").read_text(encoding="utf-8")
WATCHDOG = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "watchdog.sh").read_text(encoding="utf-8")
UPDATE = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "update_core.sh").read_text(encoding="utf-8")
COMMON = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "common.sh").read_text(encoding="utf-8")
APPLY = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "apply_settings.sh").read_text(encoding="utf-8")
DNS_MODE = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "dns_mode.sh").read_text(encoding="utf-8")
KEEP = (SRC / "root" / "lib" / "upgrade" / "keep.d" / "luci-app-adguardhome-lite").read_text(encoding="utf-8")
RULES = (SRC / "luasrc" / "model" / "adguardhome_lite" / "actions" / "rules.lua").read_text(encoding="utf-8")
CHECK = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "check_core_update.sh").read_text(encoding="utf-8")
VERSIONS = (SRC / "luasrc" / "model" / "adguardhome_lite" / "versions.lua").read_text(encoding="utf-8")
SETTINGS = (SRC / "luasrc" / "model" / "adguardhome_lite" / "actions" / "settings.lua").read_text(encoding="utf-8")
DASHBOARD = (SRC / "luasrc" / "model" / "adguardhome_lite" / "actions" / "dashboard.lua").read_text(encoding="utf-8")
CORE = (SRC / "luasrc" / "model" / "adguardhome_lite" / "actions" / "core.lua").read_text(encoding="utf-8")


class ReliabilityTest(unittest.TestCase):
    def test_watchdog_is_procd_managed(self):
        # 看护必须由 procd 作为独立实例运行：后台子进程会继承 rc.common 的锁 fd
        self.assertIn("procd_open_instance \"watchdog\"", INIT)
        self.assertIn("watchdog.sh", INIT)
        self.assertNotIn("sleep 12", INIT, "应使用持续看护而不是一次性 12 秒检查")
        self.assertNotIn(") 1000>&-", INIT, "看护不应以 shell 后台子进程方式运行")

    def test_watchdog_reverts_without_recursion(self):
        self.assertIn("state_write last_fallback", WATCHDOG)
        self.assertIn("dns_mode.sh revert", WATCHDOG)
        self.assertIn("ubus call service delete", WATCHDOG)
        self.assertNotIn("/etc/init.d/adguardhome_lite stop", WATCHDOG)
        self.assertIn("-lt 30", WATCHDOG)

    def test_update_lock_uses_flock_with_safe_fallback(self):
        self.assertIn("flock -n", UPDATE)
        self.assertIn(".stale.", UPDATE, "目录锁回收必须先改名再删除")
        self.assertIn("mv \"$LOCK\" \"$stale\"", UPDATE, "回收前应先改名，避免删掉并发进程刚建的锁")

    def test_download_integrity_checks(self):
        self.assertIn("sha256", UPDATE)
        self.assertIn("AdGuardHome/AdGuardHome", UPDATE)
        self.assertIn("target_ver", UPDATE)
        # 官方 tar 包路径带 ./ 前缀，结构检查必须归一化后再匹配
        self.assertIn("sed 's#^\\./##'", UPDATE)

    def test_state_helpers_are_atomic(self):
        self.assertIn("state_write()", COMMON)
        self.assertIn("state_read()", COMMON)
        self.assertIn("mv -f", COMMON)

    def test_apply_refuses_broken_config(self):
        self.assertIn("config_restore", APPLY)
        self.assertIn("state_write last_apply", APPLY)

    def test_state_survives_upgrade(self):
        self.assertIn("/etc/adguardhome_lite", KEEP.splitlines())

    def test_revert_keeps_clash_hijack_port(self):
        # Clash 仍劫持 53 → 某端口时，若该端口空闲则由 DNSMasq 接管，避免恢复后断 DNS
        self.assertIn("port_held_by_other", DNS_MODE)
        self.assertIn("_hj2", DNS_MODE)
        self.assertIn("openclash_hijack_port", DNS_MODE)
        self.assertIn('"$_cur" = "$_hj"', DNS_MODE)
        # 恢复后的自检必须查询 DNSMasq 实际端口，而不是写死 53
        self.assertIn('-port="$_chk_port"', DNS_MODE)

    def test_local_dns_probe_detects_nat_output_hijack(self):
        # PassWall/Clash 的 nat_output 会把本机发往 127.0.0.1:53 的查询改道，
        # 此时 nslookup 探测的不是本机 DNS 服务，直接判定失败会误报断网。
        self.assertIn("local_dns_hijack_port()", COMMON)
        self.assertIn('oif \\"lo\\"', COMMON)
        self.assertIn("local_dns_hijack_port", DNS_MODE)
        self.assertIn("dns_local_probe_hijacked", DNS_MODE)
        # 劫持目标有服务时不应告警，只有目标无人监听才算真故障
        self.assertIn('port_listening "$_lo_hj"', DNS_MODE)
        # selftest 同样要识别劫持，否则面板自检恒为红
        selftest = (SRC / "luasrc" / "model" / "adguardhome_lite" / "selftest.lua").read_text(encoding="utf-8")
        self.assertIn("redirect to :", selftest)
        self.assertIn("PassWall/Clash 劫持", selftest)

    def test_selftest_distinguishes_warn_from_fail(self):
        # 自检要区分「提示」与「异常」：劫持目标端口有服务属预期行为，不应拉红整体结论；
        # 端口无人监听才是真故障。level 字段是三态，ok 只表示非 fail。
        selftest = (SRC / "luasrc" / "model" / "adguardhome_lite" / "selftest.lua").read_text(encoding="utf-8")
        self.assertIn('level = level', selftest)
        self.assertIn('hport_ok and "warn" or "fail"', selftest)
        self.assertIn('check.level == "fail"', selftest)
        # 前端必须按 level 渲染，否则 warn 会显示成「异常」
        panel = (SRC / "panel" / "06-stats-selftest.js").read_text(encoding="utf-8")
        self.assertIn("c.level || (c.ok ? 'ok' : 'fail')", panel)
        self.assertIn("'提示'", panel)

    def test_mode_switch_syncs_upstream(self):
        # init.d 的 restart 只跑 dns_mode.sh，不跑 apply_settings.sh；
        # 若不在此同步上游，从「PassWall 前置」切回「接管 53」后上游仍指向
        # PassWall 已失效的端口，全网查询 SERVFAIL（实测）。
        self.assertIn("sync_agh_upstream()", DNS_MODE)
        self.assertIn("\n    sync_agh_upstream\n", DNS_MODE)
        self.assertIn('takeover) _up="127.0.0.1:1745"', DNS_MODE)
        # 只改插件自己写入的上游，用户自定义的保持不动
        self.assertIn('upstream_source" = "custom" ] && return 0', DNS_MODE)
        self.assertIn('"$_is_auto" = "1" ] || return 0', DNS_MODE)
        # PassWall 被手动关闭后其 DNS 端口消失，看护必须跟随回退到 1745，
        # 不能因为 passwall_enabled=0 就直接返回。
        self.assertNotIn("passwall_enabled || return 0", WATCHDOG)
        self.assertIn("passwall_upstream_dns", WATCHDOG)
        # /etc/init.d/passwall stop 不会改 UCI 的 enabled，只看标志会继续指向
        # 已无人监听的 PassWall DNS 端口，必须按端口实际监听状态判断。
        self.assertIn('port_listening "$_pw_port"', COMMON)

    def test_upstream_follow_waits_for_stable_port(self):
        # PassWall 重启期间其 DNS 端口会短暂消失，若立刻回退再跟回，
        # 每轮都要结束 AdGuard Home，实测形成 procd crash loop 并误触发整体回退。
        self.assertIn("PSW_STABLE_SECONDS", WATCHDOG)
        self.assertIn("PSW_PENDING", WATCHDOG)
        self.assertIn("_now - PSW_PENDING_SINCE", WATCHDOG)
        # 进程未就绪时不得再次 kill，否则会加剧 crash loop
        self.assertIn("is_agh_running || return 0", WATCHDOG)

    def test_disabled_start_reverts_dangling_takeover(self):
        # 断电/升级中断/直接改 UCI 关闭后，DNSMasq 可能仍停在 1745 而 AGH 不再启动，
        # 53 无人监听会断网。禁用分支必须先检测 mode_applied 并恢复。
        disabled = INIT.split('当前设置为未启用')[1].split("fi")[0]
        self.assertIn("mode_applied", disabled)
        self.assertIn("dns_mode.sh revert", disabled)

    def test_old_config_gets_defaults(self):
        # 1.3.11 时期配置缺少的新字段必须全部有兜底，否则脚本读到空值会写坏 YAML
        for key, default in [
            ("webaddr", "0.0.0.0"),
            ("dns_mode", "takeover"),
            ("channel", "stable"),
            ("upstream_source", "auto"),
            ("dns_crypto", "off"),
            ("mode_applied", "none"),
        ]:
            self.assertIn('config_get %s "main" %s "%s"' % (key, key, default), COMMON)
        # 缓存四件套允许为空（表示沿用 YAML 现值），不能被兜底成非法数字
        for key in ("cache_enabled", "cache_size_mb", "cache_ttl_min", "cache_ttl_max", "cache_optimistic"):
            self.assertIn('config_get %s "main" %s ""' % (key, key), COMMON)
        # 老配置里的 dns_mode 取值不能落到 dnsport 分支之外
        self.assertIn('*) dnsport="5333"', COMMON)

    def test_dns_mode_actions_are_serialized(self):
        # apply 与 revert 同时改写 DNSMasq 端口 / DHCP option 6 / nft 规则 / mode_applied，
        # 并发时后完成的一方用旧快照覆盖，实测会留下「mode_applied=takeover 但 53 无监听」。
        self.assertIn("lock_action()", COMMON)
        self.assertIn("flock -n 8", COMMON)
        self.assertIn("AGH_LOCK_HELD", COMMON)
        # 子脚本继承环境变量后不再重复加锁，避免 apply -> init stop -> revert 自锁
        self.assertIn('"$AGH_LOCK_HELD" = "1"', COMMON)
        self.assertIn("dns_mode_busy", COMMON)
        # dns_mode.sh 的 apply/revert 必须取锁并透传返回码，否则 init.d 的失败判断永远为真
        self.assertIn('apply|revert)', DNS_MODE)
        self.assertIn("lock_action || exit 1", DNS_MODE)
        self.assertIn('exit "$_act_rc"', DNS_MODE)
        # 整段应用过程持锁，覆盖 stop/start 触发的嵌套 dns_mode.sh 调用
        self.assertIn("lock_action || exit 1", APPLY)

    def test_stop_skips_revert_while_reapplying(self):
        # 保存设置时 stop 之后立刻重新接管，此时 revert 会把 DNSMasq 抢回 53，
        # 与尚未退出的 AGH 抢端口，实测 dnsmasq 连崩 6 次。
        self.assertIn("AGH_APPLYING", INIT)
        stopped = INIT.split("service_stopped()")[1].split("fi")[0]
        self.assertIn("AGH_APPLYING", stopped)
        self.assertIn("跳过 DNSMasq 恢复", stopped)
        self.assertIn("AGH_APPLYING=1", APPLY)
        self.assertIn("unset AGH_APPLYING", APPLY)
        # 禁用分支跳过了 stop 的自动恢复，必须显式 revert，否则 53 无人监听
        tail = APPLY.split("服务已停止，并已取消开机自启")[0]
        self.assertIn("dns_mode.sh revert", tail.split("/etc/init.d/adguardhome_lite disable")[-1])

    def test_rule_trim_handles_empty_filters_and_proxy_fallback(self):
        # AGH 没有任何黑名单订阅时返回 "filters": null，不能当成读取失败
        self.assertIn('type(st) ~= "table"', RULES)
        self.assertNotIn("type(st.filters) ~= \"table\"", RULES)
        # 直连拿不到预置列表时按配置的反代重试
        self.assertIn("add_preset", RULES)
        self.assertIn("github_proxy", RULES)
        self.assertIn("preset_path", RULES)

    def test_core_channels_are_selected_independently(self):
        # 正式版与预发布版各自保留标签列表，避免 1.0.0 把 1.0.0-b.2 盖掉
        self.assertIn("stable_tags=", CHECK)
        self.assertIn("beta_tags=", CHECK)
        self.assertIn("latest_tag(", VERSIONS)
        self.assertIn('latest = beta_tag ~= "" and beta_tag or stable', VERSIONS)
        # Atom 正文里有被转义的 changelog 链接，标签只能取合法字符
        self.assertIn("releases/tag/[A-Za-z0-9._-]*", CHECK)
        # 旧版本通道取上一条正式版本线，安装脚本按标签直连且不回退最新正式版
        self.assertIn("legacy_tag(", VERSIONS)
        self.assertIn("stable|beta|legacy", UPDATE)
        self.assertIn("legacy_github", UPDATE)
        self.assertIn('url_list="$stable_list"', UPDATE)
        self.assertIn("legacy = true", SETTINGS)
        # 旧版本内核读不了新 schema 配置时，改用兼容备份；没有备份则安全取消
        self.assertIn("cfg_from_backup", UPDATE)
        self.assertIn("旧版本内核无法解析当前配置", UPDATE)
        # 备份必须先于 --check-config：新版校验会原地迁移 schema，晚了就备份不到旧配置
        self.assertLess(UPDATE.index("更新前已备份配置"), UPDATE.index('"$newbin" --check-config'))
        # 概览提前提示配置风险；没有旧版本目标时拒绝启动安装
        self.assertIn("legacy_config_risk", DASHBOARD)
        self.assertIn("旧版本通道暂无可用目标版本", CORE)


if __name__ == "__main__":
    unittest.main()
