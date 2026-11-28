#!/usr/bin/env python3
"""Markdown → HTML 文档生成器。

用法：
  python tools/build_docs.py                 # 转换 docs/*.md → 同名 .html
  python tools/build_docs.py --check         # 校验现有 html 是否等于从 md 生成的结果（失败时退出码 1）
  python tools/build_docs.py <file.md>       # 只转换指定文件

设计：
  - 零第三方依赖，内置轻量 md 解析器，覆盖本项目 md 用到的全部语法。
  - 输出 HTML 保持现有 docs/*.html 的结构约定（class="card"/"sec"/"table-wrap"/"meta"/"tag"
    等），样式从同类文档的 <style> 段复用，保证视觉一致。
  - 版本号自动从 VERSION 文件读取。
"""

from __future__ import annotations
import sys
import re
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
VERSION_FILE = ROOT / "src" / "luci-app-adguardhome-lite" / "VERSION"

# ---------- 轻量 md 解析 ----------

def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")

INLINE_CODE_RE = re.compile(r"`([^`]+)`")
BOLD_RE = re.compile(r"\*\*(.+?)\*\*")
ITALIC_RE = re.compile(r"(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

def render_inline(text: str) -> str:
    """行内格式：code / bold / italic / link。"""
    text = escape(text)
    placeholders: list[str] = []
    def _ph(m):
        placeholders.append(f"<code>{escape(m.group(1))}</code>")
        return f"\x00PH{len(placeholders)-1}\x00"
    text = INLINE_CODE_RE.sub(_ph, text)
    text = BOLD_RE.sub(lambda m: f"<strong>{m.group(1)}</strong>", text)
    text = ITALIC_RE.sub(lambda m: f"<em>{m.group(1)}</em>", text)
    text = LINK_RE.sub(lambda m: f'<a href="{escape(m.group(2))}">{m.group(1)}</a>', text)
    for i, ph in enumerate(placeholders):
        text = text.replace(f"\x00PH{i}\x00", ph)
    return text

def parse(md: str) -> str:
    """将 markdown 正文转为 <main> 内的 HTML 片段。"""
    lines = md.splitlines()
    out: list[str] = []
    i = 0
    N = len(lines)
    section_count = 0

    # 首段：h1 + 简介 + 元信息
    doc_title = "文档"
    doc_subtitle = ""
    meta_version = ""
    meta_firmware = ""

    if i < N and lines[i].startswith("# "):
        doc_title = lines[i][2:].strip()
        i += 1
        while i < N and lines[i].strip() == "":
            i += 1
        # 元信息行（适用版本/固件）
        if i < N and lines[i].strip().startswith("适用版本"):
            meta_line = lines[i].strip()
            m = re.search(r"适用版本[：:]\s*(\S+)", meta_line)
            if m:
                meta_version = m.group(1)
            m2 = re.search(r"适用固件[：:]\s*(.+)", meta_line)
            if m2:
                meta_firmware = m2.group(1).strip()
            i += 1
            while i < N and lines[i].strip() == "":
                i += 1
        # 副标题（元信息之后紧接着的非块行）
        if i < N and lines[i].strip() and not lines[i].startswith(("#", "##", "```", "|", ">", "-", "*", "+", "---", "***")):
            doc_subtitle = lines[i].strip()
            i += 1

    out.append('<div class="doc-head">')
    out.append(f"  <h1>{escape(doc_title)}</h1>")
    if doc_subtitle:
        out.append(f"  <p>{render_inline(doc_subtitle)}</p>")
    if meta_version or meta_firmware:
        out.append('  <div class="meta">')
        if meta_version:
            out.append(f'    <span>适用版本 {render_inline(meta_version)}</span>')
        if meta_firmware:
            out.append(f'    <span>{escape(meta_firmware)}</span>')
        out.append("  </div>")
    out.append("</div>")

    # 正文
    while i < N:
        line = lines[i]
        stripped = line.strip()

        if stripped == "":
            i += 1
            continue

        if stripped in ("---", "***", "___"):
            i += 1
            continue

        # 代码块
        if stripped.startswith("```"):
            lang = stripped[3:].strip()
            i += 1
            buf: list[str] = []
            while i < N and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            if i < N:
                i += 1
            out.append(f"<pre><code class=\"language-{escape(lang)}\">{escape(chr(10).join(buf))}</code></pre>")
            continue

        # 表格
        if stripped.startswith("|"):
            table_lines: list[str] = []
            while i < N and lines[i].strip().startswith("|"):
                table_lines.append(lines[i].strip())
                i += 1
            body = [t for t in table_lines if not re.match(r"^\|\s*:?-{2,}:?\s*\|", t)]
            out.append('<div class="table-wrap">')
            out.append("  <table>")
            for row_idx, trow in enumerate(body):
                cells = [c.strip() for c in trow.strip("|").split("|")]
                tag = "th" if row_idx == 0 else "td"
                out.append("    <tr>")
                for c in cells:
                    out.append(f"      <{tag}>{render_inline(c)}</{tag}>")
                out.append("    </tr>")
            out.append("  </table>")
            out.append("</div>")
            continue

        # 引用块 → 根据内容判断 note / warn / tip
        if stripped.startswith(">"):
            buf = []
            while i < N and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].lstrip())
                i += 1
            cls = "note"
            first = buf[0] if buf else ""
            if any(kw in first for kw in ("注意", "⚠️", "警告", "不要")):
                cls = "warn"
            elif any(kw in first for kw in ("提示", "💡", "技巧")):
                cls = "tip"
            elif any(kw in first for kw in ("常见", "FAQ", "问题")):
                cls = "faq"
            out.append(f'<p class="{cls}">{render_inline(" ".join(buf))}</p>')
            continue

        # h2 → 开启新 section；但 "Android App" 不带编号的 h2 也单独成 section
        m = re.match(r"^##\s+(.*)$", stripped)
        if m:
            # 关闭当前 section（如果有）
            if section_count > 0 and out and out[-1] != "</section>":
                out.append("</section>")
            section_count += 1
            title_text = m.group(1).strip()
            sid = f"s{section_count}"
            # h2 里如果有 `{#xxx}` 语法就用那个做 id
            m2 = re.search(r"\{#([a-zA-Z0-9_-]+)\}\s*$", title_text)
            if m2:
                sid = m2.group(1)
                title_text = title_text[:m2.start()].strip()
            out.append(f'<section class="card" id="{sid}">')
            out.append(f'  <h2 class="sec">{render_inline(title_text)}</h2>')
            i += 1
            continue

        # h3
        m3 = re.match(r"^###\s+(.*)$", stripped)
        if m3:
            out.append(f"<h3>{render_inline(m3.group(1).strip())}</h3>")
            i += 1
            continue

        # 无序列表
        if re.match(r"^[-*+]\s", stripped):
            out.append("<ul>")
            while i < N and re.match(r"^\s*[-*+]\s", lines[i]):
                item = re.sub(r"^\s*[-*+]\s+", "", lines[i])
                out.append(f"  <li>{render_inline(item)}</li>")
                i += 1
            out.append("</ul>")
            continue

        # 有序列表
        if re.match(r"^\d+\.\s", stripped):
            out.append("<ol>")
            while i < N and re.match(r"^\s*\d+\.\s", lines[i]):
                item = re.sub(r"^\s*\d+\.\s+", "", lines[i])
                out.append(f"  <li>{render_inline(item)}</li>")
                i += 1
            out.append("</ol>")
            continue

        # 普通段落
        buf = [stripped]
        i += 1
        while i < N:
            nxt = lines[i].strip()
            if nxt == "" or nxt.startswith(("##", "```", "|", ">", "-", "*", "+", "#", "---", "***", "___")) or re.match(r"^\d+\.\s", nxt):
                break
            buf.append(nxt)
            i += 1
        out.append(f"<p>{render_inline(' '.join(buf))}</p>")

    # 关闭最后一个 section
    if section_count > 0 and out and out[-1] != "</section>":
        out.append("</section>")

    return "\n".join(out)

# ---------- 模板拼装 ----------

DEFAULT_CSS = """
:root { color-scheme: light dark; --fg:#222; --bg:#fff; --code-bg:#f6f8fa; --border:#e5e7eb; --accent:#2563eb; }
@media (prefers-color-scheme: dark) { :root { --fg:#e5e7eb; --bg:#11151d; --code-bg:#1a2030; --border:#2a3142; --accent:#60a5fa; } }
* { box-sizing: border-box; }
body { margin: 0; font: 15px/1.7 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "PingFang SC", "Microsoft YaHei", sans-serif; color: var(--fg); background: var(--bg); }
main { max-width: 820px; margin: 40px auto; padding: 0 24px 60px; }
.doc-head h1 { margin: 0 0 8px; font-size: 28px; }
.doc-head .meta { color: #6b7280; font-size: 13px; }
h1, h2, h3 { color: var(--fg); }
h2 { margin: 36px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--border); font-size: 22px; }
h3 { margin: 24px 0 8px; font-size: 17px; }
p { margin: 8px 0; }
ul, ol { padding-left: 22px; margin: 8px 0; }
li { margin: 3px 0; }
pre { background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px; padding: 12px 14px; overflow-x: auto; font-size: 13px; }
code { font-family: "JetBrains Mono", Consolas, Menlo, monospace; font-size: 13px; }
:not(pre) > code { background: var(--code-bg); padding: 1px 6px; border-radius: 4px; }
blockquote { border-left: 3px solid var(--accent); padding: 2px 14px; margin: 10px 0; color: #6b7280; }
table { border-collapse: collapse; margin: 10px 0; width: 100%; font-size: 14px; }
th, td { border: 1px solid var(--border); padding: 6px 10px; text-align: left; }
th { background: var(--code-bg); }
hr { border: none; border-top: 1px solid var(--border); margin: 28px 0; }
footer { text-align: center; color: #6b7280; font-size: 12px; padding: 20px; border-top: 1px solid var(--border); }
"""

def read_version() -> str:
    try:
        return VERSION_FILE.read_text(encoding="utf-8").strip()
    except Exception:
        return "0.0.0-0"

def extract_style(html: str) -> str | None:
    m = re.search(r"<style>(.*?)</style>", html, re.DOTALL | re.IGNORECASE)
    return m.group(1) if m else None

def build_html(md_path: Path, style_css: str | None, version: str) -> str:
    md = md_path.read_text(encoding="utf-8")
    main_body = parse(md)
    css = style_css or DEFAULT_CSS
    title = f"{md_path.stem} · {version}"
    footer = f"AdGuard Home 管理中心 · 使用说明 · {version} · 适用于 OpenWrt / ImmortalWrt / iStoreOS"

    # 给 main 内部内容做 4 空格缩进
    indented = "\n".join("    " + ln if ln.strip() else "" for ln in main_body.splitlines())
    return (
        "<!DOCTYPE html>\n"
        '<html lang="zh-CN">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        '  <meta name="viewport" content="width=device-width,initial-scale=1">\n'
        f"  <title>{escape(title)}</title>\n"
        f"<style>{css}</style>\n"
        "</head>\n"
        "<body>\n"
        "  <main>\n"
        + indented + "\n"
        "  </main>\n"
        f"<footer>{escape(footer)}</footer>\n"
        "</body>\n"
        "</html>\n"
    )

# ---------- 入口 ----------

def main() -> int:
    ap = argparse.ArgumentParser(description="md → html 文档生成器")
    ap.add_argument("files", nargs="*", type=Path, help="指定 md 文件；不传则处理 docs/*.md")
    ap.add_argument("--check", action="store_true", help="校验现有 html 是否匹配 md")
    ap.add_argument("--css-from", type=Path, help="从现有 html 抽取样式段（默认自动找 docs/安装与使用说明.html）")
    args = ap.parse_args()

    if args.files:
        mds = list(args.files)
    else:
        mds = sorted(DOCS.glob("*.md"))
    if not mds:
        print("没有找到 md 文件", file=sys.stderr)
        return 1

    style_css = None
    css_src = args.css_from
    if css_src is None:
        preferred = DOCS / "安装与使用说明.html.bak"
        if preferred.exists():
            css_src = preferred
    if css_src and css_src.exists():
        style_css = extract_style(css_src.read_text(encoding="utf-8"))
        if style_css is not None:
            print(f"[build_docs] 从 {css_src.name} 复用 <style> 段（{len(style_css)} 字节）")

    version = read_version()
    ok = True
    for md in mds:
        html = build_html(md, style_css, version)
        html_path = md.with_suffix(".html")
        if args.check:
            if not html_path.exists():
                print(f"[build_docs][FAIL] {html_path.name} 不存在，需要从 {md.name} 生成")
                ok = False
                continue
            existing = html_path.read_text(encoding="utf-8").replace("\r\n", "\n")
            target = html.replace("\r\n", "\n")
            if existing != target:
                print(f"[build_docs][FAIL] {html_path.name} 与 {md.name} 不同步")
                ok = False
            else:
                print(f"[build_docs][OK] {html_path.name}")
        else:
            html_path.write_text(html, encoding="utf-8", newline="")
            print(f"[build_docs] 写入 {html_path.name} ({len(html)} 字节)")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
