#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""纯 Python 的 po -> lmo 转换，替代 OpenWrt 构建链里的 po2lmo/msgfmt。

lmo 格式（与 openwrt/luci modules/luci-base/src/po2lmo.c 一致）：
    [字符串池（每条 4 字节对齐补零）][索引（16 字节/条，按 key 升序）][池长度 u32 大端]
索引条目：key_id = sfh_hash(msgid, len)，val_id = 复数序号 + 1，offset/length 指向池。

用法：
    python tools/po2lmo.py src/luci-app-adguardhome-lite/po/zh-cn/luci-app-adguardhome-lite.po out.lmo
    python tools/po2lmo.py --check <po> <lmo>   # 校验已有 lmo 是否过期
"""

import argparse
import os
import re
import struct
import sys


def sfh_hash(data: bytes, init: int) -> int:
    """Paul Hsieh 的 SuperFastHash，与 lmo.c 的 sfh_hash 逐位一致。"""

    def g16(d, i):
        return (d[i + 1] << 8) + d[i]

    n = len(data)
    if n <= 0:
        return 0
    h = init & 0xFFFFFFFF
    rem, blocks, pos = n & 3, n >> 2, 0
    for _ in range(blocks):
        h = (h + g16(data, pos)) & 0xFFFFFFFF
        tmp = ((g16(data, pos + 2) << 11) ^ h) & 0xFFFFFFFF
        h = (((h << 16) & 0xFFFFFFFF) ^ tmp) & 0xFFFFFFFF
        pos += 4
        h = (h + (h >> 11)) & 0xFFFFFFFF
    if rem == 3:
        h = (h + g16(data, pos)) & 0xFFFFFFFF
        h = (h ^ ((h << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF
        b = data[pos + 2]
        h = (h ^ (((b - 256 if b > 127 else b) << 18) & 0xFFFFFFFF)) & 0xFFFFFFFF
        h = (h + (h >> 11)) & 0xFFFFFFFF
    elif rem == 2:
        h = (h + g16(data, pos)) & 0xFFFFFFFF
        h = (h ^ ((h << 11) & 0xFFFFFFFF)) & 0xFFFFFFFF
        h = (h + (h >> 17)) & 0xFFFFFFFF
    elif rem == 1:
        b = data[pos]
        h = (h + (b - 256 if b > 127 else b)) & 0xFFFFFFFF
        h = (h ^ ((h << 10) & 0xFFFFFFFF)) & 0xFFFFFFFF
        h = (h + (h >> 1)) & 0xFFFFFFFF
    h = (h ^ ((h << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = (h + (h >> 5)) & 0xFFFFFFFF
    h = (h ^ ((h << 4) & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = (h + (h >> 17)) & 0xFFFFFFFF
    h = (h ^ ((h << 25) & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = (h + (h >> 6)) & 0xFFFFFFFF
    return h


_UNESCAPE = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}


def _po_string(raw: str) -> str:
    """还原 po 字符串字面量（去掉首尾引号并处理转义）。"""
    body = raw.strip()[1:-1] if raw.strip().startswith('"') else raw.strip()
    out, esc = [], False
    for ch in body:
        if esc:
            out.append(_UNESCAPE.get(ch, ch))
            esc = False
        elif ch == "\\":
            esc = True
        else:
            out.append(ch)
    return "".join(out)


def parse_po(path: str):
    """极简 po 解析器：只关心 msgid/msgstr/msgctxt 续行，满足本项目词条即可。"""
    entries = []
    msgid = msgctxt = None
    vals = {}      # 复数序号 -> 字符串
    plural_num = 0
    cur = None

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("msgctxt "):
                if msgid is not None or vals:
                    entries.append((msgctxt, msgid, vals))
                msgid, msgctxt, vals = None, _po_string(line[8:]), {}
            elif line.startswith("msgid "):
                if msgid is not None or vals:
                    entries.append((msgctxt, msgid, vals))
                msgid, vals = _po_string(line[6:]), {}
            elif line.startswith("msgid_plural "):
                cur = None
            elif line.startswith("msgstr"):
                plural_num = int(line[7]) if line[6] == "[" else 0
                vals[plural_num] = _po_string(line[line.index('"'):])
            elif line.startswith('"') and msgid is not None and vals:
                last = max(vals)
                vals[last] += _po_string(line)
            elif line.startswith('"') and msgid is not None:
                msgid += _po_string(line)
    if msgid is not None or vals:
        entries.append((msgctxt, msgid, vals))
    return entries


def convert(po_path: str) -> bytes:
    entries = parse_po(po_path)
    pool = bytearray()
    index = []

    for msgctxt, msgid, vals in entries:
        if not msgid or msgid == "":
            # 头部条目：只取 Plural-Forms 行（po2lmo.c 同款行为）
            header = vals.get(0, "")
            m = re.search(r"Plural-Forms: ([^\\n]*)", header)
            if m:
                text = m.group(1).encode("utf-8")
                index.append((0, 0, len(pool), len(text)))
                pool.extend(text.ljust(len(text) + (4 - len(text) % 4) % 4, b"\x00"))
            continue
        if 0 not in vals or not vals[0]:
            continue
        key = ("%s\x01%s" % (msgctxt, msgid)).encode("utf-8") if msgctxt else msgid.encode("utf-8")
        for num in sorted(vals):
            if not vals[num]:
                continue
            val = vals[num].encode("utf-8")
            key_id = sfh_hash(key, len(key))
            val_id = sfh_hash(val, len(val))
            if key_id == val_id:
                continue
            index.append((key_id, num + 1, len(pool), len(val)))
            pool.extend(val.ljust(len(val) + (4 - len(val) % 4) % 4, b"\x00"))

    index.sort(key=lambda e: e[0])
    out = bytearray(pool)
    for key_id, val_id, off, ln in index:
        out.extend(struct.pack(">IIII", key_id, val_id, off, ln))
    out.extend(struct.pack(">I", len(pool)))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("po")
    ap.add_argument("lmo", nargs="?")
    ap.add_argument("--check", action="store_true", help="校验已有 lmo 是否与 po 一致")
    args = ap.parse_args()

    data = convert(args.po)
    if args.check:
        lmo = args.lmo or args.po.rsplit(".", 1)[0] + ".lmo"
        with open(lmo, "rb") as f:
            same = f.read() == data
        print("%s: %s" % (lmo, "一致" if same else "已过期"))
        sys.exit(0 if same else 1)

    lmo = args.lmo
    if not lmo:
        raise SystemExit("缺少输出路径")
    os.makedirs(os.path.dirname(os.path.abspath(lmo)), exist_ok=True)
    with open(lmo, "wb") as f:
        f.write(data)
    print("已生成：%s（%d 字节）" % (lmo, len(data)))


if __name__ == "__main__":
    main()
