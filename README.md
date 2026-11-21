# AdGuard Home 管理中心

OpenWrt / ImmortalWrt / iStoreOS 的 AdGuard Home LuCI 管理中心：安装、DNS 接管、过滤与看护一体化，支持三步上手、低侵入 DNS 接管。

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

**一句话**：把 AdGuard Home 的「安装、DNS 接管、过滤、看护、统计」收进一个 LuCI 页面，三步完成，不需要手改配置。

> 💡 能装 `.ipk` 就用安装包；软件包页面显示 `apk` 或固件为 25.12 及以上，直接用 `install.sh`。

**不适用**：Docker、NAS、普通 Linux 发行版；LoongArch 架构暂不支持。

---

## 项目初衷

第一次用 AdGuard Home，两道坎绕不过去：内核下载总失败，DNS 不知道怎么接。这个插件就来填这两个坑：

- **不用懂 DNS**：默认接管 53，DNSMasq 自动移到 1745，停止或卸载原样还原；
- **不用找内核**：自动识别架构下载，国内网络与 fake-IP 环境都有方案；
- **不用提前配**：内置账号、规则、中文界面与日志周期，启用即用；
- **不挑固件**：新旧 LuCI 均支持，覆盖 OpenWrt、ImmortalWrt、iStoreOS 及衍生固件。

需要更细的控制，仍可在 AdGuard Home 面板或「高级配置」里改。

---

## 功能特性

### 安装与内核

- **三步上手**：安装内核 → 一键启用 → 打开 AGH 面板，每步给出状态与失败原因。
- **官方内核**：自动识别架构下载官方版本，可选预发布版；升级前备份配置，预发布通道失败自动回退正式版。
- **下载兜底**：进度实时可见，支持多个 GitHub 反代，失败自动回退官方 CDN 与直连；fake-IP 环境自动解析真实 IP。

### DNS 接入

- **五种方式**：接管 53、PassWall 前置、DNSMasq 上游、Clash 前置、仅面板；「Clash 串联」已下线，旧配置自动迁移。
- **Clash 共存**：推荐「接管 53 + Clash 劫持/转发」，自建 `agh_dns_redirect` 链先收回设备 53 查询，Clash 劫持指向哪个端口都绕不过过滤。
- **PassWall 共存**：无需关闭其 DNS 劫持，插件接管规则优先级更高，上游自动指向 PassWall 动态 DNS 端口，过滤与分流同时保留。
- **上游可控**：默认按模式自动写入，也可自定义 DoH/DoT/DoQ 与 `[/域名/]IP` 条件转发；只改插件自己写入的值，手改的代理、PTR、上游保持原样。
- **按接口 / 客户端放行**：「接管 53」下可排除指定接口或 IP/CIDR，这些查询由 DNSMasq 直接应答，不进 AdGuard Home。

> ⚠️ 「接管 53」+ 自定义上游会绕过本机 DNSMasq（1745），`.lan` 等本地主机名将无法解析；需要时把 `127.0.0.1:1745` 加到列表末尾。

### 过滤与看护

- **规则管理**：启用/停用规则、增删订阅、编辑自定义规则，修改立即生效。
- **预置档位**：按内存 512MB / 1GB / 2GB+ 一键切换 3 / 4 / 5 个分类订阅，由[自建规则仓库](https://github.com/Ozero-top/AdguardHome-Rrules)定期抓取去重生成，三档共用白名单。
- **广告根域兜底**：`$third-party` 规则降级为纯域规则，并对广告根域整域兜底，补上动态子域漏拦。
- **一键开关**：安全搜索、浏览安全、家长控制、成人内容拦截（HaGeZi NSFW）、DoH 服务器拦截，各自独立开关。
- **家长控制保护**：开启前先试拨 AdGuard 服务端，连不上直接拒绝；运行中连不上由看护进程自动关闭，避免全屋断网。
- **订阅维护**：支持手动立即更新全部订阅；自动检测 Clash 代理，内置订阅走 jsDelivr CDN；统计与日志保留天数可调。
- **异常回退**：看护进程由 procd 托管，内核异常退出自动恢复 DNSMasq。

### 可观测与维护

- **统计与日志**：概览显示查询、拦截、恶意/钓鱼、成人内容四项数据；查询日志显示最近 20 条记录，只读；运行日志支持按级别筛选并带原因码。
- **版本提示**：页面显示插件版本，插件与内核更新均会提示，后台定期检查。
- **配置与更新安全**：内核更新校验失败保留原内核，配置保存前自动检查并留备份。
- **旧版清理**：自动检测旧版插件文件与旧内核，一键清理并先备份。
- **安全复原**：默认密码可重置；停止服务或卸载时自动恢复 DNSMasq 设置。
- **一键自检**：只读检查内核、进程、管理端口与本机 53 链路，不修改任何配置。
- **在线更新**：发现新版本后可页面内更新，可选国内加速 / GitHub 直连，以及通用模式 / 安装包两种方式。
- **主题**：支持暗色 / 浅色切换。

---

## 兼容性

| 项目 | 说明 |
|---|---|
| 固件 | OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS，以及基于新版 LuCI 的衍生固件 |
| 25.12 及 apk 系统 | iStoreOS 25.12、OpenWrt 25.12 使用 `apk`，不能装 `.ipk`，请用 [脚本安装](#脚本安装2512--apk-系统) |
| 旧固件 | OpenWrt 22.03 及更早的原生 Lua LuCI 使用 `legacy` 版本（不依赖 `luci-compat`） |
| 架构 | x86_64 / 386、ARM64、ARM v5/v6/v7/v8、MIPS / MIPSel / MIPS64 / MIPS64el、RISC-V 64、PPC64LE（暂不支持 LoongArch） |
| 实测环境 | Kwrt aarch64、iStoreOS 24.10 / 25.12 x86_64；内核实测 AdGuard Home v0.107.80 与 v1.0.0-b.2 |

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
3. 等依赖装完，在 **服务** 菜单打开 **AdGuard Home 管理中心**。

**命令行**

```sh
opkg install /tmp/luci-app-adguardhome-lite_*.ipk
```

**离线 .run**

```sh
sh /tmp/luci-app-adguardhome-lite_<版本>.run
```

脚本自解压到临时目录，优先装新版 LuCI 包，失败回退 legacy，完成后清理。Release 页另附 `SHA256SUMS` 用于校验。

---

### 方式二：脚本安装（25.12 / apk 系统）

OpenWrt / iStoreOS **25.12 起改用 `apk`**，`.ipk` 装不上，请使用 `install.sh`（OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS 也可使用）：脚本自动下载源码、补齐依赖、安装文件并清理 LuCI 缓存，不需要打安装包。

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

脚本依次尝试 `gh-proxy.org`、`ghfast.top`、`gh-proxy.com` 与 GitHub 直连，`curl` / `wget` 均支持；安装前自动清理旧版插件文件与旧内核（备份到 `/etc/adguardhome_lite/legacy-backup-时间戳/`），`--keep-old` 可跳过。

**强制更新**（不升版也能覆盖同版本文件，直接装 main 分支最新代码）：

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f
```

```sh
# 国内网络
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f -m https://gh-proxy.org
```

已用 ipk 安装的设备可以强制重装：

```sh
opkg install --force-reinstall /tmp/luci-app-adguardhome-lite_1.3.7-2_all.ipk
```

**常用参数**

| 参数 | 作用 |
|---|---|
| `-v 1.3.7-2` | 指定版本；`-v latest` 取最新 Release |
| `-f, --force` | 强制更新：忽略版本标签，用 main 分支最新代码覆盖安装 |
| `-m https://gh-proxy.org` | 指定反代，可重复 |
| `--no-deps` | 跳过依赖检查（依赖已装好时更快） |
| `--keep-old` | 只检测旧版残留，不自动清理 |
| `--purge-old` | 清理旧版时一并删除旧统计数据（保留 `/etc/AdGuardHome.yaml`） |
| `--src DIR` | 从本地源码目录安装（开发调试用） |
| `--uninstall` | 卸载插件，恢复 DNSMasq 原始设置，保留配置与内核 |
| `--purge` | 卸载并删除 `/etc/config/adguardhome_lite`、内核与统计数据 |

```sh
# 卸载（保留配置）
sh install.sh --uninstall

# 强制更新到 main 分支最新代码（不升版）
sh install.sh -f

# 安装指定版本并指定反代
sh install.sh -v 1.3.7-2 -m https://gh-proxy.org
```

> 💡 脚本安装不会出现在 `apk` 已安装列表，升级 / 卸载请继续用 `install.sh`；配置与内核重复安装时保留。

---

## 三步上手

1. **安装内核**：概览页点「安装/更新内核」，等进度完成；
2. **一键启用**：点「一键启用」，插件从模板生成配置并接管 DNS；
3. **打开 AGH 面板**：点「打开 AGH 面板」，用 `admin` / `admin123` 登录。

默认配置：

- 面板：`0.0.0.0:13800`，账号 `admin` / `admin123`（首次登录建议修改）
- DNS：默认「接管 53 端口」，DNSMasq 移到 `1745`，上游 `127.0.0.1:1745`
- 过滤规则：按内存自动选档（512MB 3 个 / 1GB 4 个 / 2GB+ 5 个分类列表，档内已去重），白名单默认添加但不启用
- 日志与统计：保留 30 天，查询日志只存内存不写闪存
- DNS 缓存：开启，16MB，最小 TTL 0，乐观缓存关闭；可在「基础设置 → DNS 解析」修改
- 加密上游：默认关闭，仅「Clash 前置」可开启（阿里 / DNSPod / Cloudflare DoH 或自定义）
- DNSSEC / fallback：默认关闭，避免 fake-IP 污染与查询绕过

---

## DNS 接管方式

| 方式 | 完整链路 | 适用场景 |
|---|---|---|
| **接管 53 端口**（默认） | 客户端 → 53 AdGuard Home → 1745 DNSMasq → 7874 Clash DNS / 上游 DNS | 想逐设备统计；装了 Clash、开着 DNS 劫持/转发也能用（插件自动收回 53） |
| PassWall 前置 | 客户端 → 53 AdGuard Home → 11400 起 PassWall DNS → 分流 | 装了 PassWall、不想关它的 DNS 劫持，又想保留过滤与逐设备统计 |
| DNSMasq 上游 | 客户端 → 53 DNSMasq → 5333 AdGuard Home → 自动上游 | 不想让 AdGuard Home 占 53，且没有程序抢 53 |
| Clash 前置 | 客户端 → Clash 劫持 → 7874 Clash DNS → 5335 AdGuard Home → 真实 DNS | 不想让 AdGuard Home 占 53、不需要逐设备统计 |
| 仅面板模式 | 不接管 DNS，仅提供管理面板 | 先体验面板或手动接管 |

### 怎么选

| 目标 | 推荐 |
|---|---|
| 逐设备统计、所有域名先过滤，同时保留 fake-IP 与分流 | 「接管 53」+ Clash DNS 劫持/转发 |
| 不用 Clash，用 PassWall 做分流 | 「PassWall 前置」 |
| 不使用 Clash | 「接管 53」 |
| 不想让 AdGuard Home 占 53，也不在乎逐设备统计 | 「Clash 前置」 |

前置模式的上游必须是真实 DNS，不要让两方上游互相指向，否则形成查询环。

「接管 53」可与 Clash 的劫持 / 转发并用：插件写入独立的 `agh_dns_redirect` 链（`priority -101`），在 Clash 规则前把局域网 53 查询（IPv4 + IPv6）收回路由器，劫持目标写 `:53`、`:1745` 或 `:7874` 都不会跳过过滤；写入后校验规则存在，缺失自动重载防火墙。

### 接管 53 + Clash（推荐组合）

Clash 开着「DNS 劫持」与「DNS 转发」时：

- **DNS 劫持**：把设备的 DNS 请求（含自设的 `8.8.8.8`）收回路由器。部分固件写 `redirect to :53`，也有 `:1745` / `:7874`；插件的 `agh_dns_redirect` 链先一步收回 53，三种写法都不影响过滤。
- **DNS 转发**：把 DNSMasq 上游改成 `127.0.0.1#7874`，交给 Clash DNS 解析。

完整链路：

```text
客户端 → Clash 劫持收回 53 → 53 AdGuard Home（过滤、记录真实设备 IP）
      → 1745 DNSMasq → 7874 Clash DNS（fake-IP、分流）→ 真实 DNS
```

过滤、逐设备统计、fake-IP 与分流同时保留；Clash 必须保持运行，停止会解析失败。

检查是否生效：

```sh
nft list chain inet fw4 agh_dns_redirect
nft list chain inet fw4 dstnat | grep 'Clash DNS Hijack'
```

- 有 `agh_dns_redirect` 链：正常，它在 Clash 劫持之前生效；
- Clash 劫持写 `:1745` 或 `:7874` 都没关系，自定义链已先接住；
- 没有该链且劫持直指 `:7874`：查询绕过 AdGuard Home，重新保存一次「接管 53 端口」。

### PassWall 前置

PassWall 默认开着 DNS 劫持，会把局域网 53 查询收到自己的 DNS（端口从 `11400` 起动态分配）。选「PassWall 前置」无需关闭它：

```text
客户端 → 53 AdGuard Home（过滤、记录真实设备 IP）
      → 127.0.0.1:<PassWall DNS 端口>（国内外分流）→ 真实 DNS
```

- 插件自建 `agh_dns_redirect` 链用 `priority -102`（比 PassWall 的 `-101` 更靠前），53 查询先进入 AdGuard Home；
- 系统 DNSMasq 仍移到 `1745`，AdGuard Home 上游写成 `127.0.0.1:<端口>`，端口从 `/tmp/etc/passwall/var` 读取；
- PassWall 未启用时上游回退 `127.0.0.1:1745`，不会断网；
- 该模式不支持「排除接口 / 客户端」，排除的设备直接落到 PassWall 劫持，有分流但不经过 AdGuard Home。

PassWall 重启换了 DNS 端口时，概览会提示「上游未指向当前 PassWall DNS」，重新保存一次即可。

### 排除接口与客户端（仅「接管 53」）

「接管 53」会收回所有私网来源的 53 查询。访客网络、IoT 网段或自建 DNS 的设备不想被过滤时，在「基础设置 → 插件配置」填写：

- **不参与接管的接口**：设备名，空格分隔，如 `br-guest wg0`；
- **不参与接管的客户端 IP / CIDR**：IPv4 / IPv6 均可，如 `192.168.1.50 192.168.2.0/24 fd00::5`。

命中的查询由 nft 规则交给系统 DNSMasq（1745）应答，不进 AdGuard Home 也不计入统计；指向 `8.8.8.8` 等外部 DNS 的查询直接放行。留空即全部接管。

官方配置没有「按接口放行」开关（`allowed_clients` 是白名单、`disallowed_clients` 是丢弃），所以在防火墙层实现，不改 `AdGuardHome.yaml`，也不影响 `--check-config`。

排查：`nft list chain inet fw4 agh_dns_redirect` 能看到 `AGH bypass ... to-dnsmasq` 与 `... direct` 成对规则即生效。

### 自定义域名转发（`server=/域名/IP`）

DNSMasq 里已有的 `server=/corp.example/10.0.0.1` 会被保留，不同接管方式影响不同：

- **接管 53**：查询先到 AdGuard Home，过滤与统计照常，自定义规则只改变上游解析路径；
- **DNSMasq 上游**：DNSMasq 优先匹配域名规则，这些域名直接发给指定服务器，不过滤、不计入统计。

需要这些域名也走过滤时，把规则改到 AdGuard Home「上游 DNS」，用 `[/corp.example/]10.0.0.1` 写法。

### Clash 前置说明

部分 Clash 配置会把 53 查询直接劫持到 `7874`（「接管 53」已由 `agh_dns_redirect` 收回，不受影响）。不想让 AdGuard Home 占 53 时可选「Clash 前置」，插件会自动：

- 让 AdGuard Home 监听 `5335`，上游改为真实 DNS（WAN 优先，其次公共 DNS），绝不指向 Clash；
- 开启 Clash 自定义 DNS（`enable_custom_dns=1`），新增 `127.0.0.1:5335` nameserver，暂禁用其它 nameserver，并关闭 `append_wan_dns`；
- 原值记在 UCI，停止或切换模式时恢复并重启 Clash；
- 要求 Clash 内核运行且 DNS 劫持已开启，否则面板提示「被绕过」。

该模式来源都是 Clash（`127.0.0.1`），没有逐设备统计；需要统计请用「接管 53」。fake-IP 会对所有 A 记录返回 `198.18.x.x`，被拦截域名在 DNS 层不显示 `0.0.0.0`，实际拦截发生在连接阶段。

<details>
<summary>「Clash 串联」为什么下线</summary>

该模式曾把 `server=/#/127.0.0.1#5333` 写进 DNSMasq 的 `conf-dir`，让查询先过 AdGuard Home 再交给 Clash。但实际环境里：

- Clash 自己会把 `server=127.0.0.1#7874` 写进 `dhcp.@dnsmasq[0].server`，生成的配置里它排在 `conf-dir` 之前；
- 加了 `strict-order` 后 DNSMasq 按顺序先问 Clash，Clash 有应答就不会再问 AdGuard Home；
- Clash 每次启动还会重写这条上游，转发文件随时失效。

结果就是「显示已接管、实际没过滤」。所以插件移除了这个选项，旧配置在保存或启动时自动迁移为「接管 53 端口」——它既能逐设备统计，也能保留 Clash 的 fake-IP 与分流。

</details>

### 与 Clash / PassWall 的启动顺序

开机顺序固定为 **DNSMasq（19）→ AdGuard Home（95）→ Clash / PassWall（99）**：前置模式下 Clash 上游写着 `127.0.0.1:5335`，须等 AdGuard Home 先监听；接管 53 时 AdGuard Home 依赖先启动的 DNSMasq（1745）。插件已注册 `START=95`，无需手动调整。

| DNS 接管方式 | 顺序要求 | 说明 |
|---|---|---|
| Clash 前置 | 无 | 上游是真实 DNS，不依赖 Clash |
| 接管 53 端口 | 可与 Clash 劫持同用 | 自定义链先收回 53，再经 DNSMasq（1745）交给 Clash（7874） |
| PassWall 前置 | PassWall 启动后分流 | 收回链先占 53，上游指向 PassWall DNS；未启动时按默认 `11400` 写入，不阻塞上网 |
| DNSMasq 上游 / 仅面板 | 无 | 不涉及 53 劫持 |

Clash 重启期间 DNS 可能中断 1~2 秒，属正常现象。

---

## 常见问题（FAQ）

### Q1：和传统 AdGuard Home 插件有什么区别？会和旧版冲突吗？

传统 `luci-app-adguardhome` 把配置项全搬进 LuCI，功能多但配置重；本插件只做三件事：**装内核、接 DNS、看状态**。默认三步完成，内置反代与 fake-IP 兜底，接管前记录 DNSMasq 原值，停止或卸载自动还原；常用过滤与日志在插件内完成，高级项仍由 AdGuard Home 面板管理。

与旧版冲突：安装包内置 `Conflicts` 声明，检测到会拒绝安装，请先卸载旧插件与 `luci-i18n-adguardhome-zh-cn` 并停止旧服务。

### Q2：怎么安装？25.12 / apk 系统怎么办？

- **ipk**：OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS 等新版 LuCI，用 [安装包](#方式一安装包ipk--run)；
- **apk**：25.12 起改用 `apk`，`.ipk` 装不上，用 [脚本安装](#方式二脚本安装2512--apk-系统)，上述固件也可用。

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
```

常用参数：`-v` 指定版本、`-f` 强制更新、`--uninstall` 卸载保留配置、`--purge` 删除配置与内核；脚本安装不会出现在 `apk` 已安装列表，后续升级和卸载继续用它。

不需要先手动装 AdGuard Home，首次点「安装/更新内核」即可，已有 `/etc/AdGuardHome.yaml` 会直接复用。

### Q3：内核下载失败，或重启后消失？

- **下载失败**：检查网络与系统时间；国内网络在「基础设置 → 插件配置」启用 GitHub 反代；fake-IP 环境自动解析真实 IP；空间不足时把内核位置改到内置存储或清理闪存。
- **预发布版**：依次尝试 GitHub 预发布（含反代）→ 官方预发布通道 → 正式版，日志记录每个地址的结果。
- **重启后消失**：内核装在 `/tmp` 内存位置，重装或在「基础设置 → 插件配置」改到内置存储。

### Q4：启用后不能上网 / 面板打不开 / 网页打不开？

**不能上网**：概览点「停止并关闭自启」会恢复接管前的 DNSMasq 设置。仍异常执行：

```sh
/etc/init.d/adguardhome_lite stop
/etc/init.d/dnsmasq restart
```

然后看「运行日志」，确认 53 / 1745 / 5333 / 5335 端口未被占用。

**停止后面板打不开**：正常现象，面板随服务停止，重新点「启动服务」；服务已运行仍打不开时，检查 UCI 端口与 YAML `address` 是否一致，等 5–10 秒。

**能连路由器但打不开网页**：设备没拿到 IPv4 DNS，给 LAN 补下发：

```sh
uci add_list dhcp.lan.dhcp_option='6,路由器IP'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

`路由器IP` 换成实际 LAN 地址，设备断开重连后生效。

### Q5：同时运行 Clash 时去广告不生效？

先确认收回规则存在：

```sh
nft list chain inet fw4 agh_dns_redirect
```

有 `redirect to :53` 时，Clash 劫持指向 `:53`、`:1745` 或 `:7874` 都不影响过滤；链不存在则重新保存一次「接管 53 端口」，或改用「Clash 前置」。

### Q6：卸载后 DNS 会恢复吗？

会。停止或卸载只写回接管前记录的 DNSMasq 端口、`noresolv`、`resolvfile` 和 `server`，不写公共 DNS。`--uninstall` 恢复 DNS 并保留配置与内核，`--purge` 才删除配置、内核与统计。

### Q7：DNS 缓存与加密 DNS 怎么设置？

- **缓存**：默认开启 16MB、最小 TTL 0（不覆盖上游）、最大 TTL 不限、乐观缓存关闭；在「基础设置 → DNS 解析」关闭并保存，升级用户保留原有缓存状态。
- **加密上游**：只在 AdGuard Home 直接查询真实上游时有意义，即「Clash 前置」模式；默认「接管 53」上游是本机 DNSMasq（loopback），加密不生效。需要防运营商劫持时选阿里或 DNSPod DoH（Cloudflare 等境外 DoH 通常需配合代理）。加密只保护「路由器 → 上游」，不影响过滤。

### Q8：出问题怎么快速定位？

先在概览点「DNS 自检」，只读检查内核、进程、13800 端口与本机 53 链路，不改配置；再到「运行日志」切到「仅错误」或「仅警告」，每条带原因码（如 `dns_hijack_conflict`、`core_integrity_failed`、`config_check_failed`）。反馈时附上错误那几行。

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

生成 modern（新版 LuCI）与 legacy（旧版 LuCI）两个包及 `SHA256SUMS`。再生成离线自解压包：

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
- [预置规则仓库](https://github.com/Ozero-top/AdguardHome-Rrules)：每 7 天自动抓取、去重、重分类的三档订阅，产物发布于 `dist` 分支。
- 插件内「使用引导」标签包含三步说明与常见问题入口。

---

## 更新日志

### 1.3.7-2

- **在线更新实测**：在 24.10（opkg）与 25.12（apk）设备上验证通用模式 / 安装包、强制重装与降级、渠道回退
- **设置文案修正**：更新方式中的「源码覆盖」更名为「通用模式」，避免误解为需要编译源码

### 1.3.7

- **插件在线更新**：发现新版本后可在页面内直接更新，支持国内加速（jsDelivr → gh-proxy → ghfast → 直连）与 GitHub 直连两种渠道，通用模式与安装包两种方式，实时显示下载百分比、阶段与日志，失败自动回退
- **强制更新 / 降级**：高级选项可重装当前版本或指定历史版本；更新前自动备份 UCI 配置；通用模式写入版本标记，避免降级后仍显示包管理器里的旧高版本
- **家长控制保护**：开启前试拨 AdGuard 服务端，连不上拒绝开启；运行中由看护进程每 30 秒探测，连不上自动关闭，避免全屋断网
- **显示名统一**：「AdGuard Home 管理中心」，包名、UCI 配置与菜单路由保持不变
- **发布基础设施**：新增 apk 产物（实验性）、`manifest-<版本>.txt` 清单与 SHA256 校验；Release 资产自动同步到 `dist` 分支，供 jsDelivr 国内加速

### 1.3.6

- **兼容 AdGuard Home v1.0.0**：安全搜索开关改用 `/control/safesearch/settings`，v0.107.53 及更早版本自动回退旧接口
- **修复自定义上游保存**：v1.0.0 起不再接受空的 `upstream_mode`，保存前自动归一化为 `load_balance`
- **内核通道更名**：「稳定版 / 测试版」改为「正式版 / 预发布版」，语义与发布策略一致，UCI 值不变

### 1.3.5-2

- **手动更新订阅**：「过滤规则」页档位按钮右侧一键让 AdGuard Home 立即重下载全部订阅，不必等自动周期
- **结果更明确**：区分「已是最新 / 已更新 N 个 / 未返回明细」，不再一律提示「更新完成」
- **白名单失败不打断**：黑名单成功时，白名单失败只作提示
- **并发保护**：档位切换与手动更新互斥，避免更新冲突
- **日志可追溯**：每次写入「运行日志 → 订阅更新日志」（保留最近 100 次）
- **超时对齐**：后端黑名单 45 秒、白名单 20 秒，前端 90 秒

### 1.3.5

- **拦截 DoH 服务器**：「过滤规则」页一键写入 / 移除 9 条常见加密 DNS（`dns.google`、`cloudflare-dns.com`、`dns.quad9.net`、`doh.pub` 等）拦截规则，防止绕过；关闭时按域名清理，裸域名与 `||domain^` 两种写法都会移除
- **预置规则补全广告根域**：`$third-party` 规则降级为纯域规则，新增手工广告根域清单（`tanx.com`、`alimama.com`、`mmstat.com` 等），覆盖平台临时新增的子域
- **规则仓库瘦身**：移除 5 个零产出源，`meta.json` 增加原始行数与有效率；CI 条数门禁放宽到最近 5 条提交，重构可加 `[allow-drift]` 放行
- **修复面板报错**：过滤接口返回空列表（`{}`）时不再抛 `TypeError`，DoH 开关与自定义规则回填恢复
- **面板布局**：DoH 开关移入「自定义规则」区域，与输入框横向并列、高度一致，窄屏自动堆叠

### 1.3.4

- 预置过滤规则改由自建规则仓库提供，每 7 天自动抓取、跨源去重并按分类重新生成，按设备内存分 512MB / 1GB / 2GB+ 三档
- 修复带路径或修饰符的广告规则被压成整域拦截导致的误杀问题；白名单改为默认添加但保持关闭

---

> **搭配浏览器扩展效果更佳**
>
> 路由器端只能按域名拦截，页面内广告位、同域名广告和追踪脚本需要浏览器端过滤。建议再装 AdGuard 浏览器扩展或 uBlock Origin，叠加后 adblock-tester.com 通常能到 95% 以上。
>
> - 官方下载页（自动识别浏览器）：<https://adguard.com/zh_cn/adguard-browser-extension/overview.html>
> - Chrome 应用商店：<https://chromewebstore.google.com/detail/adguard-adblocker/bgnkhhnnamicmpeenaelnjfhikgbkllg>
> - Edge / Firefox 在各自扩展商店搜「AdGuard AdBlocker」
>
> 只装扩展，手机、电视过滤不到；只装路由器端，页面里仍会剩广告。

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
