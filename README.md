# luci-app-adguardhome-lite

面向 OpenWrt / ImmortalWrt / iStoreOS 的 **AdGuard Home 一键版 LuCI 插件**，三步完成「装内核 → 接 DNS → 看状态」。

> 插件负责安装内核、接管 DNS 与服务管理；过滤规则、查询统计、家长控制等请直接在 AdGuard Home 面板中操作。

<div align=center>
<img src="https://ozero.top/media/2026/11/6af0738b04e0b3.88465351.png" width="600" height="566"> 
</div>

---

## 项目初衷

第一次用 AdGuard Home，会卡在两件事：不知道怎么接管 DNS，以及下载内核总是失败。

本插件的目标就是把这些门槛降到最低：

- **不用懂 DNS**：安装后按三步操作即可启用，默认接管 53 端口，停止或卸载时自动恢复。
- **不用手动找内核**：自动识别架构、自动下载；国内网络和 fake-IP 环境都有对应的加速与绕过方案。
- **不用预先配置**：内置默认账号、过滤规则、中文界面和日志周期，开箱即用。
- **不绑定设备**：同时兼容新版 LuCI 与旧版 Lua LuCI，覆盖 OpenWrt、ImmortalWrt、iStoreOS 及衍生固件。

需要更细的控制时，仍可在 AdGuard Home 面板或插件「高级配置」中修改。

---

## 功能特性

- **开箱即用**：安装内核 → 一键启用 → 打开控制台，全程中文引导，默认配置可直接使用。
- **三步上手**：每一步都有状态提示与失败原因，不需要命令行。
- **官方内核**：自动识别 CPU 架构，从 AdGuard 官方源下载最新稳定版内核。
- **GitHub 反代**：可选 `gh-proxy.org`、`ghproxy.cc`、`ghproxy.com`、`ghfast.top`，加速国内下载；失败自动回退官方 CDN 与 GitHub 直连。
- **fake-IP 兼容下载**：路由器使用 OpenClash 等 fake-IP DNS 时，自动通过公共 DNS 解析真实 IP 并用 `curl --resolve` 下载。
- **四种 DNS 接管方式**：接管 53、DNSMasq 上游、OpenClash 串联、仅面板。
- **OpenClash 共存**：保留 OpenClash 本地 DNS 劫持与 fake-IP/TUN 代理，同时让 AdGuard Home 参与过滤。
- **安全可控**：默认密码 `admin123`，可在插件内重置；停止服务或卸载时自动恢复 DNSMasq 设置。
- **配置可维护**：内置 YAML 模板（8 个过滤规则 + 1 个白名单，日志/统计保留 30 天）；高级配置保存前自动 `--check-config` 并保留备份。

---

## 兼容性

| 项目 | 说明 |
|---|---|
| 固件 | OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS，以及基于新版 LuCI 的衍生固件 |
| 旧固件 | OpenWrt 22.03 及更早的原生 Lua LuCI 使用 `legacy` 版本（不依赖 `luci-compat`） |
| 架构 | x86_64 / 386、ARM64、ARM v5/v6/v7/v8、MIPS / MIPSel / MIPS64 / MIPS64el、RISC-V 64、PPC64LE（暂不支持 LoongArch） |
| 实测环境 | Kwrt aarch64、iStoreOS x86_64；内核 AdGuard Home v0.107.80 |

> 与旧版 `luci-app-adguardhome` 冲突，安装前请先卸载旧插件及中文语言包。

---

## 安装

前往 [Releases](../../releases) 下载安装包。提供 `.ipk` 与离线 `.run` 两种形式，**同一设备只能安装其中一个版本**：

| 安装包 | 适用固件 |
|---|---|
| `luci-app-adguardhome-lite_<版本>_all.ipk` | OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS 等新版 LuCI |
| `luci-app-adguardhome-lite_<版本>-legacy_all.ipk` | OpenWrt 22.03 及更早的原生 Lua LuCI |
| `luci-app-adguardhome-lite_<版本>.run` | 离线自解压安装包，内含上述两个 ipk，自动选择可用版本 |

**LuCI 上传安装（推荐）**

1. 打开 `http://路由器IP` → **系统 → 软件包**。
2. 找到 **上传安装包**，选择对应 `.ipk` 上传。
3. 等待依赖安装完成，在 **服务** 菜单下打开 **AdGuard Home 一键版**。

**命令行安装（备用）**

```sh
opkg install /tmp/luci-app-adguardhome-lite_*.ipk
```

**离线 .run 安装**

将 `.run` 上传到路由器后执行：

```sh
sh /tmp/luci-app-adguardhome-lite_<版本>.run
```

脚本会自解压到临时目录，优先安装新版 LuCI 包，失败时自动回退 legacy 包，安装完成后自动清理临时文件。

Release 页面同时提供 `SHA256SUMS`，下载后可校验文件完整性。

---

## 三步上手

1. **安装内核**：概览页点击「安装/更新内核」，等待进度完成。
2. **一键启用**：点击「一键启用」，插件从内置模板生成配置并接管 DNS。
3. **打开控制台**：点击「打开控制台」，使用 `admin` / `admin123` 登录。

默认配置：

- 面板地址：`0.0.0.0:13800`
- 管理账号：`admin`，密码 `admin123`（建议首次登录后修改）
- DNS 接管：默认「接管 53 端口」，DNSMasq 自动移到 `1745`
- 上游 DNS：`127.0.0.1:1745`
- 过滤规则：8 个 + 1 个白名单
- 查询日志与统计：保留 30 天

---

## DNS 接管方式

| 方式 | 原理 | 适用场景 |
|---|---|---|
| 接管 53 端口（默认） | AdGuard Home 监听 53，DNSMasq 移到 1745 | 普通家庭网络 |
| DNSMasq 上游 | AdGuard Home 监听 5333，DNSMasq 继续占用 53 并转发 | 不想替换系统 DNS |
| **OpenClash 串联** | 保留 OpenClash DNS 劫持；DNSMasq 通过 `strict-order` + `server=/#/127.0.0.1#5333` 转发给 AdGuard Home，再由其转发到 Clash DNS（7874） | 同时运行 OpenClash 且必须开启 DNS 劫持 |
| 仅面板模式 | AdGuard Home 监听 5333，不修改 DNSMasq | 先体验面板或手动接管 |

### OpenClash 串联说明

OpenClash 的 DNS 劫持会把所有 53 端口查询重定向到它自己的 DNS，导致 AdGuard Home 收不到查询、去广告不生效。选择「OpenClash 串联」后插件会自动：

- AdGuard Home 监听 `5333`，避开 53 劫持；
- 在 `/etc/dnsmasq.conf` 写入带标记的 `strict-order` + `server=/#/127.0.0.1#5333`；
- AdGuard Home 上游指向 `openclash.config.dns_port`（默认 `7874`）；
- DNSMasq 端口与 OpenClash 劫持目标保持一致。

停止插件或切换模式时自动移除转发规则，DNS 恢复直连 Clash，不会断网。

验证：

```sh
nslookup pos.baidu.com 路由器IP    # 应返回 0.0.0.0
nslookup www.baidu.com 路由器IP    # 应正常解析
nslookup www.google.com 路由器IP   # 代理站点返回 198.18.x.x fake-IP
tail -6 /etc/dnsmasq.conf          # 应包含 BEGIN adguardhome-lite-openclash
```

---

## 项目结构

```text
.
├── src/luci-app-adguardhome-lite/       # 插件源码（OpenWrt 包结构）
│   ├── luasrc/                          # Lua 控制器与页面模板
│   ├── htdocs/luci-static/resources/    # 页面样式与脚本
│   ├── root/usr/share/adguardhome-lite/ # 安装、接管、更新等核心脚本
│   ├── root/etc/init.d/                 # procd 服务脚本
│   └── Makefile                         # OpenWrt SDK 构建入口
├── tools/build_ipk.py                   # 免 SDK 直接构建 ipk
├── tools/build_run.py                   # 构建离线自解压 .run 安装包
├── docs/安装与使用说明.md                # 安装、验证与排障文档
└── README.md
```

---

## 构建

### 方式一：直接生成 ipk（无需 OpenWrt SDK）

需要 Python 3：

```sh
python tools/build_ipk.py
```

构建完成后会在本地生成 modern（新版 LuCI）与 legacy（旧版 Lua LuCI）两个安装包，以及 `SHA256SUMS` 校验文件。

生成离线自解压安装包：

```sh
python tools/build_run.py
```

会在 ipk 基础上生成 `.run` 安装包，并将其校验值追加到 `SHA256SUMS`。

### 方式二：使用 OpenWrt SDK

将 `src/luci-app-adguardhome-lite/` 放入 SDK 的 `package/` 或 feed 目录：

```sh
make menuconfig   # LuCI → Applications → luci-app-adguardhome-lite
make package/luci-app-adguardhome-lite/compile V=s
```

---

## 文档

- [安装与使用说明](docs/安装与使用说明.md)：安装验证清单、DNS 接管方式详解、OpenClash 排查、卸载回滚与常见问题。
- 插件内「使用引导」标签包含三步说明与常见问题入口。

---

## 常见问题（摘要）

- **内核下载失败**：检查网络与系统时间；国内网络启用 GitHub 反代；fake-IP 环境已自动绕过。
- **启用后不能上网**：概览页点「停止并关闭自启」，插件会恢复 DNSMasq；仍异常可执行 `/etc/init.d/adguardhome_lite stop && /etc/init.d/dnsmasq restart`。
- **停止后面板打不开**：正常现象，面板随服务停止；重新「启动服务」即可。
- **改了面板端口打不开**：等待 5-10 秒，并确认服务运行中、UCI 端口与 YAML `address` 一致。
- **OpenClash 下不去广告**：DNS 接管方式选择「OpenClash 串联」。
- **重启后内核消失**：内核安装在 `/tmp` 内存位置，重新安装或改为内置存储。

更多内容见 [安装与使用说明](docs/安装与使用说明.md)。

---

## 更新记录

### v1.0.0（2026-11-08）

- 首次发布：三步完成内核安装、DNS 接管与服务启停
- 支持官方内核自动下载、GitHub 反代与 fake-IP 环境
- 四种 DNS 接管方式，新增「OpenClash 串联」共存模式
- 提供 `.ipk` 与离线 `.run` 两种安装包
- 内置 8 个过滤规则 + 1 个白名单，日志与统计保留 30 天

---

## 反馈与贡献

- 问题反馈：[GitHub Issues](https://github.com/Ozero-top/luci-app-adguardhome-lite/issues)
- 欢迎提交 Pull Request 改进插件或文档
- 如果这个项目帮到了你，欢迎点一个 Star

---

## 安全建议

- 不要将 `13800` 面板端口映射到公网。
- 默认密码仅供首次登录，请及时修改。
- 「接管 53 端口」会调整系统 DNSMasq，若同时运行 Pi-hole、旧版 AdGuard Home 或自建 DNS，请先确认端口不冲突。
- 高级配置会直接修改 `/etc/AdGuardHome.yaml`，修改前请备份。

---

## 许可证

[GPL-3.0-or-later](https://www.gnu.org/licenses/gpl-3.0.html)

## 声明

本项目为社区开源插件，与 AdGuard 官方无关；AdGuard Home 内核版权归其作者所有。请遵守当地法律法规与网络服务条款。
