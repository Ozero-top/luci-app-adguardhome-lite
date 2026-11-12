include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-adguardhome-lite
PKG_VERSION:=1.1.8
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=Ozero-top

LUCI_TITLE:=AdGuard Home 助手
LUCI_DESCRIPTION:=面向零基础用户的 AdGuard Home LuCI 插件：一键安装内核、一键接管 DNS、中文引导
LUCI_DEPENDS:=+luci-base +luci-compat +luci-lib-jsonc +curl +wget-ssl +ca-bundle
LUCI_PKGARCH:=all

CONFLICTS:=luci-app-adguardhome

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
