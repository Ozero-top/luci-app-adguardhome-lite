#!/bin/sh
# AdGuard Home 助手 - 一键安装脚本（适用于 OpenWrt 24.10 / 25.12 等 apk 系统，也兼容 opkg）
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
#
# 国内加速（脚本与文件都走反代）：
#   curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -m https://gh-proxy.org
#
# 常用参数：
#   -v VERSION   指定版本（默认 1.3.0），可写 latest 取最新 Release
#   -m URL       指定 GitHub 反代（可重复），默认依次尝试 gh-proxy.org / ghfast.top / gh-proxy.com
#   --no-deps    不自动安装依赖
#   --src DIR    从本地源码目录安装（开发调试用）
#   --uninstall  卸载插件（保留配置与内核）
#   --purge      卸载并删除配置、内核、统计数据
#   -h           显示帮助

set -u

REPO="Ozero-top/luci-app-adguardhome-lite"
PKG="luci-app-adguardhome-lite"
VERSION="1.3.0"
MIRRORS=""
NO_DEPS=0
SRC_DIR=""
FORCE=0
ACTION="install"

RAW_BASE="https://raw.githubusercontent.com/$REPO/main"

log() { printf '%s\n' "$*"; }
warn() { printf '警告：%s\n' "$*" >&2; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

usage() {
	cat <<'EOF'
AdGuard Home 助手 安装脚本

  -v VERSION   指定版本号（默认 1.3.0，latest 表示最新 Release）
  -f, --force  强制更新：忽略版本标签，直接用 main 分支最新代码覆盖安装
  -m URL       指定 GitHub 反代，可重复，例如 -m https://gh-proxy.org
  --no-deps    跳过依赖安装
  --src DIR    从本地源码目录安装（开发调试用）
  --uninstall  卸载（保留 /etc/config/adguardhome_lite 与 /etc/AdGuardHome）
  --purge      卸载并删除配置、内核与统计数据
  -h, --help   显示帮助
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-v) shift; [ $# -gt 0 ] || die "-v 需要版本号"; VERSION="$1" ;;
		-m|--mirror) shift; [ $# -gt 0 ] || die "-m 需要地址"; MIRRORS="$MIRRORS $1" ;;
		--no-deps) NO_DEPS=1 ;;
		-f|--force) FORCE=1 ;;
		--src) shift; [ $# -gt 0 ] || die "--src 需要目录"; SRC_DIR="$1" ;;
		--uninstall) ACTION="uninstall" ;;
		--purge) ACTION="purge" ;;
		-h|--help) usage; exit 0 ;;
		*) die "未知参数：$1（用 -h 查看帮助）" ;;
	esac
	shift
done

[ "$(id -u)" = "0" ] || die "请用 root 运行"

PKG_MGR=""
if command -v apk >/dev/null 2>&1; then
	PKG_MGR="apk"
elif command -v opkg >/dev/null 2>&1; then
	PKG_MGR="opkg"
fi

clear_luci_cache() {
	rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
	rm -f /tmp/luci-modulecache/* 2>/dev/null
}

uninstall() {
	log "==> 停止服务并恢复 DNS"
	if [ -x /etc/init.d/adguardhome_lite ]; then
		/etc/init.d/adguardhome_lite stop >/dev/null 2>&1
		/etc/init.d/adguardhome_lite disable >/dev/null 2>&1
	fi
	rm -f /etc/rc.d/*adguardhome_lite 2>/dev/null
	pkill -f '/usr/bin/AdGuardHome/AdGuardHome' 2>/dev/null

	log "==> 删除插件文件"
	rm -rf /usr/share/adguardhome-lite
	rm -f /usr/lib/lua/luci/controller/adguardhome_lite.lua
	rm -rf /usr/lib/lua/luci/view/adguardhome_lite
	rm -rf /www/luci-static/resources/adguardhome-lite
	rm -f /usr/share/rpcd/acl.d/luci-app-adguardhome-lite.json
	rm -f /etc/init.d/adguardhome_lite
	rm -f /etc/uci-defaults/50_luci-adguardhome-lite
	rm -f /lib/upgrade/keep.d/luci-app-adguardhome-lite

	if [ "$ACTION" = "purge" ]; then
		log "==> 删除配置、内核与统计数据"
		rm -rf /etc/AdGuardHome /usr/bin/AdGuardHome
		rm -f /etc/AdGuardHome.yaml /etc/AdGuardHome.yaml.bak /etc/config/adguardhome_lite
	fi

	clear_luci_cache
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1
	log "卸载完成。DNS 已恢复为系统原始设置。"
}

install_deps() {
	[ "$NO_DEPS" = "1" ] && return 0

	case "$PKG_MGR" in
		apk)
			log "==> 检查依赖（apk）"
			for p in luci-compat luci-lua-runtime luci-lib-jsonc curl ca-bundle; do
				if ! apk info -e "$p" >/dev/null 2>&1; then
					apk add "$p" >/dev/null 2>&1 || warn "依赖 $p 安装失败，可稍后用 apk add $p 手动安装"
				fi
			done
			;;
		opkg)
			log "==> 检查依赖（opkg）"
			opkg update >/dev/null 2>&1 || warn "opkg update 失败，继续尝试安装"
			for p in luci-compat luci-lib-jsonc curl ca-bundle; do
				opkg list-installed 2>/dev/null | grep -q "^$p " || opkg install "$p" >/dev/null 2>&1 || warn "依赖 $p 安装失败"
			done
			;;
		*)
			warn "未找到 apk/opkg，跳过依赖检查"
			;;
	esac
}

have_downloader() {
	command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1
}

fetch() {
	url="$1"
	out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --connect-timeout 10 --retry 2 -o "$out" "$url" && [ -s "$out" ]
	else
		wget -q -O "$out" "$url" && [ -s "$out" ]
	fi
}

resolve_version() {
	[ "$VERSION" = "latest" ] || return 0
	api="https://api.github.com/repos/$REPO/releases/latest"
	_api_file="$1/api.json"
	for prefix in $MIRRORS "https://gh-proxy.org" "https://ghfast.top" ""; do
		if [ -n "$prefix" ]; then
			fetch "$prefix/$api" "$_api_file" || continue
		else
			fetch "$api" "$_api_file" || continue
		fi
		v=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' "$_api_file" | head -n 1)
		[ -n "$v" ] && { VERSION="$v"; return 0; }
	done
	warn "无法获取最新版本，改用默认 $VERSION"
}

download_source() {
	dest="$1"

	if [ -n "$SRC_DIR" ]; then
		[ -d "$SRC_DIR" ] || die "源码目录不存在：$SRC_DIR"
		return 0
	fi

	have_downloader || die "系统里没有 curl 或 wget"

	archive="$dest/src.tar.gz"
	OK=0
	if [ "$FORCE" = "1" ]; then
		# 强制更新：不取版本标签，直接用 main 分支最新代码覆盖同版本文件
		refs="refs/heads/main"
	else
		refs="refs/tags/v$VERSION refs/heads/main"
	fi
	for ref in $refs; do
		for prefix in $MIRRORS "https://gh-proxy.org" "https://ghfast.top" "https://gh-proxy.com" ""; do
			base="https://github.com/$REPO/archive/$ref.tar.gz"
			if [ -n "$prefix" ]; then
				url="$prefix/$base"
				label="$prefix"
			else
				url="$base"
				label="直连"
			fi
			log "==> 下载源码（$ref，$label）"
			rm -f "$archive"
			if fetch "$url" "$archive" && tar -tzf "$archive" >/dev/null 2>&1; then
				OK=1
				break
			fi
		done
		[ "$OK" = "1" ] && break
	done
	[ "$OK" = "1" ] || die "源码下载失败，请检查网络或换个反代（-m）"

	tar -xzf "$archive" -C "$dest" || die "源码解压失败"
}

install_from_dir() {
	src="$1"
	root="$src/root"

	[ -d "$root" ] || die "源码不完整：缺少 root 目录"

	log "==> 备份现有配置"
	keep=""
	if [ -f /etc/config/adguardhome_lite ]; then
		keep="$2/keep_adguardhome_lite"
		cp -p /etc/config/adguardhome_lite "$keep"
	fi

	log "==> 安装文件"
	mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/view \
		/www/luci-static/resources /usr/share/rpcd/acl.d /etc/uci-defaults /lib/upgrade/keep.d
	cp -a "$root/." / || die "复制 root 文件失败"
	cp -a "$src/luasrc/." /usr/lib/lua/luci/ || die "复制 luasrc 失败"
	cp -a "$src/htdocs/." /www/ || die "复制 htdocs 失败"

	if [ -n "$keep" ] && [ -f "$keep" ]; then
		cp -p "$keep" /etc/config/adguardhome_lite
		log "==> 保留原有 /etc/config/adguardhome_lite"
	fi

	chmod 755 /etc/init.d/adguardhome_lite 2>/dev/null
	chmod 755 /etc/uci-defaults/50_luci-adguardhome-lite 2>/dev/null
	chmod 755 /usr/share/adguardhome-lite/*.sh 2>/dev/null
	chmod 644 /usr/share/adguardhome-lite/AdGuardHome.yaml.template 2>/dev/null

	[ -x /etc/uci-defaults/50_luci-adguardhome-lite ] && /etc/uci-defaults/50_luci-adguardhome-lite >/dev/null 2>&1

	[ -f "$src/Makefile" ] && grep -q 'PKG_VERSION' "$src/Makefile" 2>/dev/null
	ver="$VERSION"
	[ -n "$SRC_DIR" ] && ver="local"
	printf '%s\n' "$ver" > /usr/share/adguardhome-lite/install_version 2>/dev/null
	# 清掉版本与更新检查缓存，面板立即显示新版本
	rm -f /var/run/adguardhome_lite_plugin_version /var/run/adguardhome_lite_plugin_update 2>/dev/null
}

main_install() {
	tmp="$(mktemp -d /tmp/agh-install.XXXXXX)" || die "创建临时目录失败"
	trap 'rm -rf "$tmp"' EXIT INT TERM

	[ -n "$SRC_DIR" ] && log "==> 使用本地源码：$SRC_DIR"
	[ "$FORCE" = "1" ] && log "==> 强制更新：忽略版本标签，安装 main 分支最新代码"
	install_deps
	# 强制更新直接从 main 安装，不需要再查询最新 Release 标签
	[ "$FORCE" = "1" ] || resolve_version "$tmp"
	download_source "$tmp"

	src="$SRC_DIR"
	if [ -z "$src" ]; then
		src="$(find "$tmp" -maxdepth 4 -type d -name 'luci-app-adguardhome-lite' -path '*/src/*' | head -n 1)"
		[ -n "$src" ] || die "在压缩包里找不到 src/luci-app-adguardhome-lite"
	fi

	install_from_dir "$src" "$tmp"

	log "==> 清理 LuCI 缓存"
	clear_luci_cache
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1

	if [ "$(uci -q get adguardhome_lite.main.enabled 2>/dev/null)" = "1" ]; then
		log "==> 服务已启用，重启中"
		/etc/init.d/adguardhome_lite restart >/dev/null 2>&1
	fi

	log ""
	log "安装完成（版本 $VERSION，包管理器：${PKG_MGR:-未知}）。"
	log "下一步：打开 LuCI → 服务 → AdGuard Home 助手 → 安装内核 → 一键启用。"
	log "卸载：运行本脚本并加 --uninstall（加 --purge 可同时删除配置与内核）。"
}

case "$ACTION" in
	uninstall|purge) uninstall ;;
	install) main_install ;;
esac
