#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 modern ipk 生成 apk 包（实验性）。

OpenWrt 25.12 开始使用 apk-tools；这里把 ipk 的 control/data 重新封装为
apk 的 tar.gz 结构。产物需要先在 25.12 上实测安装/卸载，再放入 Release。
"""

import argparse
import io
import os
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
VERSION_FILE = os.path.join(ROOT, "src", "luci-app-adguardhome-lite", "VERSION")
PKG_NAME = "luci-app-adguardhome-lite"
REPO_URL = "https://github.com/Ozero-top/luci-app-adguardhome-lite"

SCRIPTS = {
    "preinst": ".pre-install",
    "postinst": ".post-install",
    "prerm": ".pre-deinstall",
    "postrm": ".post-deinstall",
}


def read_version():
    with open(VERSION_FILE, "r", encoding="utf-8") as f:
        text = f.read().strip()
    base, _, release = text.partition("-")
    return base, release or "1"


def parse_control(text):
    fields = {}
    for line in text.splitlines():
        if line.startswith(" ") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def normalize(name):
    while name.startswith("./"):
        name = name[2:]
    return name.lstrip("/")


def build_pkinfo(control, installed_size):
    pkgver = control.get("Version", "")
    # 1.3.6-1 -> 1.3.6-r1
    if "-" in pkgver:
        base, release = pkgver.rsplit("-", 1)
        pkgver = "%s-r%s" % (base, release)

    lines = [
        "pkgname = %s" % control.get("Package", PKG_NAME),
        "pkgver = %s" % pkgver,
        "pkgdesc = %s" % control.get("Description", ""),
        "url = %s" % REPO_URL,
        "arch = all",
        "size = %d" % installed_size,
        "origin = %s" % control.get("SourceName", PKG_NAME),
        "maintainer = %s" % control.get("Maintainer", ""),
        "license = GPL-3.0-or-later",
        "section = luci",
    ]
    for dep in control.get("Depends", "").split(","):
        dep = dep.strip()
        if dep:
            lines.append("depend = %s" % dep)
    return "\n".join(lines) + "\n"


def build_apk(ipk_path, out_dir):
    with tarfile.open(ipk_path, "r:gz") as outer:
        outer_files = {}
        for member in outer.getmembers():
            if member.isfile():
                outer_files[normalize(member.name)] = outer.extractfile(member).read()
        control_data = outer_files.get("control.tar.gz")
        data_data = outer_files.get("data.tar.gz")
        if control_data is None or data_data is None:
            raise SystemExit("ipk 结构不完整：%s" % ipk_path)

    control_files = {}
    with tarfile.open(fileobj=io.BytesIO(control_data), mode="r:gz") as control_tar:
        for member in control_tar.getmembers():
            if not member.isfile():
                continue
            name = normalize(member.name)
            control_files[name] = control_tar.extractfile(member).read()

    control = parse_control(control_files.get("control", b"").decode("utf-8", "replace"))
    installed_size = int(control.get("Installed-Size", "0")) * 1024

    os.makedirs(out_dir, exist_ok=True)
    out_name = "%s_%s_all.apk" % (PKG_NAME, control.get("Version", "unknown"))
    out_path = os.path.join(out_dir, out_name)

    pkinfo = build_pkinfo(control, installed_size)
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))

    def add_bytes(archive, name, data, mode, mtime):
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = mode
        info.mtime = mtime
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        archive.addfile(info, io.BytesIO(data))

    with tarfile.open(out_path, "w:gz", format=tarfile.GNU_FORMAT) as archive:
        add_bytes(archive, ".PKGINFO", pkinfo.encode("utf-8"), 0o644, epoch)
        for src, dst in SCRIPTS.items():
            if src in control_files:
                add_bytes(archive, dst, control_files[src], 0o755, epoch)

        with tarfile.open(fileobj=io.BytesIO(data_data), mode="r:gz") as data_tar:
            for member in data_tar.getmembers():
                name = normalize(member.name)
                if name in ("", "."):
                    continue
                if member.isdir():
                    info = tarfile.TarInfo(name)
                    info.type = tarfile.DIRTYPE
                    info.mode = member.mode or 0o755
                    info.mtime = epoch
                    info.uid = 0
                    info.gid = 0
                    info.uname = "root"
                    info.gname = "root"
                    archive.addfile(info)
                elif member.isfile():
                    add_bytes(archive, name, data_tar.extractfile(member).read(),
                              member.mode or 0o644, epoch)
                elif member.issym():
                    info = tarfile.TarInfo(name)
                    info.type = tarfile.SYMTYPE
                    info.linkname = member.linkname
                    info.mtime = epoch
                    archive.addfile(info)

    return out_path


def main():
    parser = argparse.ArgumentParser(description="从 modern ipk 生成实验性 apk")
    parser.add_argument("--ipk", default=None, help="modern ipk 路径")
    parser.add_argument("--out-dir", default=DIST, help="输出目录")
    args = parser.parse_args()

    ipk = args.ipk
    if not ipk:
        base, release = read_version()
        ipk = os.path.join(DIST, "%s_%s-%s_all.ipk" % (PKG_NAME, base, release))
    if not os.path.isfile(ipk):
        raise SystemExit("找不到 ipk：%s" % ipk)

    out = build_apk(ipk, args.out_dir)
    print("apk 已生成（实验性，需在 25.12 实测）：%s" % out)


if __name__ == "__main__":
    main()
