import sys
import tempfile
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_docs as bd  # noqa: E402


class BuildDocsTest(unittest.TestCase):

    def test_heading_lists_meta(self):
        md = "# 标题\n\n适用版本：`1.0.0` ｜ 适用固件：OpenWrt\n\n简介段落。\n\n## 第一节\n\n内容段落。\n\n### 小节\n\n- 列表 1\n- 列表 2\n\n1. 有序 1\n2. 有序 2\n"
        html = bd.parse(md)
        self.assertIn("<h1>标题</h1>", html)
        self.assertIn('class="meta"', html)
        self.assertIn('class="card" id="s1"', html)
        self.assertIn('class="sec"', html)
        self.assertIn("<li>列表 1</li>", html)
        self.assertIn("<li>有序 1</li>", html)

    def test_table_code(self):
        md = "## 表格\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```bash\necho hello\n```\n\n行内 `code`。\n"
        html = bd.parse(md)
        self.assertIn('class="table-wrap"', html)
        self.assertIn("<table>", html)
        self.assertIn("<pre><code", html)
        self.assertIn("echo hello", html)
        self.assertIn("<code>code</code>", html)

    def test_quote_class(self):
        md = "## 引用\n\n> ⚠️ 注意这是警告\n\n> 提示：这是提示\n\n> 普通引用\n"
        html = bd.parse(md)
        self.assertIn('class="warn"', html)
        self.assertIn('class="note"', html)

    def test_inline_formats(self):
        html = bd.render_inline("**粗体** *斜体* [链接](https://x.com)")
        self.assertIn("<strong>粗体</strong>", html)
        self.assertIn("<em>斜体</em>", html)
        self.assertIn('<a href="https://x.com">链接</a>', html)

    def test_build_html_structure(self):
        md_path = ROOT / "docs" / "安装与使用说明.md"
        html = bd.build_html(md_path, None, "1.0.0")
        self.assertIn("<!DOCTYPE html>", html)
        self.assertIn('<html lang="zh-CN">', html)
        self.assertIn("<main>", html)
        self.assertIn("</main>", html)
        self.assertIn("<footer>", html)
        self.assertIn("1.0.0", html)

    def test_self_check_roundtrip(self):
        tmp = Path(tempfile.mkdtemp(prefix="bd_test_"))
        md = tmp / "smoke.md"
        md.write_text("# Smoke\n\n适用版本：`1.0` ｜ 适用固件：TestOS\n\n简介。\n\n## H2\n\n内容。\n", encoding="utf-8")

        # 让 build_docs.py 自己写 html（和样式模板一致）
        rc_gen = subprocess.call(
            [sys.executable, str(ROOT / "tools" / "build_docs.py"), str(md)],
            cwd=str(ROOT), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.assertEqual(rc_gen, 0)

        # 校验：同一个 md 跑 --check 必须通过
        rc = subprocess.call(
            [sys.executable, str(ROOT / "tools" / "build_docs.py"), str(md), "--check"],
            cwd=str(ROOT), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.assertEqual(rc, 0)

        # 改 md 后 check 应失败
        md.write_text("# Changed\n\n适用版本：`1.0` ｜ 适用固件：TestOS\n\n简介。\n\n## H2\n\n内容。\n", encoding="utf-8")
        rc2 = subprocess.call(
            [sys.executable, str(ROOT / "tools" / "build_docs.py"), str(md), "--check"],
            cwd=str(ROOT), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.assertEqual(rc2, 1)


if __name__ == "__main__":
    unittest.main()
