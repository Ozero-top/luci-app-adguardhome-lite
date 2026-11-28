#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 panel/ 分片拼装成 panel.js 与 panel.css。

两者都是构建产物，唯一来源是插件根目录下的分片（分片本身不会安装到设备）：
- panel/*.js      -> htdocs/luci-static/resources/adguardhome-lite/panel.js
- panel/css/*.css -> htdocs/luci-static/resources/adguardhome-lite/panel.css

用法：
    python tools/build_panel.py            # 重新生成 panel.js 与 panel.css
    python tools/build_panel.py --check    # 只校验产物与分片是否一致
"""

import argparse
import os
import re
import sys

ROOT = "htdocs/luci-static/resources/adguardhome-lite"

# (分片目录, 后缀, 产物路径)
TARGETS = [
    (os.path.join("panel"), ".js", os.path.join(ROOT, "panel.js")),
    (os.path.join("panel", "css"), ".css", os.path.join(ROOT, "panel.css")),
]


def parts_dir(src_root: str, rel_parts: str) -> str:
    return os.path.join(src_root, rel_parts)


def out_path(src_root: str, rel_out: str) -> str:
    return os.path.join(src_root, rel_out)


def assemble_dir(src_root: str, rel_parts: str, suffix: str) -> str:
    folder = parts_dir(src_root, rel_parts)
    if not os.path.isdir(folder):
        raise SystemExit("缺少分片目录：%s" % folder)

    names = sorted(n for n in os.listdir(folder) if n.endswith(suffix))
    if not names:
        raise SystemExit("分片目录为空：%s" % folder)

    chunks = []
    for name in names:
        with open(os.path.join(folder, name), "r", encoding="utf-8", newline="") as f:
            chunks.append(f.read())
    return "".join(chunks)


def assemble(src_root: str) -> str:
    """panel.js 内容。"""
    return assemble_dir(src_root, "panel", ".js")


def assemble_css(src_root: str) -> str:
    """panel.css 内容。"""
    return assemble_dir(src_root, os.path.join("panel", "css"), ".css")


def assemble_htm(src_root: str) -> str:
    """把 panel.htm 骨架里的 <%+adguardhome_lite/panel/x%> 原地展开成完整模板。

    设备上由 LuCI 运行时做同样的 include，这里只是为了让测试能校验完整页面。
    """
    view = os.path.join(src_root, "luasrc", "view", "adguardhome_lite")
    with open(os.path.join(view, "panel.htm"), "r", encoding="utf-8", newline="") as f:
        text = f.read()

    def expand(match):
        path = os.path.join(view, "panel", match.group(1) + ".htm")
        with open(path, "r", encoding="utf-8", newline="") as f:
            return f.read()

    return re.sub(r"<%\+adguardhome_lite/panel/([\w-]+)%>", expand, text)


def build(src_root: str) -> list:
    written = []
    for rel_parts, suffix, rel_out in TARGETS:
        text = assemble_dir(src_root, rel_parts, suffix)
        path = out_path(src_root, rel_out)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        written.append(path)
    return written


def check(src_root: str) -> bool:
    for rel_parts, suffix, rel_out in TARGETS:
        path = out_path(src_root, rel_out)
        if not os.path.isfile(path):
            return False
        with open(path, "r", encoding="utf-8", newline="") as f:
            if f.read() != assemble_dir(src_root, rel_parts, suffix):
                return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=None, help="插件源码目录")
    ap.add_argument("--check", action="store_true", help="只校验，不写文件")
    args = ap.parse_args()

    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_root = args.src or os.path.join(base, "src", "luci-app-adguardhome-lite")

    if args.check:
        ok = check(src_root)
        print("panel.js / panel.css %s" % ("与分片一致" if ok else "已过期，请运行 tools/build_panel.py"))
        sys.exit(0 if ok else 1)

    for path in build(src_root):
        print("已生成：%s（%d 字节）" % (path, os.path.getsize(path)))


if __name__ == "__main__":
    main()
