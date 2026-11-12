#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建 luci-app-adguardhome-lite 的 OpenWrt .ipk 安装包。

用法：
    python tools/build_ipk.py                 # 同时构建 modern 和 legacy 两个版本
    python tools/build_ipk.py --variant modern
    python tools/build_ipk.py --variant legacy

说明：
- modern 版本依赖 luci-compat，适用于 OpenWrt 23.05 / 24.10 / ImmortalWrt / iStoreOS 等使用 JS LuCI 的固件。
- legacy 版本不依赖 luci-compat，适用于 OpenWrt 22.03 及更早的原生 Lua LuCI 固件。
- 两个版本使用相同的文件和包名，只能安装其中一个。
"""

import argparse
import gzip
import hashlib
import io
import os
import shutil
import stat
import sys
import tarfile
import tempfile

SOURCE_DATE_EPOCH = 1794096000  # 2026-11-08 00:00:00 UTC，保证构建结果可复现

PKG_NAME = "luci-app-adguardhome-lite"
PKG_VERSION = "1.1.7"
PKG_RELEASE = "1"
PKG_MAINTAINER = "Ozero-top"

# 文本文件统一转换为 LF，避免 Windows 换行导致脚本无法执行
TEXT_EXTENSIONS = {
    ".sh", ".lua", ".htm", ".json", ".css", ".js", ".config", ".conf", ".txt", ".md", ".template"
}


def norm_text(data: bytes) -> bytes:
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def is_text_file(path: str) -> bool:
    name = os.path.basename(path)
    if name in ("adguardhome_lite", "50_luci-adguardhome-lite", "luci-app-adguardhome-lite"):
        return True
    return os.path.splitext(path)[1].lower() in TEXT_EXTENSIONS


def copy_file(src: str, dst: str, force_mode: int = None):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, "rb") as f:
        data = f.read()

    if is_text_file(src):
        data = norm_text(data)

    with open(dst, "wb") as f:
        f.write(data)

    if force_mode is not None:
        os.chmod(dst, force_mode)
    else:
        os.chmod(dst, 0o644)


def copy_tree(src_root: str, dst_root: str):
    for dirpath, _dirnames, filenames in os.walk(src_root):
        rel = os.path.relpath(dirpath, src_root)
        target_dir = dst_root if rel == "." else os.path.join(dst_root, rel)
        os.makedirs(target_dir, exist_ok=True)

        for name in filenames:
            src = os.path.join(dirpath, name)
            if name in (".DS_Store", "Thumbs.db"):
                continue

            rel_file = os.path.normpath(os.path.join(rel, name))
            dst = os.path.join(dst_root, rel_file)

            mode = None
            if name.endswith(".sh") or os.sep + "init.d" + os.sep in dst or os.sep + "uci-defaults" + os.sep in dst:
                mode = 0o755

            copy_file(src, dst, mode)


def stage_data(src_root: str, staging: str):
    # root/ 下的文件直接对应系统根目录
    root_dir = os.path.join(src_root, "root")
    if os.path.isdir(root_dir):
        copy_tree(root_dir, staging)

    # luasrc/ -> /usr/lib/lua/luci
    luasrc = os.path.join(src_root, "luasrc")
    if os.path.isdir(luasrc):
        copy_tree(luasrc, os.path.join(staging, "usr", "lib", "lua", "luci"))

    # htdocs/ -> /www
    htdocs = os.path.join(src_root, "htdocs")
    if os.path.isdir(htdocs):
        copy_tree(htdocs, os.path.join(staging, "www"))


def add_path(tar: tarfile.TarFile, full_path: str, arcname: str, mode: int):
    info = tarfile.TarInfo(arcname)
    info.mtime = SOURCE_DATE_EPOCH
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mode = mode

    if os.path.isdir(full_path):
        info.type = tarfile.DIRTYPE
        tar.addfile(info)
        return

    info.type = tarfile.REGTYPE
    info.size = os.path.getsize(full_path)
    with open(full_path, "rb") as f:
        tar.addfile(info, f)


def package_file_mode(full_path: str, rel_path: str) -> int:
    rel = rel_path.replace(os.sep, "/")
    name = os.path.basename(full_path)

    if name in ("postinst", "preinst", "prerm", "postrm", "postinst-pkg", "prerm-pkg"):
        return 0o755
    if full_path.endswith(".sh"):
        return 0o755
    if "/init.d/" in "/" + rel or "/uci-defaults/" in "/" + rel:
        return 0o755
    return 0o644


def add_tree(tar: tarfile.TarFile, root: str, include_root: bool = True):
    if include_root:
        add_path(tar, root, "./", 0o755)

    dirs = []
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        filenames.sort()
        rel = os.path.relpath(dirpath, root)
        if rel != ".":
            dirs.append(dirpath)
        for name in filenames:
            files.append(os.path.join(dirpath, name))

    for dirpath in sorted(dirs):
        rel = os.path.relpath(dirpath, root)
        arc = "./" + rel.replace(os.sep, "/")
        add_path(tar, dirpath, arc, 0o755)

    for full in files:
        rel = os.path.relpath(full, root)
        arc = "./" + rel.replace(os.sep, "/")
        mode = package_file_mode(full, rel)
        add_path(tar, full, arc, mode)


def write_tar_gz(root: str, out_path: str, include_root: bool = True):
    with open(out_path, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=SOURCE_DATE_EPOCH) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.GNU_FORMAT) as tar:
                add_tree(tar, root, include_root)


def write_bytes_gz(data: bytes, out_path: str):
    with open(out_path, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=SOURCE_DATE_EPOCH) as gz:
            gz.write(data)


def dir_size_kb(root: str) -> int:
    total = 0
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            total += os.path.getsize(os.path.join(dirpath, name))
    return max(1, (total + 1023) // 1024)


def write_text(path: str, text: str, mode: int = 0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.chmod(path, mode)


def build_control(staging_control: str, variant: str, installed_kb: int):
    version = "%s-%s" % (PKG_VERSION, PKG_RELEASE)
    deps = "libc, luci-base, luci-lib-jsonc, curl, wget-ssl, ca-bundle"
    if variant == "modern":
        deps = "libc, luci-base, luci-compat, luci-lib-jsonc, curl, wget-ssl, ca-bundle"
    else:
        version += "-legacy"

    control = """Package: {name}
Version: {version}
Depends: {deps}
Conflicts: luci-app-adguardhome
Source: {name}
SourceName: {name}
Section: luci
Priority: optional
Maintainer: {maintainer}
Architecture: all
Installed-Size: {installed}
SourceDateEpoch: {epoch}
Description: AdGuard Home 助手：自动安装官方最新内核、一键接管 DNS、内置中文引导。
""".format(
        name=PKG_NAME,
        version=version,
        deps=deps,
        maintainer=PKG_MAINTAINER,
        installed=installed_kb,
        epoch=SOURCE_DATE_EPOCH,
    )

    write_text(os.path.join(staging_control, "control"), control)
    write_text(os.path.join(staging_control, "conffiles"), "/etc/config/adguardhome_lite\n")

    postinst = """#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0

mkdir -p /etc/AdGuardHome /usr/bin/AdGuardHome 2>/dev/null
chmod 755 /etc/init.d/adguardhome_lite 2>/dev/null
chmod 755 /usr/share/adguardhome-lite/*.sh 2>/dev/null
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null

# 升级/重装时如果配置里仍启用服务，则重建自启链接并重启
if [ -x /etc/init.d/adguardhome_lite ] && [ "$(uci -q get adguardhome_lite.main.enabled 2>/dev/null)" = "1" ]; then
	/etc/init.d/adguardhome_lite enable >/dev/null 2>&1
	/etc/init.d/adguardhome_lite restart >/dev/null 2>&1
fi

exit 0
"""
    write_text(os.path.join(staging_control, "postinst"), postinst, 0o755)

    prerm = """#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0

# 停止服务会同时恢复 DNSMasq 原始设置，避免卸载后断网
if [ -x /etc/init.d/adguardhome_lite ]; then
	/etc/init.d/adguardhome_lite stop >/dev/null 2>&1
fi

rm -f /var/run/adguardhome_lite_update.lock /var/run/adguardhome_lite_update.pid
rm -f /var/run/adguardhome_lite_update.code /var/run/adguardhome_lite_new_hash /var/run/adguardhome_lite_new_pass

exit 0
"""
    write_text(os.path.join(staging_control, "prerm"), prerm, 0o755)

    postrm = """#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	rm -f /etc/rc.d/*adguardhome_lite 2>/dev/null
fi

rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null

exit 0
"""
    write_text(os.path.join(staging_control, "postrm"), postrm, 0o755)


def build_variant(src_root: str, out_dir: str, variant: str) -> str:
    if not os.path.isdir(src_root):
        raise SystemExit("源码目录不存在：%s" % src_root)

    required = [
        "luasrc/controller/adguardhome_lite.lua",
        "luasrc/view/adguardhome_lite/panel.htm",
        "htdocs/luci-static/resources/adguardhome-lite/panel.css",
        "htdocs/luci-static/resources/adguardhome-lite/panel.js",
        "root/etc/init.d/adguardhome_lite",
        "root/usr/share/adguardhome-lite/update_core.sh",
    ]
    for rel in required:
        if not os.path.isfile(os.path.join(src_root, rel)):
            raise SystemExit("缺少必要文件：%s" % rel)

    os.makedirs(out_dir, exist_ok=True)

    work = tempfile.mkdtemp(prefix="agh_ipk_")
    try:
        staging_data = os.path.join(work, "data")
        staging_control = os.path.join(work, "control")
        os.makedirs(staging_data)
        os.makedirs(staging_control)

        stage_data(src_root, staging_data)

        installed_kb = dir_size_kb(staging_data)
        build_control(staging_control, variant, installed_kb)

        control_tgz = os.path.join(work, "control.tar.gz")
        data_tgz = os.path.join(work, "data.tar.gz")
        write_tar_gz(staging_control, control_tgz)
        write_tar_gz(staging_data, data_tgz)

        debian_binary = os.path.join(work, "debian-binary")
        write_text(debian_binary, "2.0\n")

        version = "%s-%s" % (PKG_VERSION, PKG_RELEASE)
        if variant == "legacy":
            version += "-legacy"
        out_name = "%s_%s_all.ipk" % (PKG_NAME, version)
        out_path = os.path.join(out_dir, out_name)

        outer_root = os.path.join(work, "outer")
        os.makedirs(outer_root)
        shutil.copy2(debian_binary, os.path.join(outer_root, "debian-binary"))
        shutil.copy2(control_tgz, os.path.join(outer_root, "control.tar.gz"))
        shutil.copy2(data_tgz, os.path.join(outer_root, "data.tar.gz"))

        # 外层 ipk 使用 tar.gz，与 OpenWrt 官方 ipk 结构一致
        write_tar_gz(outer_root, out_path, include_root=False)

        return out_path
    finally:
        shutil.rmtree(work, ignore_errors=True)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=["modern", "legacy", "both"], default="both")
    ap.add_argument("--src", default=None, help="插件源码目录")
    ap.add_argument("--out", default=None, help="输出目录")
    args = ap.parse_args()

    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_root = args.src or os.path.join(base, "src", "luci-app-adguardhome-lite")
    out_base = args.out or os.path.join(base, "dist")

    built = []

    if args.variant in ("modern", "both"):
        built.append(build_variant(src_root, out_base, "modern"))

    if args.variant in ("legacy", "both"):
        legacy_out = os.path.join(out_base, "legacy")
        built.append(build_variant(src_root, legacy_out, "legacy"))

    print("构建完成：")
    for path in built:
        print("  %s" % path)
        print("    大小: %.1f KB" % (os.path.getsize(path) / 1024.0))
        print("    SHA256: %s" % sha256_file(path))

    # 生成校验文件
    sums_path = os.path.join(out_base, "SHA256SUMS")
    lines = []
    for path in built:
        rel = os.path.relpath(path, out_base).replace(os.sep, "/")
        lines.append("%s  %s" % (sha256_file(path), rel))
    with open(sums_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("校验文件：%s" % sums_path)


if __name__ == "__main__":
    main()
