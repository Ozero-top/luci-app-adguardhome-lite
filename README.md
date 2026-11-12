# AdGuard Home 助手

面向 OpenWrt / ImmortalWrt / iStoreOS 的 **AdGuard Home 助手**（LuCI 插件），三步完成「装内核 → 接 DNS → 看状态」。

> 插件负责安装内核、接管 DNS 与服务管理；过滤规则、查询统计、家长控制等请直接在 AdGuard Home 面板中操作。

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

<div align=center>
<img src="https://ozero.top/media/2026/11/6af2d7b3091938.16423231.png" width="600" height="794"> 
</div>

---

> **搭配浏览器扩展效果更佳**
>
> 路由器上的 AdGuard Home 只能按域名拦截，页面内的广告位、同域名广告和追踪脚本需要浏览器端过滤。建议在常用浏览器再装一个 AdGuard 浏览器扩展（或 uBlock Origin），两者叠加后，adblock-tester.com、adblock.turtlecute.org 这类测试通常可以达到 95% 以上。
>
> - 官方下载页（自动识别浏览器）：<https://adguard.com/zh_cn/adguard-browser-extension/overview.html>
> - Chrome 应用商店：<https://chromewebstore.google.com/detail/adguard-adblocker/bgnkhhnnamicmpeenaelnjfhikgbkllg>
> - Edge：在扩展商店搜索「AdGuard AdBlocker」即可；Firefox：在 addons.mozilla.org 搜索「AdGuard」
>
> 只装扩展不装路由器端也可以，但手机、电视等无法装扩展的设备就过滤不到；只装路由器端则页面内广告会剩下一些，推荐两者一起用。

## 功能特性

- **开箱即用**：安装内核 → 一键启用 → 打开控制台，全程中文引导，默认配置可直接使用。
- **三步上手**：每一步都有状态提示与失败原因，不需要命令行。
- **官方内核**：自动识别 CPU 架构，从 AdGuard 官方源下载最新稳定版内核。
- **GitHub 反代**：可选 `gh-proxy.org`、`ghproxy.cc`、`ghproxy.com`、`ghfast.top`，加速国内下载；失败自动回退官方 CDN 与 GitHub 直连。
- **fake-IP 兼容下载**：路由器使用 OpenClash 等 fake-IP DNS 时，自动通过公共 DNS 解析真实 IP 并用 `curl --resolve` 下载。
- **四种 DNS 接管方式**：接管 53、DNSMasq 上游、OpenClash 前置、仅面板（「OpenClash 串联」已下线，旧配置会自动迁移）。
- **OpenClash 共存**：推荐「接管 53 + OpenClash DNS 劫持/转发」，在保留 fake-IP 与分流的同时，让 AdGuard Home 直接看到每台设备；插件会自建 `agh_dns_redirect` 链把设备的 53 查询收回，因此 OpenClash 劫持指向 `53`、`1745` 还是 `7874` 都不会绕过过滤；也支持「Clash → AdGuard Home → 真实 DNS」的前置链路。
- **概览直接看统计**：插件页内即可看到 DNS 查询、过滤器拦截、恶意/钓鱼、成人内容（家长控制）四项数据，随状态每 10 秒刷新，不必打开 AdGuard Home 控制台
- **可选成人内容拦截**：基础设置里一个开关，自动追加/移除 HaGeZi NSFW 规则，关闭即还原，不需要手动编辑过滤列表
- **规则下载走代理**：自动检测 OpenClash 的 HTTP 代理并写入 AdGuard Home 的 `http_proxy`，避免国内直连 GitHub 更新失败
- **参数自动配置**：保存接管方式时自动关闭缓存与 DNSSEC、改用并行上游，并按模式写入上游与 PTR，不需要逐项手动设置
- **安全可控**：默认密码 `admin123`，可在插件内重置；停止服务或卸载时自动恢复 DNSMasq 设置。
- **配置可维护**：内置 YAML 模板（11 个过滤规则 + 1 个白名单，日志/统计保留 30 天）；高级配置保存前自动 `--check-config` 并保留备份。

---

## 兼容性

| 项目 | 说明 |
|---|---|
| 固件 | OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS，以及基于新版 LuCI 的衍生固件 |
| 25.12 及 apk 系统 | iStoreOS 25.12、OpenWrt 25.12 使用 `apk` 包管理，不能安装 `.ipk`，请用 [脚本安装](#脚本安装2512--apk-系统推荐) |
| 旧固件 | OpenWrt 22.03 及更早的原生 Lua LuCI 使用 `legacy` 版本（不依赖 `luci-compat`） |
| 架构 | x86_64 / 386、ARM64、ARM v5/v6/v7/v8、MIPS / MIPSel / MIPS64 / MIPS64el、RISC-V 64、PPC64LE（暂不支持 LoongArch） |
| 实测环境 | Kwrt aarch64、iStoreOS 24.10 / 25.12 x86_64；内核 AdGuard Home v0.107.80 |

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
3. 等待依赖安装完成，在 **服务** 菜单下打开 **AdGuard Home 助手**。

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

### 脚本安装（25.12 / apk 系统，推荐）

OpenWrt / iStoreOS **25.12 起默认使用 `apk` 包管理**，`.ipk` 无法安装。这类系统直接用 `install.sh`，脚本会自动下载源码、补齐依赖、安装文件并清理 LuCI 缓存，**不需要打安装包**。

```sh
# curl（推荐）
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh

# 只有 wget 时
wget -qO- https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
```

国内网络如果访问 raw.githubusercontent.com 失败，脚本本身也走反代：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -m https://gh-proxy.org
```

脚本会依次尝试 `gh-proxy.org`、`ghfast.top`、`gh-proxy.com` 和 GitHub 直连，哪一个能用就用哪一个；`curl` 与 `wget` 都支持。

常用参数：

| 参数 | 作用 |
|---|---|
| `-v 1.1.8` | 指定版本；`-v latest` 取最新 Release |
| `-m https://gh-proxy.org` | 指定反代，可重复 |
| `--no-deps` | 跳过依赖检查（依赖已装好时更快） |
| `--uninstall` | 卸载插件，恢复 DNSMasq 原始设置，保留配置与内核 |
| `--purge` | 卸载并删除 `/etc/config/adguardhome_lite`、内核与统计数据 |

示例：

```sh
# 卸载（保留配置）
sh install.sh --uninstall

# 安装指定版本并指定反代
sh install.sh -v 1.1.8 -m https://gh-proxy.org
```

> 脚本安装不会在 `apk` 的已安装列表里留下记录，升级/卸载都请继续用 `install.sh`；`/etc/config/adguardhome_lite` 与内核在重复安装时都会保留。

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
- 过滤规则：11 个 + 1 个白名单
- 查询日志与统计：保留 30 天（查询日志只存内存，不写闪存）
- 缓存 / DNSSEC / fallback：默认全部关闭，避免 fake-IP 缓存污染与查询绕过

---

## DNS 接管方式

| 方式 | 完整链路 | 适用场景 |
|---|---|---|
| 接管 53 端口（默认） | 客户端 → 53 AdGuard Home → 1745 DNSMasq → 7874 Clash DNS / 上游 DNS | 想逐设备统计；装了 OpenClash、开着 DNS 劫持/转发也能用（插件自动收回 53） |
| DNSMasq 上游 | 客户端 → 53 DNSMasq → 5333 AdGuard Home → 自动上游 | 不想让 AdGuard Home 占用 53，且无程序抢 53 |
| **OpenClash 前置** | 客户端 → OpenClash 劫持 → 7874 Clash DNS → 5335 AdGuard Home → 真实 DNS | 不想让 AdGuard Home 占 53、不需要逐设备统计；劫持直接指向 7874 时的备选 |
| 仅面板模式 | 不接管 DNS，仅提供管理面板 | 先体验面板或手动接管 |

> 「OpenClash 串联」已下线：OpenClash 写入 DNSMasq 的默认上游（`server=127.0.0.1#7874`）排在 `conf-dir` 之前，`strict-order` 下查询会被 Clash 抢先应答，AdGuard Home 实际收不到查询。旧配置在保存或启动时会自动迁移为「接管 53 端口」。

### 推荐架构怎么选

| 目标 | 推荐方式 |
|---|---|
| 逐设备统计、所有域名先过滤，同时保留 fake-IP 与分流 | 「接管 53」+ OpenClash DNS 劫持/转发（插件会自动把查询收回 53） |
| 不使用 OpenClash | 「接管 53」 |
| 不想让 AdGuard Home 占 53，也不在乎逐设备统计 | 「OpenClash 前置」（Clash → AdGuard Home → 真实 DNS） |

不要同时让一方的上游指向另一方：前置模式的上游必须是真实 DNS，否则会形成查询环。「接管 53」可以和 OpenClash 的 DNS 劫持/转发一起用：插件会写入独立的 `agh_dns_redirect` 链（`priority -101`），在 OpenClash 规则之前把局域网设备的 53 查询（IPv4 + IPv6）收回路由器 53 端口，所以劫持目标写 `:53`、`:1745` 或 `:7874` 都不会跳过 AdGuard Home；写入后会实际校验规则是否存在，缺失时自动重载防火墙。

### 接管 53 + OpenClash（推荐组合）

OpenClash 开着「DNS 劫持」和「DNS 转发」时，这两件事分别是：

- **DNS 劫持**：把设备的 DNS 请求（包括设备自己设的 `8.8.8.8`）收回路由器，部分固件写 `redirect to :53`，也有写 `:1745`/`:7874` 的；插件的 `agh_dns_redirect` 链会先一步收回 53，所以三种写法都不影响过滤；
- **DNS 转发**：把 DNSMasq 的上游改成 `127.0.0.1#7874`，交给 Clash DNS 解析。

所以把 53 交给 AdGuard Home 后，完整链路是：

```text
客户端 → OpenClash 劫持收回 53 → 53 AdGuard Home（过滤、记录真实设备 IP）
      → 1745 DNSMasq → 7874 Clash DNS（fake-IP、分流）→ 真实 DNS
```

过滤、逐设备统计、fake-IP 与分流同时保留。

检查是否生效：

```sh
nft list chain inet fw4 agh_dns_redirect
nft list chain inet fw4 dstnat | grep 'OpenClash DNS Hijack'
```

- 有 `agh_dns_redirect` 链（`priority -101`）：正常。它在 OpenClash 的劫持规则之前生效，会把局域网设备的 53 查询统一收回路由器 53 端口，交给 AdGuard Home；
- OpenClash 自己的劫持规则写 `redirect to :1745` 或 `:7874` 都没关系，前面的自定义链已经先把查询接住了；
- 没有 `agh_dns_redirect` 且 OpenClash 劫持直接指向 `:7874`：查询会跳过 AdGuard Home，请重新选择一次「接管 53 端口」模式。

注意：这套组合里 Clash 必须保持运行（DNSMasq 上游指向 7874），Clash 停止时会解析失败。

### OpenClash 前置说明

部分 OpenClash 配置会把 53 查询直接劫持到自己的 `7874`（「接管 53」已由 `agh_dns_redirect` 收回，不受影响）。如果不想让 AdGuard Home 占 53，可选「OpenClash 前置」作为备选，插件会自动：

- 让 AdGuard Home 监听 `5335`，上游改为真实 DNS（WAN 优先，其次公共 DNS），绝不指向 Clash；
- 开启 OpenClash 自定义 DNS（`enable_custom_dns=1`），新增 `127.0.0.1:5335` 的 nameserver，暂时禁用其它 nameserver，并关闭“追加 WAN DNS”（`append_wan_dns=0`）；
- 原值全部记录在插件 UCI 中，停止/切换模式时恢复，并重启 OpenClash 使配置生效；
- 要求 Clash 内核正在运行且 OpenClash DNS 劫持已开启，否则面板会提示“被绕过”。

该模式下 AdGuard Home 看到的来源都是 Clash（`127.0.0.1`），没有逐设备统计；需要逐设备统计请用「接管 53」。另外 Clash 的 fake-IP 会对所有 A 记录返回 `198.18.x.x`，被拦截的域名在 DNS 层也不会显示成 `0.0.0.0`，实际拦截发生在连接阶段。

### 「OpenClash 串联」为什么下线

该模式曾把 `server=/#/127.0.0.1#5333` 写进 DNSMasq 的 `conf-dir`，让查询先经过 AdGuard Home 再交给 Clash。但在真实环境中：

- OpenClash 自己会把 `server=127.0.0.1#7874` 写进 `dhcp.@dnsmasq[0].server`，生成配置里它排在 `conf-dir` 之前；
- 加了 `strict-order` 后 DNSMasq 按顺序先问 Clash，Clash 有应答就不会再问 AdGuard Home；
- OpenClash 每次启动还会重写这条上游，转发文件随时失效。

结果是「显示已接管、实际没过滤」。因此插件已移除该选项，旧配置会在保存或启动时自动迁移为「接管 53 端口」（该模式既能逐设备统计，也能保留 Clash 的 fake-IP 与分流）。

### 与 OpenClash 的启动顺序

系统开机时按初始化顺序启动：**DNSMasq（START=19）→ AdGuard Home（START=95）→ OpenClash（START=99）**。

| DNS 接管方式 | 顺序要求 | 说明 |
|---|---|---|
| **OpenClash 前置** | 无要求 | AdGuard Home 上游是真实 DNS，不依赖 Clash；OpenClash 启动后接管 53 并转发到 AdGuard Home |
| 接管 53 端口 | 可与 OpenClash 劫持同用 | 插件自建 `agh_dns_redirect` 链先把查询收回 AdGuard Home（53），再经 DNSMasq（1745）交给 Clash（7874），不受 OpenClash 劫持目标影响 |
| DNSMasq 上游 / 仅面板 | 无要求 | 不涉及 53 端口劫持 |

建议：

- 顺序固定为 **DNSMasq（19）→ AdGuard Home（95）→ OpenClash（99）**：OpenClash 的 DNS 上游写着 `127.0.0.1:5335`，必须等 AdGuard Home 先监听；接管 53 时 AdGuard Home 又要依赖先启动的 DNSMasq（1745）。插件已自动注册好 `START=95`，无需手动调整。
- 想逐设备统计：用 **「接管 53」**，OpenClash 的 DNS 劫持/转发可以保持开启；
- 不想让 AdGuard Home 占 53：用 **「OpenClash 前置」**（没有逐设备统计）；
- OpenClash 重启期间 DNS 会短暂中断 1~2 秒，属正常现象。

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
├── install.sh                          # 脚本安装入口（25.12 / apk 系统，无需安装包）
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
- **OpenClash 下不去广告**：先确认「接管 53」模式已生效（`nft list chain inet fw4 agh_dns_redirect` 有 `redirect to :53`）；有这条链时无论 OpenClash 劫持指向哪里都会过滤。若这条链不存在，重新保存一次「接管 53 端口」，或改用「OpenClash 前置」。
- **设备能连路由器但打不开网页**：多为设备没拿到 IPv4 DNS。可在路由器上给 LAN 补一条 DHCP DNS 下发：`uci add_list dhcp.lan.dhcp_option='6,路由器IP'`（把路由器IP换成实际的 LAN 地址），`uci commit dhcp && /etc/init.d/dnsmasq restart`，设备重新连接后生效。
- **重启后内核消失**：内核安装在 `/tmp` 内存位置，重新安装或改为内置存储。

更多内容见 [安装与使用说明](docs/安装与使用说明.md)。

---

## 更新记录

> 更名说明：插件显示名由「AdGuard Home 一键版」改为「AdGuard Home 助手」。包名 `luci-app-adguardhome-lite`、配置 `/etc/config/adguardhome_lite` 与安装方式均未变化，已安装用户可直接覆盖升级。

### v1.1.8（2026-11-12）

- 修复「接管 53 端口」下 DNSMasq 端口未强制为 1745 导致的抢端口/断网风险：写入后回读校验，失败即回滚 DNSMasq 设置并标记未接管
- 修复 «DNSMasq 上游» / «OpenClash 前置» 模式未强制 DNSMasq 回到 53 的问题，模式判定改为校验实际端口
- 修复「仅面板」模式上游写死 `127.0.0.1` 的问题，改为跟随 DNSMasq 实际端口
- IPv6 收回规则由仅 LAN 改为排除 WAN 接口，覆盖访客/IoT 网络；规则不完整或内容变化时强制重载防火墙
- 修正使用引导中「装了 OpenClash 必须改前置模式」的误导文案

### v1.1.7（2026-11-12）

- 调整运行日志与高级配置框高度，修复独立页面背景无法随内容收缩的问题

### v1.1.6（2026-11-10）

- 新增 `install.sh` 脚本安装：支持 curl / wget，自动选择 GitHub 反代、检查依赖、安装文件并清理 LuCI 缓存；带 `--uninstall` / `--purge`
- 适配 OpenWrt / iStoreOS 25.12（`apk` 包管理）：这类系统无法安装 `.ipk`，直接用 `install.sh` 即可
- 修复配置模板把 `ratelimit_whitelist` 写成 CIDR（`127.0.0.0/8`、`::1/128`）导致 `--check-config` 失败、服务无法启动的问题；改为单个 IP，旧配置在应用时自动修正
- 文档补充 25.12 兼容说明与脚本安装、卸载命令

### v1.1.5（2026-11-10）

- 概览新增「过滤统计」卡片：DNS 查询、已拦截、恶意/钓鱼、成人内容四项数据直接读取 AdGuard Home 统计接口，随状态每 10 秒刷新，不需要打开控制台
- 一键化：保存接管方式时自动关闭缓存与 DNSSEC、改用并行上游，省去进面板逐项设置
- 模板默认不开启安全浏览：它依赖 AdGuard 在线服务，国内网络不可达时会拖慢甚至阻塞解析；需要时可在面板手动开启
- 基础设置新增「成人内容拦截」开关：开启自动追加 HaGeZi NSFW 规则，关闭自动移除，命中计入「已拦截」
- 自动检测 OpenClash 的 HTTP 代理并写入 AdGuard Home 的 `http_proxy`，修复国内直连 GitHub 导致规则更新失败
- 概览「快捷操作」更名为「服务控制」，只保留启动/停止/重启三个按钮
- 性能优化：统计合并进状态接口（页面由两次请求变一次），内核版本与统计数据加本地缓存，状态接口稳定在约 170ms
- 文档补充开机启动顺序（DNSMasq 19 → AdGuard Home 95 → OpenClash 99）与原因，面板使用引导同步更新

### v1.1.4（2026-11-10）

- 修复「前置」模式被 AGH 限速误伤：模板默认把 `127.0.0.0/8`、`::1/128` 加入 `ratelimit_whitelist`；旧配置在应用前置模式时若白名单为空会自动补上
- `agh_dns_redirect` 增加 IPv6 收回规则（限定 LAN 接口），写入后实际校验规则是否生效；改用防火墙 restart 重建规则（iStoreOS 上 `fw4 reload` 不会重建），并清理残留空链
- 「OpenClash 串联」下线：旧配置自动迁移为「接管 53 端口」，界面与文档同步移除该选项
- 面板提示改为「劫持已开启但收回规则未生效」时才告警，不再误报「接管 53 会被绕过」

### v1.1.3（2026-11-10）

- 插件显示名由「AdGuard Home 一键版」改为「AdGuard Home 助手」：LuCI 菜单、页面标题、安装包描述与文档同步更新；包名 `luci-app-adguardhome-lite` 与配置目录不变，可直接覆盖升级

### v1.1.2（2026-11-09）

- 「接管 53」新增独立 nft 重定向链 `agh_dns_redirect`（`priority -101`）：即使 OpenClash 的 DNS 劫持指向 `1745`/`7874`，查询也会先进入 AdGuard Home，过滤与逐设备统计不再被绕过；停止服务或切换模式时自动移除
- 文档补充该链的检查方法，并新增「设备没拿到 IPv4 DNS」的排查步骤

### v1.1.1（2026-11-09）

- 修复从「OpenClash 前置」切换到其它接管方式时未还原 Clash 上游、可能形成查询环的问题
- 文档补充「接管 53 + OpenClash DNS 劫持/转发」完整链路：过滤、逐设备统计与 fake-IP/分流可同时保留，并给出劫持目标检查命令
- 更正内置过滤规则数量为 11 个

### v1.1.0（2026-11-09）

- 修复 DNSMasq 跟随 OpenClash 劫持端口导致的抢端口断网问题，DNSMasq 不再跟随劫持端口（「接管 53」时固定为 1745）
- 新增「OpenClash 前置」模式：Clash 7874 → AdGuard Home 5335 → 真实 DNS，并自动配置 OpenClash 自定义上游
- 串联模式转发规则改写到 DNSMasq 实际 `conf-dir`，兼容 dnsmasq < 2.86
- 默认关闭 DNS 缓存、DNSSEC 与 fallback DNS，上游模式改为并行，避免 fake-IP 缓存污染和查询绕过
- 默认启用限速（20）、浅色主题；查询日志只存内存
- 面板新增完整链路展示与绕过/劫持冲突提示

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
