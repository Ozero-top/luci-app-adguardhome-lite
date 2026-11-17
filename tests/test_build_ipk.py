#!/usr/bin/env python3
"""ipk 构建与内容断言：结构、权限、控制脚本、可复现性。"""

import hashlib
import io
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"

sys.path.insert(0, str(ROOT / "tools"))
import build_ipk  # noqa: E402


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

    def test_reproducible_build(self):
        again = Path(build_ipk.build_variant(str(SRC), str(self.out), "modern"))
        self.assertEqual(sha256(self.modern), sha256(again), "同一源码两次构建结果不一致")


if __name__ == "__main__":
    unittest.main()
