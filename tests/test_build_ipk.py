#!/usr/bin/env python3
"""ipk 构建与内容断言：结构、权限、控制脚本、可复现性。"""

import hashlib
import io
import re
import struct
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"

sys.path.insert(0, str(ROOT / "tools"))
import build_ipk  # noqa: E402
import build_panel  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def outer_members(ipk: Path):
    with tarfile.open(ipk, "r:gz") as outer:
        return {m.name.lstrip("./"): outer.extractfile(m).read() for m in outer.getmembers() if m.isfile()}


def inner_members(blob: bytes):
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        result = {}
        for member in tar.getmembers():
            if member.isfile():
                result[member.name.lstrip("./")] = (tar.extractfile(member).read(), member.mode)
        return result


class BuildIpkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="agh_ipk_test_")
        cls.out = Path(cls.tmp.name)
        cls.modern = Path(build_ipk.build_variant(str(SRC), str(cls.out), "modern"))
        cls.legacy = Path(build_ipk.build_variant(str(SRC), str(cls.out / "legacy"), "legacy"))
        base, release = build_ipk.read_version(str(SRC))
        cls.version = "%s-%s" % (base, release)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_outer_structure(self):
        members = outer_members(self.modern)
        for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
            self.assertIn(name, members, "ipk 外层缺少 %s" % name)
        self.assertEqual(members["debian-binary"], b"2.0\n")

    def test_control_fields(self):
        members = outer_members(self.modern)
        control = inner_members(members["control.tar.gz"])
        text = control["control"][0].decode()
        self.assertIn("Package: luci-app-adguardhome-lite", text)
        self.assertIn("Version: %s" % self.version, text)
        self.assertIn("luci-compat", text)
        self.assertIn("Architecture: all", text)
        self.assertIn("conffiles", control)

        legacy_control = inner_members(outer_members(self.legacy)["control.tar.gz"])
        legacy_text = legacy_control["control"][0].decode()
        self.assertIn("Version: %s-legacy" % self.version, legacy_text)
        self.assertNotIn("luci-compat", legacy_text)

    def test_install_hooks(self):
        control = inner_members(outer_members(self.modern)["control.tar.gz"])
        postinst = control["postinst"][0].decode()
        prerm = control["prerm"][0].decode()
        self.assertEqual(control["postinst"][1], 0o755)
        self.assertEqual(control["prerm"][1], 0o755)
        self.assertIn("luci-indexcache", postinst)
        # opkg 升级遗留的旧 conffile 无代码引用，装完即清，避免被误当当前配置编辑
        self.assertIn("/etc/config/adguardhome_lite-opkg", postinst)
        self.assertIn("upgrade|failed-upgrade", prerm)
        self.assertIn("dns_mode.sh revert", prerm)

    def test_data_layout_and_modes(self):
        data = inner_members(outer_members(self.modern)["data.tar.gz"])
        required = [
            "etc/init.d/adguardhome_lite",
            "usr/share/adguardhome-lite/common.sh",
            "usr/share/adguardhome-lite/dns_mode.sh",
            "usr/share/adguardhome-lite/watchdog.sh",
            "usr/lib/lua/luci/controller/adguardhome_lite.lua",
            "usr/lib/lua/luci/model/adguardhome_lite/util.lua",
            "usr/lib/lua/luci/model/adguardhome_lite/codes.lua",
            "usr/lib/lua/luci/model/adguardhome_lite/agh.lua",
            "usr/lib/lua/luci/model/adguardhome_lite/selftest.lua",
            "usr/lib/lua/luci/view/adguardhome_lite/panel.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/header.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/tab-overview.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/tab-settings.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/tab-filters.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/tab-advanced.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/tab-logs.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/tab-guide.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/footer.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/modals.htm",
            "usr/lib/lua/luci/view/adguardhome_lite/panel/scripts.htm",
            "www/luci-static/resources/adguardhome-lite/panel.js",
            "www/luci-static/resources/adguardhome-lite/panel.css",
            "etc/config/adguardhome_lite",
        ]
        for name in required:
            self.assertIn(name, data, "安装包缺少 %s" % name)

        self.assertEqual(data["etc/init.d/adguardhome_lite"][1], 0o755)
        self.assertEqual(data["usr/share/adguardhome-lite/common.sh"][1], 0o755)
        self.assertEqual(data["www/luci-static/resources/adguardhome-lite/panel.js"][1], 0o644)
        self.assertNotIn("VERSION", data, "VERSION 只用于构建，不应安装到设备")

    def test_scripts_use_lf(self):
        data = inner_members(outer_members(self.modern)["data.tar.gz"])
        for name, (blob, _mode) in data.items():
            if name.endswith((".sh", ".lua", ".htm")) or "/init.d/" in name:
                self.assertNotIn(b"\r\n", blob, "%s 含 CRLF，设备上会执行失败" % name)

    def test_panel_js_built_from_parts(self):
        data = inner_members(outer_members(self.modern)["data.tar.gz"])
        blob = data["www/luci-static/resources/adguardhome-lite/panel.js"][0]
        self.assertEqual(blob.decode(), build_panel.assemble(str(SRC)),
                         "panel.js 与分片拼装结果不一致")
        leaked = [n for n in data if "/adguardhome-lite/panel/" in n]
        self.assertEqual(leaked, [], "分片源码不应安装到设备：%s" % leaked)

    def test_panel_css_built_from_parts(self):
        data = inner_members(outer_members(self.modern)["data.tar.gz"])
        blob = data["www/luci-static/resources/adguardhome-lite/panel.css"][0]
        self.assertEqual(blob.decode(), build_panel.assemble_css(str(SRC)),
                         "panel.css 与分片拼装结果不一致")
        self.assertTrue(blob.decode().startswith("@font-face"))

    def test_panel_css_parts_cover_every_rule(self):
        """分片拼装结果必须与拆分前的 panel.css 完全一致，且覆盖全部章节。"""
        css = build_panel.assemble_css(str(SRC))
        self.assertEqual(css.count("{"), css.count("}"), "CSS 大括号不配对")
        for section in ("外壳", "顶栏", "运行状态", "按钮", "子页签",
                        "查询日志表", "YAML 编辑器", "弹窗", "响应式"):
            self.assertIn("/* ========== %s" % section, css, "缺少章节：%s" % section)

    def test_panel_parts_cover_every_function(self):
        """分片必须覆盖 panel.js 的全部顶层函数，防止拆分时漏行。"""
        parts = build_panel.assemble(str(SRC))
        full = (SRC / "htdocs" / "luci-static" / "resources" / "adguardhome-lite" / "panel.js").read_text(encoding="utf-8")
        self.assertEqual(parts, full)
        self.assertTrue(parts.startswith("/*"))
        self.assertTrue(parts.rstrip().endswith("})();"))

    def test_panel_htm_split_into_parts(self):
        """panel.htm 只保留骨架，各 tab 由 panel/ 片段 include；片段必须成对闭合。"""
        view = SRC / "luasrc" / "view" / "adguardhome_lite"
        htm = (view / "panel.htm").read_text(encoding="utf-8")
        self.assertLessEqual(len(htm.splitlines()), 90, "panel.htm 应只保留骨架")

        parts = sorted(p.stem for p in (view / "panel").glob("*.htm"))
        self.assertEqual(parts, ["footer", "header", "modals", "scripts",
                                 "tab-advanced", "tab-filters", "tab-guide",
                                 "tab-logs", "tab-overview", "tab-settings"])
        for name in parts:
            self.assertIn("<%%+adguardhome_lite/panel/%s%%>" % name, htm,
                          "骨架未 include 片段：%s" % name)

        for name in ("overview", "settings", "filters", "advanced", "logs", "guide"):
            frag = (view / "panel" / ("tab-%s.htm" % name)).read_text(encoding="utf-8")
            self.assertEqual(frag.count("<section"), 1, "tab-%s 应恰好一个 section" % name)
            self.assertEqual(frag.count("</section>"), 1, "tab-%s section 未闭合" % name)

    def test_reproducible_build(self):
        again = Path(build_ipk.build_variant(str(SRC), str(self.out), "modern"))
        self.assertEqual(sha256(self.modern), sha256(again), "同一源码两次构建结果不一致")

    def test_i18n_lmo_installed_and_resolvable(self):
        """lmo 必须装入 i18n 目录，且英文 msgid 能按 LuCI 哈希查到中文。"""
        import build_po2lmo

        data = inner_members(outer_members(self.modern)["data.tar.gz"])
        for lang in ("zh-cn", "zh_Hans"):
            self.assertIn("usr/lib/lua/luci/i18n/adguardhome_lite.%s.lmo" % lang, data)

        blob = data["usr/lib/lua/luci/i18n/adguardhome_lite.zh-cn.lmo"][0]
        self.assertEqual(blob.decode() if False else blob,
                         build_po2lmo.convert(str(SRC / "po" / "zh-cn" / "luci-app-adguardhome-lite.po")))

        pool = int.from_bytes(blob[-4:], "big")
        idx = {}
        for k in range((len(blob) - 4 - pool) // 16):
            key_id, _vid, off, ln = struct.unpack(">IIII", blob[pool + k * 16: pool + k * 16 + 16])
            idx[key_id] = blob[off:off + ln].decode("utf-8")
        for msgid, expect in (("Save & Apply", "保存并应用"),
                              ("AdGuard Home Admin Center", "AdGuard Home 管理中心")):
            key = msgid.encode()
            self.assertEqual(idx.get(build_po2lmo.sfh_hash(key, len(key))), expect, "msgid 查询失败：%s" % msgid)

    def test_panel_skeleton_fully_translated(self):
        """骨架元素（标题/按钮/折叠/tab）不得再出现硬编码中文。"""
        htm = build_panel.assemble_htm(str(SRC))
        pattern = re.compile(r"<(h[1-4]|button|summary)\b[^>]*>([^<]*[\u4e00-\u9fa5][^<]*)</\1>")
        offenders = [m.group(2).strip()[:40] for m in pattern.finditer(htm)]
        self.assertEqual(offenders, [], "骨架仍有硬编码中文：%s" % offenders)


if __name__ == "__main__":
    unittest.main()
