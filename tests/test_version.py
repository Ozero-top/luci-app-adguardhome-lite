#!/usr/bin/env python3
"""版本号单一来源校验：VERSION / Makefile / install.sh / 构建脚本必须一致。"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"


def version_text() -> str:
    return (SRC / "VERSION").read_text(encoding="utf-8").strip()


class VersionSourceTest(unittest.TestCase):
    def test_version_format(self):
        text = version_text()
        self.assertRegex(text, r"^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$", "VERSION 格式应为「版本」或「版本-发行号」")

    def test_makefile_reads_version_file(self):
        makefile = (SRC / "Makefile").read_text(encoding="utf-8")
        self.assertIn("VERSION_FILE", makefile)
        self.assertNotRegex(makefile, r"(?m)^PKG_VERSION:=\d", "Makefile 不应再硬编码版本号")
        self.assertNotRegex(makefile, r"(?m)^PKG_RELEASE:=B", "Makefile 不应再硬编码发行号")

    def test_build_script_reads_version_file(self):
        script = (ROOT / "tools" / "build_ipk.py").read_text(encoding="utf-8")
        self.assertIn("read_version", script)
        self.assertNotRegex(script, r'(?m)^PKG_VERSION\s*=\s*"', "build_ipk.py 不应硬编码版本号")

    def test_install_sh_matches_version(self):
        script = (ROOT / "install.sh").read_text(encoding="utf-8")
        match = re.search(r'(?m)^VERSION="([^"]+)"', script)
        self.assertIsNotNone(match, "install.sh 缺少 VERSION 定义")
        self.assertEqual(match.group(1), version_text(), "install.sh 的版本与 VERSION 不一致")

    def test_build_ipk_parser(self):
        import sys

        sys.path.insert(0, str(ROOT / "tools"))
        import build_ipk

        version, release = build_ipk.read_version(str(SRC))
        expected = version_text() if "-" in version_text() else version_text() + "-1"
        self.assertEqual("%s-%s" % (version, release), expected)

    def test_readme_mentions_current_version(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        # README 允许只写版本号，不强制写发行号；至少主版本要能对上
        self.assertIn(version_text().split("-", 1)[0], readme)

    def test_build_run_uses_version(self):
        import sys

        sys.path.insert(0, str(ROOT / "tools"))
        import build_run

        # VERSION 可带发行号（1.3.5-2）也可不带（1.3.6），不带时发行号按惯例为 1
        expected = version_text() if "-" in version_text() else version_text() + "-1"
        self.assertEqual(build_run.PKG_VERSION, expected)
        self.assertIn(expected, build_run.MODERN)
        self.assertIn(expected, build_run.OUTPUT)


if __name__ == "__main__":
    unittest.main()
