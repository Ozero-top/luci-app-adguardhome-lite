#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建离线安装包（.run）

用法：
    python tools/build_run.py

说明：
    将 dist/ 下的 modern 与 legacy 安装包连同 install.sh 一起打包为
    自解压脚本，适合通过 SSH 或固件离线安装功能直接执行。
"""

import hashlib
import io
import os
import subprocess
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
MODERN = "luci-app-adguardhome-lite_1.1.7-1_all.ipk"
LEGACY = "luci-app-adguardhome-lite_1.1.7-1-legacy_all.ipk"
OUTPUT = "luci-app-adguardhome-lite_1.1.7-1.run"

INSTALL_SH = """#!/bin/sh
# AdGuard Home 助手 - 离线安装脚本
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1

MODERN="{modern}"
LEGACY="{legacy}"

echo "=============================================="
echo " AdGuard Home 助手 - 离线安装"
echo "=============================================="

if [ ! -f "$MODERN" ] || [ ! -f "$LEGACY" ]; then
    echo "错误：安装包不完整，请重新下载 .run 文件。"
    exit 1
fi

echo "正在更新软件源（失败不影响本地安装）..."
opkg update >/dev/null 2>&1 || echo "警告：软件源更新失败，继续尝试本地安装。"

echo "正在安装（优先新版 LuCI 版本）..."
if opkg install --force-reinstall "$MODERN"; then
    echo "安装完成。"
else
    if opkg list-installed 2>/dev/null | grep -q '^luci-app-adguardhome-lite '; then
        echo "安装完成。"
    else
        echo "新版安装失败，尝试旧版 LuCI 兼容包..."
        if opkg install --force-reinstall "$LEGACY"; then
            echo "安装完成。"
        else
            echo "安装失败，请检查固件版本、依赖与剩余空间。"
            exit 1
        fi
    fi
fi

echo ""
echo "下一步："
echo "  1. 打开 LuCI：服务 → AdGuard Home 助手"
echo "  2. 安装内核 → 一键启用 → 打开控制台"
echo "  3. 默认账号 admin / 密码 admin123（请及时修改）"
echo ""
"""

HEADER = """#!/bin/sh
# AdGuard Home 助手 - 离线安装包（自解压）
# 用法：sh {output}
# 说明：解压到临时目录后执行 install.sh，不会修改固件其他文件。
set -u

PAYLOAD_OFFSET={offset}
TMPDIR="$(mktemp -d /tmp/agh-run.XXXXXX 2>/dev/null || echo /tmp/agh-run.$$)"
mkdir -p "$TMPDIR" || exit 1
cleanup() {{ rm -rf "$TMPDIR"; }}
trap cleanup EXIT INT TERM

tail -c +$PAYLOAD_OFFSET "$0" | tar -xz -C "$TMPDIR" || {{ echo "解压失败"; exit 1; }}
[ -f "$TMPDIR/install.sh" ] || {{ echo "安装包不完整"; exit 1; }}
sh "$TMPDIR/install.sh"
rc=$?
exit $rc
"""


def ensure_ipks():
    modern = os.path.join(DIST, MODERN)
    legacy = os.path.join(DIST, "legacy", LEGACY)

    if not os.path.isfile(modern) or not os.path.isfile(legacy):
        print("未找到安装包，先执行 tools/build_ipk.py ...")
        subprocess.check_call([sys.executable, os.path.join(ROOT, "tools", "build_ipk.py")], cwd=ROOT)

    return modern, legacy


def build_payload(modern, legacy):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz", format=tarfile.GNU_FORMAT) as tar:
        def add(path, name, mode):
            info = tarfile.TarInfo(name)
            info.size = os.path.getsize(path)
            info.mode = mode
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            with open(path, "rb") as f:
                tar.addfile(info, f)

        add(modern, MODERN, 0o644)
        add(legacy, LEGACY, 0o644)

        script = INSTALL_SH.format(modern=MODERN, legacy=LEGACY).encode("utf-8")
        info = tarfile.TarInfo("install.sh")
        info.size = len(script)
        info.mode = 0o755
        info.mtime = 0
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        tar.addfile(info, io.BytesIO(script))

    return buffer.getvalue()


def main():
    modern, legacy = ensure_ipks()
    payload = build_payload(modern, legacy)

    header_template = HEADER.format(output=OUTPUT, offset="0000000000")
    header_bytes = header_template.encode("utf-8")
    offset = len(header_bytes) + 1
    header = HEADER.format(output=OUTPUT, offset="%010d" % offset).encode("utf-8")

    if len(header) != len(header_bytes):
        raise RuntimeError("安装包头部长度计算异常")

    data = header + payload
    out_path = os.path.join(DIST, OUTPUT)
    with open(out_path, "wb") as f:
        f.write(data)

    digest = hashlib.sha256(data).hexdigest()

    sums_path = os.path.join(DIST, "SHA256SUMS")
    lines = []
    if os.path.isfile(sums_path):
        with open(sums_path, "r", encoding="utf-8") as f:
            lines = [line for line in f.read().splitlines() if OUTPUT not in line]
    lines.append("%s  %s" % (digest, OUTPUT))
    with open(sums_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("构建完成：")
    print("  %s" % out_path)
    print("  大小: %.1f KB" % (len(data) / 1024.0))
    print("  SHA256: %s" % digest)
    print("校验文件：%s" % sums_path)


if __name__ == "__main__":
    main()
