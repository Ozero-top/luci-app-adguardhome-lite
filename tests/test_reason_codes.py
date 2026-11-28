#!/usr/bin/env python3
"""reason code、日志级别与 API 设置写入的静态契约。"""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "luci-app-adguardhome-lite"

sys.path.insert(0, str(ROOT / "tools"))
import build_panel  # noqa: E402

RUNTIME = (SRC / "luasrc" / "model" / "adguardhome_lite" / "runtime.lua").read_text(encoding="utf-8")
SETTINGS = (SRC / "luasrc" / "model" / "adguardhome_lite" / "actions" / "settings.lua").read_text(encoding="utf-8")
LOGS_ACTION = (SRC / "luasrc" / "model" / "adguardhome_lite" / "actions" / "logs.lua").read_text(encoding="utf-8")
CODES = (SRC / "luasrc" / "model" / "adguardhome_lite" / "codes.lua").read_text(encoding="utf-8")
COMMON = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "common.sh").read_text(encoding="utf-8")
APPLY = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "apply_settings.sh").read_text(encoding="utf-8")
UPDATE = (SRC / "root" / "usr" / "share" / "adguardhome-lite" / "update_core.sh").read_text(encoding="utf-8")
PANEL_JS = (SRC / "htdocs" / "luci-static" / "resources" / "adguardhome-lite" / "panel.js").read_text(encoding="utf-8")
PANEL_HTM = build_panel.assemble_htm(str(SRC))


class ReasonCodeTest(unittest.TestCase):
    def test_codes_registry(self):
        for code in ["invalid_param", "update_busy", "core_version_mismatch",
                     "config_restore_failed", "service_start_failed", "dns_hijack_conflict"]:
            self.assertIn(code, CODES)

    def test_json_error_returns_reason(self):
        self.assertIn("reason = reason or M.default_reason(status)", RUNTIME)
        self.assertIn("level = codes.level(reason)", RUNTIME)

    def test_state_files_use_codes(self):
        self.assertIn("failed:config_restore_failed", APPLY)
        self.assertIn("failed:service_start_failed", APPLY)
        self.assertIn("failed:${ERR_REASON:-core_update_failed}", UPDATE)

    def test_shell_log_levels(self):
        self.assertIn("log_event()", COMMON)
        self.assertIn("user.err", COMMON)
        self.assertIn('_tag="ERROR"', COMMON)
        self.assertIn('log_event error "$ERR_REASON"', UPDATE)

    def test_log_filter_ui(self):
        self.assertIn("agh-log-level", PANEL_HTM)
        self.assertIn("state.logLevel", PANEL_JS)
        self.assertIn('formvalue("level")', LOGS_ACTION)

    def test_cache_api_first_with_fallback(self):
        self.assertIn("cache_api_applied", SETTINGS)
        self.assertIn("patch_dns_config", SETTINGS)
        self.assertIn("cache_api_applied", APPLY)
        self.assertIn("_cache_api", APPLY)


if __name__ == "__main__":
    unittest.main()
