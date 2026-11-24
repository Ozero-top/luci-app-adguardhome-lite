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
CONTROLLER = (SRC / "luasrc" / "controller" / "adguardhome_lite.lua").read_text(encoding="utf-8")
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
        self.assertIn("latest_tag(", CONTROLLER)
        self.assertIn('latest = beta_tag ~= "" and beta_tag or stable', CONTROLLER)
        # Atom 正文里有被转义的 changelog 链接，标签只能取合法字符
        self.assertIn("releases/tag/[A-Za-z0-9._-]*", CHECK)
        # 旧版本通道取上一条正式版本线，安装脚本按标签直连且不回退最新正式版
        self.assertIn("legacy_tag(", CONTROLLER)
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
