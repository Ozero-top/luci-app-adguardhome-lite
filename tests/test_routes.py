#!/usr/bin/env python3
"""前后端契约：视图声明的路由必须由 Lua 控制器提供，写操作必须校验 CSRF 令牌。"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"
CTRL = SRC / "luasrc" / "controller" / "adguardhome_lite.lua"
VIEW = SRC / "luasrc" / "view" / "adguardhome_lite" / "panel.htm"
AGH = SRC / "luasrc" / "model" / "adguardhome_lite" / "agh.lua"

MUTATIONS = [
    "action_stats_clear",
    "action_filters_save",
    "action_retention_save",
    "action_core_install",
    "action_service",
    "action_password",
    "action_settings_save",
    "action_yaml_save",
    "action_legacy_clean",
]


class RoutesTest(unittest.TestCase):
    def setUp(self):
        self.controller = CTRL.read_text(encoding="utf-8")
        self.view = VIEW.read_text(encoding="utf-8")

    def controller_routes(self):
        return set(re.findall(
            r'entry\(\{\s*"admin",\s*"services",\s*"adguardhome_lite",\s*"([a-z_]+)"\s*\}',
            self.controller))

    def view_routes(self):
        return set(re.findall(
            r'url\(\[\[admin\]\],\s*\[\[services\]\],\s*\[\[adguardhome_lite\]\],\s*\[\[([a-z_]+)\]\]\)',
            self.view))

    def test_view_routes_exist(self):
        missing = self.view_routes() - self.controller_routes()
        self.assertEqual(missing, set(), "视图调用了控制器不存在的路由：%s" % sorted(missing))

    def test_mutations_require_post(self):
        for name in MUTATIONS:
            match = re.search(r"(?ms)^function %s\(\)\n(.*?)^end$" % name, self.controller)
            self.assertIsNotNone(match, "缺少函数 %s" % name)
            self.assertIn("require_post()", match.group(1), "%s 未校验 POST 令牌" % name)

    def test_password_not_in_process_arguments(self):
        agh = AGH.read_text(encoding="utf-8")
        self.assertNotIn("-u %q", agh, "凭据不应出现在 curl -u 参数中")
        self.assertIn("--netrc-file", agh)


if __name__ == "__main__":
    unittest.main()
