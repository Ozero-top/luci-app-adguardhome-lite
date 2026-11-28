#!/usr/bin/env python3
"""脚本静态检查：shebang、换行符、shell 语法；有 luac 时检查 Lua 语法。"""

import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"


def shell_scripts():
    paths = [
        ROOT / "install.sh",
        SRC / "root" / "etc" / "init.d" / "adguardhome_lite",
        SRC / "root" / "etc" / "uci-defaults" / "50_luci-adguardhome-lite",
    ]
    paths.extend((SRC / "root" / "usr" / "share" / "adguardhome-lite").glob("*.sh"))
    return paths


class ScriptTest(unittest.TestCase):
    def test_shebang_and_lf(self):
        for path in shell_scripts():
            data = path.read_bytes()
            self.assertNotIn(b"\r\n", data, "%s 含 CRLF" % path.name)
            first = data.split(b"\n", 1)[0].decode("utf-8", "replace")
            self.assertTrue(first.startswith("#!/bin/sh"), "%s 缺少 #!/bin/sh" % path.name)

    def test_shell_syntax(self):
        sh = shutil.which("sh")
        if not sh:
            self.skipTest("当前环境没有 sh，跳过 shell 语法检查")
        for path in shell_scripts():
            result = subprocess.run(
                [sh, "-n", path.as_posix()],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, "%s 语法错误：%s" % (path.name, result.stderr))

    def test_lua_syntax(self):
        luac = shutil.which("luac5.1") or shutil.which("luac")
        if not luac:
            self.skipTest("当前环境没有 luac，跳过 Lua 语法检查")
        for path in (SRC / "luasrc").rglob("*.lua"):
            result = subprocess.run([luac, "-p", path.as_posix()], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, "%s 语法错误：%s" % (path.name, result.stderr))


class LegacyCleanupTest(unittest.TestCase):
    """旧 conffile 残留：opkg 升级遗留的 <包名>-opkg 必须能扫描到并安全清理。"""

    def setUp(self):
        self.sh = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "legacy_cleanup.sh").read_text(encoding="utf-8")

    def test_scan_reports_conffile_residue(self):
        self.assertIn("OLD_CONF_RESIDUE", self.sh)
        self.assertIn("/etc/config/adguardhome_lite-opkg", self.sh)
        self.assertIn('add_item "conffile"', self.sh)

    def test_clean_backups_before_removing(self):
        self.assertIn('cp -a "$c" "$bk$c"', self.sh)
        self.assertIn('rm -f "$c"', self.sh)

    def test_install_sh_cleans_conffile_residue(self):
        # 脚本安装路径同样要覆盖 opkg 遗留的 -opkg 配置，否则两套入口行为不一致
        sh = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn('OLD_CONF_RESIDUE="/etc/config/adguardhome_lite-opkg', sh)
        self.assertIn("for c in $OLD_CONF_RESIDUE", sh)

    def test_clean_never_touches_current_config(self):
        # 清理只针对 *-opkg，当前配置路径不能出现在任何删除语句里
        for line in self.sh.splitlines():
            if "rm " in line:
                self.assertNotIn("/etc/config/adguardhome_lite ", line)
                self.assertNotIn('rm -f /etc/config/adguardhome_lite"', line)


class DnsModeStatusTest(unittest.TestCase):
    """dns_mode.sh 的 JSON 状态输出与 Clash 相关函数命名。"""

    def setUp(self):
        self.sh = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "dns_mode.sh").read_text(encoding="utf-8")
        self.common = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "common.sh").read_text(encoding="utf-8")

    def test_status_json_action_exists(self):
        self.assertIn("show_status_json()", self.sh)
        self.assertIn("status-json) show_status_json ;;", self.sh)
        # JSON 必须是单行可解析对象
        self.assertIn('printf \'{"ok":true\'', self.sh)

    def test_status_json_fields_match_text_output(self):
        for key in ("dns_mode", "mode_applied", "agh_dns_port", "dnsmasq_port",
                    "passwall_enabled", "passwall_dns_port"):
            self.assertIn('"%s"' % key, self.sh, "JSON 缺少字段：%s" % key)
            self.assertIn("%s=" % key, self.sh, "文本输出缺少字段：%s" % key)

    def test_clash_helpers_renamed(self):
        self.assertNotIn("clashfirst_openclash_", self.sh)
        self.assertNotIn("clashfirst_openclash_", self.common)
        for name in ("clashfirst_clash_apply", "clashfirst_clash_restore", "clashfirst_clash_refresh"):
            self.assertIn("%s()" % name, self.common)


if __name__ == "__main__":
    unittest.main()
