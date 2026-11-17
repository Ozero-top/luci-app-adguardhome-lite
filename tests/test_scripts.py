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


if __name__ == "__main__":
    unittest.main()
