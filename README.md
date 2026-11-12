# AdGuard Home 助手

OpenWrt / ImmortalWrt / iStoreOS 上的 LuCI 插件，把 AdGuard Home 的安装、DNS 接管和服务管理收进一个页面：装内核、接 DNS、看状态，三步完成。

> 插件管安装与接管；过滤规则、查询日志、家长控制等仍在 AdGuard Home 面板里操作。

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

<div align=center>
<img src="https://ozero.top/media/2026/11/6af2d7b3091938.16423231.png" width="600" height="794">
</div>

---

> **搭配浏览器扩展效果更佳**
>
> 路由器上的 AdGuard Home 只能按域名拦截，页面内的广告位、同域名广告和追踪脚本需要浏览器端过滤。建议再装一个 AdGuard 浏览器扩展或 uBlock Origin，两者叠加后，adblock-tester.com、adblock.turtlecute.org 这类测试通常能到 95% 以上。
>
> - 官方下载页（自动识别浏览器）：<https://adguard.com/zh_cn/adguard-browser-extension/overview.html>
> - Chrome 应用商店：<https://chromewebstore.google.com/detail/adguard-adblocker/bgnkhhnnamicmpeenaelnjfhikgbkllg>
> - Edge 在扩展商店搜「AdGuard AdBlocker」；Firefox 在 addons.mozilla.org 搜「AdGuard」
>
> 只装扩展，手机、电视这类设备过滤不到；只装路由器端，页面里还是会剩一些广告。推荐两边一起用。

---

## 功能特性

- **三步上手**：安装内核 → 一键启用 → 打开控制台，每步都有状态提示和失败原因，不需要敲命令。
- **官方内核**：自动识别 CPU 架构，从 AdGuard 官方源下载最新稳定版。
- **下载兜底**：可选 `gh-proxy.org`、`ghproxy.cc`、`ghproxy.com`、`ghfast.top` 反代，失败自动回退官方 CDN 与 GitHub 直连。
- **fake-IP 兼容**：路由器用 OpenClash 等 fake-IP DNS 时，自动用公共 DNS 解析真实 IP，再以 `curl --resolve` 下载。
- **四种 DNS 接管方式**：接管 53、DNSMasq 上游、OpenClash 前置、仅面板（「OpenClash 串联」已下线，旧配置自动迁移）。
- **OpenClash 共存**：推荐「接管 53 + OpenClash DNS 劫持/转发」。插件会自建 `agh_dns_redirect` 链把设备的 53 查询收回，OpenClash 劫持指向 `53`、`1745` 还是 `7874` 都绕不过过滤；也支持「Clash → AdGuard Home → 真实 DNS」的前置链路。
- **页内看统计**：概览直接显示 DNS 查询、过滤器拦截、恶意/钓鱼、成人内容四项数据，每 10 秒随状态刷新，不用打开控制台。
- **成人内容拦截**：基础设置里一个开关，自动追加/移除 HaGeZi NSFW 规则，关闭即还原。
- **规则更新走代理**：自动检测 OpenClash 的 HTTP 代理并写入 `http_proxy`，避免国内直连 GitHub 更新失败。
- **参数自动配置**：保存接管方式时自动关闭缓存与 DNSSEC、改用并行上游，并按模式写入上游与 PTR。
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

> 与旧版 `luci-app-adguardhome` 冲突，安装前先卸载旧插件及中文语言包。

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

脚本会依次尝试 `gh-proxy.org`、`ghfast.top`、`gh-proxy.com` 和 GitHub 直连，哪个能用用哪个，`curl` 与 `wget` 都支持。

**强制更新**（不升版也能覆盖同版本文件，直接装 main 分支最新代码）：

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f

# 国内网络
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f -m https://gh-proxy.org
```

已用 ipk 安装的设备可以强制重装：

```sh
opkg install --force-reinstall /tmp/luci-app-adguardhome-lite_1.1.8-1_all.ipk
```

**常用参数**

| 参数 | 作用 |
|---|---|
| `-v 1.1.8` | 指定版本；`-v latest` 取最新 Release |
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
sh install.sh -v 1.1.8 -m https://gh-proxy.org
```

> 脚本安装不会在 `apk` 的已安装列表里留记录，升级/卸载都请继续用 `install.sh`；`/etc/config/adguardhome_lite` 与内核在重复安装时都会保留。

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
- 缓存 / DNSSEC / fallback：默认关闭，避免 fake-IP 缓存污染与查询绕过

---

## DNS 接管方式

| 方式 | 完整链路 | 适用场景 |
|---|---|---|
| **接管 53 端口**（默认） | 客户端 → 53 AdGuard Home → 1745 DNSMasq → 7874 Clash DNS / 上游 DNS | 想逐设备统计；装了 OpenClash、开着 DNS 劫持/转发也能用（插件自动收回 53） |
| DNSMasq 上游 | 客户端 → 53 DNSMasq → 5333 AdGuard Home → 自动上游 | 不想让 AdGuard Home 占 53，且没有程序抢 53 |
| OpenClash 前置 | 客户端 → OpenClash 劫持 → 7874 Clash DNS → 5335 AdGuard Home → 真实 DNS | 不想让 AdGuard Home 占 53、不需要逐设备统计 |
| 仅面板模式 | 不接管 DNS，仅提供管理面板 | 先体验面板或手动接管 |

### 怎么选

| 目标 | 推荐 |
|---|---|
| 逐设备统计、所有域名先过滤，同时保留 fake-IP 与分流 | 「接管 53」+ OpenClash DNS 劫持/转发 |
| 不使用 OpenClash | 「接管 53」 |
| 不想让 AdGuard Home 占 53，也不在乎逐设备统计 | 「OpenClash 前置」 |

不要同时让一方的上游指向另一方：前置模式的上游必须是真实 DNS，否则会形成查询环。

「接管 53」可以和 OpenClash 的 DNS 劫持/转发一起用：插件会写入独立的 `agh_dns_redirect` 链（`priority -101`），在 OpenClash 规则之前把局域网设备的 53 查询（IPv4 + IPv6）收回路由器 53 端口，所以劫持目标写 `:53`、`:1745` 或 `:7874` 都不会跳过 AdGuard Home；写入后会实际校验规则是否存在，缺失时自动重载防火墙。

### 接管 53 + OpenClash（推荐组合）

OpenClash 开着「DNS 劫持」和「DNS 转发」时，这两件事分别是：

- **DNS 劫持**：把设备的 DNS 请求（包括设备自己设的 `8.8.8.8`）收回路由器。部分固件写 `redirect to :53`，也有写 `:1745` / `:7874` 的；插件的 `agh_dns_redirect` 链会先一步收回 53，三种写法都不影响过滤。
- **DNS 转发**：把 DNSMasq 的上游改成 `127.0.0.1#7874`，交给 Clash DNS 解析。

完整链路：

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

- 有 `agh_dns_redirect` 链（`priority -101`）：正常，它在 OpenClash 的劫持规则之前生效；
- OpenClash 自己的劫持写成 `:1745` 或 `:7874` 都没关系，前面的自定义链已经先接住了；
- 没有 `agh_dns_redirect` 且劫持直接指向 `:7874`：查询会跳过 AdGuard Home，重新选一次「接管 53 端口」。

注意：这套组合里 Clash 必须保持运行（DNSMasq 上游指向 7874），Clash 停止时会解析失败。

### OpenClash 前置说明

部分 OpenClash 配置会把 53 查询直接劫持到 `7874`（「接管 53」已由 `agh_dns_redirect` 收回，不受影响）。如果不想让 AdGuard Home 占 53，可以选「OpenClash 前置」，插件会自动：

- 让 AdGuard Home 监听 `5335`，上游改为真实 DNS（WAN 优先，其次公共 DNS），绝不指向 Clash；
- 开启 OpenClash 自定义 DNS（`enable_custom_dns=1`），新增 `127.0.0.1:5335` 的 nameserver，暂时禁用其它 nameserver，并关闭「追加 WAN DNS」（`append_wan_dns=0`）；
- 原值全部记在插件 UCI 里，停止/切换模式时恢复，并重启 OpenClash 使配置生效；
- 要求 Clash 内核正在运行且 OpenClash DNS 劫持已开启，否则面板会提示「被绕过」。

这个模式下 AdGuard Home 看到的来源都是 Clash（`127.0.0.1`），没有逐设备统计；需要逐设备统计请用「接管 53」。另外 Clash 的 fake-IP 会对所有 A 记录返回 `198.18.x.x`，被拦截的域名在 DNS 层不会显示成 `0.0.0.0`，实际拦截发生在连接阶段。

### 「OpenClash 串联」为什么下线

该模式曾把 `server=/#/127.0.0.1#5333` 写进 DNSMasq 的 `conf-dir`，让查询先过 AdGuard Home 再交给 Clash。但实际环境里：

- OpenClash 自己会把 `server=127.0.0.1#7874` 写进 `dhcp.@dnsmasq[0].server`，生成的配置里它排在 `conf-dir` 之前；
- 加了 `strict-order` 后 DNSMasq 按顺序先问 Clash，Clash 有应答就不会再问 AdGuard Home；
- OpenClash 每次启动还会重写这条上游，转发文件随时失效。

结果就是「显示已接管、实际没过滤」。所以插件移除了这个选项，旧配置在保存或启动时自动迁移为「接管 53 端口」——它既能逐设备统计，也能保留 Clash 的 fake-IP 与分流。

### 与 OpenClash 的启动顺序

开机按初始化顺序启动：**DNSMasq（START=19）→ AdGuard Home（START=95）→ OpenClash（START=99）**。

| DNS 接管方式 | 顺序要求 | 说明 |
|---|---|---|
| OpenClash 前置 | 无要求 | AdGuard Home 上游是真实 DNS，不依赖 Clash |
| 接管 53 端口 | 可与 OpenClash 劫持同用 | 自定义链先收回 53，再经 DNSMasq（1745）交给 Clash（7874） |
| DNSMasq 上游 / 仅面板 | 无要求 | 不涉及 53 端口劫持 |

- 顺序固定为 **DNSMasq（19）→ AdGuard Home（95）→ OpenClash（99）**：前置模式下 OpenClash 的上游写着 `127.0.0.1:5335`，必须等 AdGuard Home 先监听；接管 53 时 AdGuard Home 又依赖先启动的 DNSMasq（1745）。插件已注册好 `START=95`，无需手动调整。
- 想逐设备统计：用「接管 53」，OpenClash 的 DNS 劫持/转发保持开启即可；
- 不想让 AdGuard Home 占 53：用「OpenClash 前置」（没有逐设备统计）；
- OpenClash 重启期间 DNS 会短暂中断 1~2 秒，属正常现象。

---

## 常见问题

- **内核下载失败**：检查网络与系统时间；国内网络启用 GitHub 反代；fake-IP 环境已自动绕过。
- **启用后不能上网**：概览页点「停止并关闭自启」，插件会恢复 DNSMasq；仍异常可执行 `/etc/init.d/adguardhome_lite stop && /etc/init.d/dnsmasq restart`。
- **停止后面板打不开**：正常现象，面板随服务停止；重新「启动服务」即可。
- **改了面板端口打不开**：等 5-10 秒，确认服务运行中、UCI 端口与 YAML `address` 一致。
- **OpenClash 下不去广告**：先确认 `nft list chain inet fw4 agh_dns_redirect` 有 `redirect to :53`；有这条链时无论 OpenClash 劫持指向哪里都会过滤。若不存在，重新保存一次「接管 53 端口」，或改用「OpenClash 前置」。
- **设备能连路由器但打不开网页**：多为设备没拿到 IPv4 DNS。给 LAN 补一条 DHCP DNS 下发：`uci add_list dhcp.lan.dhcp_option='6,路由器IP'`（换成实际 LAN 地址），然后 `uci commit dhcp && /etc/init.d/dnsmasq restart`，设备重连后生效。
- **重启后内核消失**：内核装在 `/tmp` 内存位置，重新安装，或改到内置存储。

更多内容见 [安装与使用说明](docs/安装与使用说明.md)。

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

- [安装与使用说明](docs/安装与使用说明.md)：安装验证清单、DNS 接管详解、OpenClash 排查、卸载回滚与常见问题。
- 插件内「使用引导」标签包含三步说明与常见问题入口。

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
