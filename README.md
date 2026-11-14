# AdGuard Home 助手

OpenWrt / ImmortalWrt / iStoreOS 轻量级 AdGuard Home LuCI 管理助手插件，支持三步安装、低侵入 DNS 接管。

> 插件负责安装、DNS 接管、过滤与统计；更细的高级项仍可在 AdGuard Home 面板调整。

<div align=center>
<img src="https://ozero.top/media/2026/11/6af82bb0625a57.22446996.png" width="600" height="614">
</div>

## 目录

- **了解**：[结构化摘要](#结构化摘要) · [项目初衷](#项目初衷) · [功能特性](#功能特性)
- **安装**：[兼容性](#兼容性) · [安装](#安装) · [三步上手](#三步上手)
- **DNS**：[接管方式](#dns-接管方式)
- **排障与开发**：[常见问题](#常见问题faq) · [项目结构](#项目结构) · [构建](#构建) · [文档](#文档) · [反馈与贡献](#反馈与贡献) · [安全建议](#安全建议) · [许可证](#许可证)

---

## 结构化摘要

**一句话**：把 AdGuard Home 的「装内核、接 DNS、看状态」收进一个 LuCI 页面，三步完成，不需要手改配置。

> 💡 能装 `.ipk` 就用安装包；软件包页面显示 `apk` 或固件为 25.12 及以上，直接用 `install.sh`。

**不适用**：Docker、NAS、普通 Linux 发行版；LoongArch 架构暂不支持。

---

## 项目初衷

第一次用 AdGuard Home，两个坎绕不过去：内核下载总失败，DNS 也不知道怎么接。

这个插件就是来填这两个坑的：

- **不用懂 DNS**：默认接管 53 端口，DNSMasq 自动挪到 1745，停止服务或卸载时原样还原；
- **不用手动找内核**：自动识别架构、自动下载，国内网络和 fake-IP 环境都有对应方案；
- **不用提前配**：内置默认账号、过滤规则、中文界面和日志周期，启用即可用；
- **不挑固件**：新旧 LuCI 都支持，覆盖 OpenWrt、ImmortalWrt、iStoreOS 及衍生固件。

需要更细的控制，仍可以在 AdGuard Home 面板或插件「高级配置」里改。

---

## 功能特性

### 安装与内核

- **三步上手**：安装内核 → 一键启用 → 打开控制台，每步都有状态提示和失败原因。
- **官方内核**：自动识别 CPU 架构，从 AdGuard 官方源下载最新稳定版。
- **下载兜底**：可选 `gh-proxy.org`、`ghproxy.cc`、`ghproxy.com`、`ghfast.top` 反代，失败自动回退官方 CDN 与 GitHub 直连。
- **fake-IP 兼容**：路由器使用 fake-IP DNS 时，自动解析真实 IP，再以 `curl --resolve` 下载。

### DNS 接管

- **四种接管方式**：接管 53、DNSMasq 上游、Clash 前置、仅面板（「Clash 串联」已下线，旧配置自动迁移）。
- **Clash 共存**：推荐「接管 53 + Clash DNS 劫持/转发」。插件自建 `agh_dns_redirect` 链收回设备的 53 查询，Clash 劫持指向 `53`、`1745` 还是 `7874` 都绕不过过滤；也支持「Clash → AdGuard Home → 真实 DNS」的前置链路。
- **缓存与上游**：DNS 缓存默认开启（16MB，可关闭）；首次生成默认关闭 DNSSEC、使用并行上游，之后保存不再覆盖用户在 AGH 面板的修改。
- **上游可编辑**：默认按接管方式自动写入，也可固定自定义列表，支持 DoH/DoT/DoQ 与 `[/域名/]IP` 条件转发；加密预设不会覆盖自定义上游。
- **不覆盖自定义配置**：`http_proxy`、本地 PTR、上游 DNS 只更新插件自己写入的值，用户手改的代理、反向解析和上游保持原样。
- **加密上游（可选）**：仅「Clash 前置」可把上游切到阿里 / DNSPod DoH、Cloudflare DoH 或自定义 DoH/DoT/DoQ；其它模式的上游是本机 DNSMasq，保持不加密。
- **按接口 / 客户端放行**：「接管 53」下可指定不参与接管的网络设备或客户端 IP/CIDR，这些查询直接由 DNSMasq 应答，不进 AdGuard Home。

> ⚠️ 「接管 53」+ 自定义上游会绕过本机 DNSMasq（1745），`.lan` 等本地主机名将无法解析；需要时把 `127.0.0.1:1745` 加到列表末尾。

### 过滤与统计

- **页内看统计**：概览显示 DNS 查询、过滤器拦截、恶意/钓鱼、成人内容四项数据，每 10 秒随状态刷新。
- **查询日志**：运行日志 → 查询日志显示最近 20 条查询与拦截结果，只读。
- **过滤规则管理**：基础设置 → 过滤规则内启用/停用规则、添加订阅（黑名单/白名单）、编辑自定义规则，修改立即生效。
- **安全搜索 / 浏览安全**：一个开关即可启用或关闭。
- **保留周期**：统计与查询日志的保留天数可在「插件配置」内调整。
- **成人内容拦截**：「过滤规则」页一个开关，自动追加/移除 HaGeZi NSFW 订阅，命中计入「已拦截」，立即生效。
- **规则更新走代理**：自动检测 Clash 的 HTTP 代理并写入 `http_proxy`，避免国内直连 GitHub 更新失败。

### 维护与安全

- **版本提示**：页面标题下显示插件版本，有新版本时给出提示，每 24 小时后台检查一次。
- **安全可控**：默认密码 `admin123`，可在插件内重置；停止服务或卸载时自动恢复 DNSMasq 设置。
- **配置可维护**：内置 YAML 模板（11 个过滤规则 + 1 个白名单，日志/统计保留 30 天）；高级配置保存前自动 `--check-config` 并留备份。

---

## 兼容性

| 项目 | 说明 |
|---|---|
| 固件 | OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS，以及基于新版 LuCI 的衍生固件 |
| 25.12 及 apk 系统 | iStoreOS 25.12、OpenWrt 25.12 使用 `apk`，不能装 `.ipk`，请用 [脚本安装](#脚本安装2512--apk-系统) |
| 旧固件 | OpenWrt 22.03 及更早的原生 Lua LuCI 使用 `legacy` 版本（不依赖 `luci-compat`） |
| 架构 | x86_64 / 386、ARM64、ARM v5/v6/v7/v8、MIPS / MIPSel / MIPS64 / MIPS64el、RISC-V 64、PPC64LE（暂不支持 LoongArch） |
| 实测环境 | Kwrt aarch64、iStoreOS 24.10 / 25.12 x86_64；内核 AdGuard Home v0.107.80 |

> ⚠️ 与旧版 `luci-app-adguardhome` 冲突，安装前先卸载旧插件及中文语言包。

---

## 安装

### 方式一：安装包（ipk / run）

到 [Releases](../../releases) 下载。**同一设备只装其中一个**：

| 安装包 | 适用固件 |
|---|---|
| `luci-app-adguardhome-lite_<版本>_all.ipk` | OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS 等新版 LuCI |
| `luci-app-adguardhome-lite_<版本>-legacy_all.ipk` | OpenWrt 22.03 及更早的原生 Lua LuCI |
| `luci-app-adguardhome-lite_<版本>.run` | 离线自解压包，内含上述两个 ipk，自动选择可用版本 |

**LuCI 上传（推荐）**

1. 打开 `http://路由器IP` → **系统 → 软件包**；
2. 找到 **上传安装包**，选择对应 `.ipk`；
3. 等依赖装完，在 **服务** 菜单打开 **AdGuard Home 助手**。

**命令行**

```sh
opkg install /tmp/luci-app-adguardhome-lite_*.ipk
```

**离线 .run**

```sh
sh /tmp/luci-app-adguardhome-lite_<版本>.run
```

脚本会自解压到临时目录，优先装新版 LuCI 包，失败自动回退 legacy 包，完成后清理临时文件。

Release 页同时提供 `SHA256SUMS`，可校验文件完整性。

---

### 方式二：脚本安装（25.12 / apk 系统）

OpenWrt / iStoreOS **25.12 起默认使用 `apk`**，`.ipk` 装不上。这类系统直接用 `install.sh`：脚本自动下载源码、补齐依赖、安装文件并清理 LuCI 缓存，不需要打安装包。

```sh
# curl（推荐）
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh

# 只有 wget 时
wget -qO- https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
```

国内访问 raw 失败时，脚本本身也走反代：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -m https://gh-proxy.org
```

脚本会依次尝试 `gh-proxy.org`、`ghfast.top`、`gh-proxy.com` 和 GitHub 直连，`curl` 与 `wget` 都支持。

**强制更新**（不升版也能覆盖同版本文件，直接装 main 分支最新代码）：

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f

# 国内网络
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f -m https://gh-proxy.org
```

已用 ipk 安装的设备可以强制重装：

```sh
opkg install --force-reinstall /tmp/luci-app-adguardhome-lite_1.3.0-1_all.ipk
```

**常用参数**

| 参数 | 作用 |
|---|---|
| `-v 1.3.0` | 指定版本；`-v latest` 取最新 Release |
| `-f, --force` | 强制更新：忽略版本标签，用 main 分支最新代码覆盖安装 |
| `-m https://gh-proxy.org` | 指定反代，可重复 |
| `--no-deps` | 跳过依赖检查（依赖已装好时更快） |
| `--uninstall` | 卸载插件，恢复 DNSMasq 原始设置，保留配置与内核 |
| `--purge` | 卸载并删除 `/etc/config/adguardhome_lite`、内核与统计数据 |

```sh
# 卸载（保留配置）
sh install.sh --uninstall

# 强制更新到 main 分支最新代码（不升版）
sh install.sh -f

# 安装指定版本并指定反代
sh install.sh -v 1.3.0 -m https://gh-proxy.org
```

> 💡 脚本安装不会在 `apk` 的已安装列表里留记录，升级/卸载都请继续用 `install.sh`；`/etc/config/adguardhome_lite` 与内核在重复安装时都会保留。

---

## 三步上手

1. **安装内核**：概览页点「安装/更新内核」，等进度完成；
2. **一键启用**：点「一键启用」，插件从模板生成配置并接管 DNS；
3. **打开控制台**：点「打开控制台」，用 `admin` / `admin123` 登录。

默认配置：

- 面板地址：`0.0.0.0:13800`
- 账号：`admin`，密码 `admin123`（首次登录后建议修改）
- DNS 接管：默认「接管 53 端口」，DNSMasq 自动移到 `1745`
- 上游 DNS：`127.0.0.1:1745`
- 过滤规则：11 个 + 1 个白名单
- 查询日志与统计：保留 30 天（查询日志只存内存，不写闪存）
- DNS 缓存：默认开启，16MB，最小 TTL 0（不覆盖），乐观缓存关闭；可在「基础设置 → DNS 解析」修改
- 加密上游：默认关闭；仅在「Clash 前置」模式可开启，可选阿里 / DNSPod / Cloudflare DoH 或自定义
- DNSSEC / fallback：默认关闭，避免 fake-IP 污染与查询绕过

---

## DNS 接管方式

| 方式 | 完整链路 | 适用场景 |
|---|---|---|
| **接管 53 端口**（默认） | 客户端 → 53 AdGuard Home → 1745 DNSMasq → 7874 Clash DNS / 上游 DNS | 想逐设备统计；装了 Clash、开着 DNS 劫持/转发也能用（插件自动收回 53） |
| DNSMasq 上游 | 客户端 → 53 DNSMasq → 5333 AdGuard Home → 自动上游 | 不想让 AdGuard Home 占 53，且没有程序抢 53 |
| Clash 前置 | 客户端 → Clash 劫持 → 7874 Clash DNS → 5335 AdGuard Home → 真实 DNS | 不想让 AdGuard Home 占 53、不需要逐设备统计 |
| 仅面板模式 | 不接管 DNS，仅提供管理面板 | 先体验面板或手动接管 |

### 怎么选

| 目标 | 推荐 |
|---|---|
| 逐设备统计、所有域名先过滤，同时保留 fake-IP 与分流 | 「接管 53」+ Clash DNS 劫持/转发 |
| 不使用 Clash | 「接管 53」 |
| 不想让 AdGuard Home 占 53，也不在乎逐设备统计 | 「Clash 前置」 |

不要同时让一方的上游指向另一方：前置模式的上游必须是真实 DNS，否则会形成查询环。

「接管 53」可以和 Clash 的 DNS 劫持/转发一起用：插件会写入独立的 `agh_dns_redirect` 链（`priority -101`），在 Clash 规则之前把局域网设备的 53 查询（IPv4 + IPv6）收回路由器 53 端口，所以劫持目标写 `:53`、`:1745` 或 `:7874` 都不会跳过 AdGuard Home；写入后会实际校验规则是否存在，缺失时自动重载防火墙。

### 接管 53 + Clash（推荐组合）

Clash 开着「DNS 劫持」和「DNS 转发」时：

- **DNS 劫持**：把设备的 DNS 请求（包括设备自设的 `8.8.8.8`）收回路由器。部分固件写 `redirect to :53`，也有写 `:1745` / `:7874` 的；插件的 `agh_dns_redirect` 链先一步收回 53，三种写法都不影响过滤。
- **DNS 转发**：把 DNSMasq 的上游改成 `127.0.0.1#7874`，交给 Clash DNS 解析。

完整链路：

```text
客户端 → Clash 劫持收回 53 → 53 AdGuard Home（过滤、记录真实设备 IP）
      → 1745 DNSMasq → 7874 Clash DNS（fake-IP、分流）→ 真实 DNS
```

过滤、逐设备统计、fake-IP 与分流同时保留。Clash 必须保持运行（DNSMasq 上游指向 7874），停止时会解析失败。

检查是否生效：

```sh
nft list chain inet fw4 agh_dns_redirect
nft list chain inet fw4 dstnat | grep 'Clash DNS Hijack'
```

- 有 `agh_dns_redirect` 链（`priority -101`）：正常，它在 Clash 的劫持规则之前生效；
- Clash 自己的劫持写成 `:1745` 或 `:7874` 都没关系，前面的自定义链已经先接住了；
- 没有 `agh_dns_redirect` 且劫持直接指向 `:7874`：查询会跳过 AdGuard Home，重新选一次「接管 53 端口」。

### 排除接口与客户端（仅「接管 53」）

「接管 53」会收回所有私网来源的 53 查询。如果访客网络、IoT 网段或某台自建 DNS 的设备不想被过滤，在「基础设置 → 插件配置」里填：

- **不参与接管的接口**：网络设备名，空格分隔，例如 `br-guest wg0`；
- **不参与接管的客户端 IP / CIDR**：IPv4、IPv6 均可，例如 `192.168.1.50 192.168.2.0/24 fd00::5`。

命中的查询由插件生成的 nft 规则直接交给系统 DNSMasq（1745）应答，不进入 AdGuard Home，也不计入统计；指向 `8.8.8.8` 这类外部 DNS 的查询直接放行。留空即维持「全部接管」。

AdGuard Home 官方配置没有「按接口放行」的开关（`dns.allowed_clients` 是「只接受这些客户端」，`disallowed_clients` 是「直接丢弃请求」），所以这里在防火墙层实现，不改 `AdGuardHome.yaml`，也不影响 `--check-config`。

排查：`nft list chain inet fw4 agh_dns_redirect` 能看到 `AGH bypass ... to-dnsmasq` 和 `... direct` 成对规则就说明已生效。

### 自定义域名转发（`server=/域名/IP`）

DNSMasq 里已有的 `server=/corp.example/10.0.0.1` 这类规则会被保留，不同接管方式影响不同：

- **接管 53**：查询先到 AdGuard Home，过滤和统计照常生效；自定义规则只改变 AGH 上游的解析路径，不会绕过过滤。
- **DNSMasq 上游**：DNSMasq 优先匹配域名规则，这些域名直接发给指定服务器，不经过 AdGuard Home，不过滤、也不计入统计。

需要这些域名也走过滤时，把规则改到 AdGuard Home 的「上游 DNS」，用 `[/corp.example/]10.0.0.1` 的写法配置。

### Clash 前置说明

部分 Clash 配置会把 53 查询直接劫持到 `7874`（「接管 53」已由 `agh_dns_redirect` 收回，不受影响）。如果不想让 AdGuard Home 占 53，可选「Clash 前置」，插件会自动：

- 让 AdGuard Home 监听 `5335`，上游改为真实 DNS（WAN 优先，其次公共 DNS），绝不指向 Clash；
- 开启 Clash 自定义 DNS（`enable_custom_dns=1`），新增 `127.0.0.1:5335` 的 nameserver，暂时禁用其它 nameserver，并关闭「追加 WAN DNS」（`append_wan_dns=0`）；
- 原值全部记在插件 UCI 里，停止/切换模式时恢复，并重启 Clash 使配置生效；
- 要求 Clash 内核正在运行且 DNS 劫持已开启，否则面板会提示「被绕过」。

该模式下来源都是 Clash（`127.0.0.1`），没有逐设备统计；需要逐设备统计请用「接管 53」。另外 Clash 的 fake-IP 会对所有 A 记录返回 `198.18.x.x`，被拦截的域名在 DNS 层不会显示成 `0.0.0.0`，实际拦截发生在连接阶段。

<details>
<summary>「Clash 串联」为什么下线</summary>

该模式曾把 `server=/#/127.0.0.1#5333` 写进 DNSMasq 的 `conf-dir`，让查询先过 AdGuard Home 再交给 Clash。但实际环境里：

- Clash 自己会把 `server=127.0.0.1#7874` 写进 `dhcp.@dnsmasq[0].server`，生成的配置里它排在 `conf-dir` 之前；
- 加了 `strict-order` 后 DNSMasq 按顺序先问 Clash，Clash 有应答就不会再问 AdGuard Home；
- Clash 每次启动还会重写这条上游，转发文件随时失效。

结果就是「显示已接管、实际没过滤」。所以插件移除了这个选项，旧配置在保存或启动时自动迁移为「接管 53 端口」——它既能逐设备统计，也能保留 Clash 的 fake-IP 与分流。

</details>

### 与 Clash 的启动顺序

开机顺序固定为 **DNSMasq（19）→ AdGuard Home（95）→ Clash（99）**：前置模式下 Clash 的上游写着 `127.0.0.1:5335`，必须等 AdGuard Home 先监听；接管 53 时 AdGuard Home 又依赖先启动的 DNSMasq（1745）。插件已注册 `START=95`，无需手动调整。

| DNS 接管方式 | 顺序要求 | 说明 |
|---|---|---|
| Clash 前置 | 无要求 | AdGuard Home 上游是真实 DNS，不依赖 Clash |
| 接管 53 端口 | 可与 Clash 劫持同用 | 自定义链先收回 53，再经 DNSMasq（1745）交给 Clash（7874） |
| DNSMasq 上游 / 仅面板 | 无要求 | 不涉及 53 端口劫持 |

- 想逐设备统计：用「接管 53」，Clash 的 DNS 劫持/转发保持开启即可；
- 不想让 AdGuard Home 占 53：用「Clash 前置」（没有逐设备统计）；
- Clash 重启期间 DNS 会短暂中断 1~2 秒，属正常现象。

---

## 常见问题（FAQ）

### Q1：luci-app-adguardhome-lite 和传统 AdGuard Home 插件有什么区别？

传统 `luci-app-adguardhome` 更偏向把 AdGuard Home 的配置项全部搬进 LuCI，功能多但配置也重；本插件只做三件事：**装内核、接 DNS、看状态**。

- 默认三步完成，不要求先手动安装 AdGuard Home；
- 自动识别架构下载官方内核，内置反代与 fake-IP 兜底；
- 接管前记录 DNSMasq 原值，停止或卸载时自动还原；
- 过滤规则、查询日志等常用项也能在插件内完成，高级项仍由 AdGuard Home 面板管理；
- 与旧插件冲突，安装前需卸载旧插件及中文语言包。

### Q2：OpenWrt 25.12 升级 apk 系统后怎么安装？

25.12 起默认使用 `apk`，不能安装 `.ipk`，直接用 `install.sh`（详见[脚本安装](#方式二脚本安装2512--apk-系统)）：

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
```

脚本会补齐依赖、安装文件并清理 LuCI 缓存。常用参数：`-v` 指定版本、`-f` 强制更新、`--uninstall` 卸载保留配置、`--purge` 卸载并删除配置与内核。脚本安装不会在 `apk` 已安装列表里留记录，后续升级和卸载继续使用 `install.sh`。

### Q3：需要先手动安装 AdGuard Home 吗？

不需要。插件自带内核安装流程，首次使用点「安装/更新内核」即可；已存在 `/etc/AdGuardHome.yaml` 时会直接复用。

### Q4：内核下载失败怎么办？

检查网络和系统时间；国内网络在「基础设置 → 插件配置」启用 GitHub 反代；fake-IP 环境插件会自动解析真实 IP 并用 `curl --resolve` 下载；空间不足时把内核位置改到内置存储，或清理闪存。

### Q5：启用后不能上网怎么办？

到概览页点「停止并关闭自启」，插件会恢复接管前的 DNSMasq 设置。仍异常可执行：

```sh
/etc/init.d/adguardhome_lite stop
/etc/init.d/dnsmasq restart
```

然后查看「运行日志」，确认 53 / 1745 / 5333 / 5335 端口是否被占用。

### Q6：同时运行 Clash 时去广告不生效？

先确认收回规则存在：

```sh
nft list chain inet fw4 agh_dns_redirect
```

有 `redirect to :53` 时，Clash 劫持指向 `:53`、`:1745` 或 `:7874` 都不影响过滤。若链不存在，重新保存一次「接管 53 端口」，或改用「Clash 前置」。

### Q7：停止服务后面板打不开？

正常现象，面板随服务停止。重新点「启动服务」即可；如果服务已运行仍打不开，检查 UCI 端口与 YAML `address` 是否一致，并等待 5–10 秒。

### Q8：设备能连路由器但打不开网页？

常见原因是设备没拿到 IPv4 DNS。给 LAN 补一条 DHCP DNS 下发：

```sh
uci add_list dhcp.lan.dhcp_option='6,路由器IP'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

把 `路由器IP` 换成实际 LAN 地址，设备断开重连后生效。

### Q9：重启后内核消失？

内核装在 `/tmp` 内存位置时会这样。重新点「安装/更新内核」，或在「基础设置 → 插件配置」里把安装位置改到内置存储。

### Q10：和旧版插件冲突吗？

会。安装包内置 `Conflicts` 声明，检测到 `luci-app-adguardhome` 时会拒绝安装。请先卸载旧插件和 `luci-i18n-adguardhome-zh-cn`，确认旧服务已停止后再安装。

### Q11：卸载后 DNS 会恢复吗？

会。停止或卸载时只写回接管前记录的 DNSMasq 端口、`noresolv`、`resolvfile` 和 `server`，不会写入公共 DNS。`install.sh --uninstall` 卸载并恢复 DNS、保留配置与内核；`--purge` 才会删除配置、内核与统计。

### Q12：DNS 缓存默认开启吗？怎么关闭？

默认开启：16MB、最小 TTL 0（不覆盖上游）、最大 TTL 不限制、乐观缓存关闭。进入「基础设置 → DNS 解析」关闭开关并保存即可；升级用户会保留原有 YAML 中的缓存状态。

### Q13：加密 DNS 什么时候需要开？

只在 AdGuard Home 直接查询真实上游时有意义，也就是「Clash 前置」模式。默认「接管 53」的上游是本机 DNSMasq（`127.0.0.1:1745`），这一段是 loopback，加密不会生效；出公网的查询由 Clash 或上游 DNS 负责。需要防运营商 DNS 劫持时，在「基础设置 → DNS 解析」的加密上游里选择阿里或 DNSPod DoH 即可；Cloudflare 等境外 DoH 通常需要配合代理，否则可能超时。加密只保护「路由器 → 上游」这一段，不影响过滤效果。

更多排查与验证步骤见 [安装与使用说明](docs/安装与使用说明.md)。

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

### 直接生成 ipk（无需 OpenWrt SDK）

需要 Python 3：

```sh
python tools/build_ipk.py
```

会生成 modern（新版 LuCI）与 legacy（旧版 LuCI）两个安装包，以及 `SHA256SUMS`。

生成离线自解压包：

```sh
python tools/build_run.py
```

会在 ipk 基础上生成 `.run`，并把校验值追加到 `SHA256SUMS`。

### 使用 OpenWrt SDK

把 `src/luci-app-adguardhome-lite/` 放进 SDK 的 `package/` 或 feed 目录：

```sh
make menuconfig   # LuCI → Applications → luci-app-adguardhome-lite
make package/luci-app-adguardhome-lite/compile V=s
```

---

## 文档

- [安装与使用说明](docs/安装与使用说明.md)：安装验证清单、DNS 接管详解、Clash 排查、卸载回滚与常见问题。
- 插件内「使用引导」标签包含三步说明与常见问题入口。

---

> **搭配浏览器扩展效果更佳**
>
> 路由器端只能按域名拦截，页面内的广告位、同域名广告和追踪脚本需要浏览器端过滤。建议再装 AdGuard 浏览器扩展或 uBlock Origin，两者叠加后，adblock-tester.com 这类测试通常能到 95% 以上。
>
> - 官方下载页（自动识别浏览器）：<https://adguard.com/zh_cn/adguard-browser-extension/overview.html>
> - Chrome 应用商店：<https://chromewebstore.google.com/detail/adguard-adblocker/bgnkhhnnamicmpeenaelnjfhikgbkllg>
> - Edge / Firefox 在各自扩展商店搜「AdGuard AdBlocker」
>
> 只装扩展，手机、电视过滤不到；只装路由器端，页面里仍会剩一些广告。推荐两边一起用。

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
