# 折腾 AdGuard Home 这么久，我干脆把它做成了个插件

先说结论：如果你在用 OpenWrt / ImmortalWrt / iStoreOS，想装 AdGuard Home 又不想跟配置文件和防火墙规则死磕，可以直接用我这个插件，装完三步就能跑起来。

项目地址：<https://github.com/Ozero-top/luci-app-adguardhome-lite>

下面按我自己的经历聊，想到哪写到哪。

## 一、为什么又写一个

第一次装 AdGuard Home，我卡了两件事。

第一件是下载。官方 GitHub 在国内经常拉不动，好不容易下下来，架构还下错了，路由器上跑不起来。第二件是接管 DNS。教程里全是"把 53 端口给 AdGuard Home，DNSMasq 改到 1745"，照着改完发现网断了，回头还得一点点恢复。

后来断断续续折腾了好几台设备，每次都要重复这一套。我就想，这些东西其实都能自动化：架构自动识别、内核自动下载、DNSMasq 的原始设置先备份、停止或者卸载时再还回去。

插件就这么来的。它只管三件事：装内核、接 DNS、看状态。过滤规则、查询日志、家长控制这些，还是进 AdGuard Home 自己的面板操作，我不去重复造。

## 二、先装上

装的时候看你的固件版本，别装错包。

- **OpenWrt 23.05 / 24.10、ImmortalWrt、iStoreOS**：用普通 `ipk`，LuCI 里"系统 → 软件包 → 上传安装包"传上去就行。
- **OpenWrt 22.03 及更早**（老的原生 Lua LuCI）：用 `legacy` 版。
- **25.12 及以后的 apk 系统**：`.ipk` 装不了，得用脚本。

脚本装最省事，curl 一行：

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh
```

国内网络拉 raw 也慢的话，加上反代：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -m https://gh-proxy.org
```

这里有个我踩过的坑：opkg 同版本不会覆盖，你重新传一个版本号一样的包，它直接跳过。以前每次改点东西都得升个版本号，挺烦。现在脚本加了 `-f`，直接从 main 拉最新代码覆盖，不用再为了一个文案改动升版本：

```sh
curl -fsSL https://raw.githubusercontent.com/Ozero-top/luci-app-adguardhome-lite/main/install.sh | sh -s -- -f
```

已经有 ipk 的也可以强行重装：

```sh
opkg install --force-reinstall /tmp/luci-app-adguardhome-lite_1.2.0-1_all.ipk
```

装完在 LuCI 的"服务"菜单里找 **AdGuard Home 助手**。注意别跟老的 `luci-app-adguardhome` 一起装，会打架，先把旧的卸干净。

## 三、三步就能用

打开插件页，就三步：

1. 点「安装/更新内核」，等进度条走完；
2. 点「一键启用」，插件从内置模板生成配置，顺手把 DNS 接管了；
3. 点「打开控制台」，用 `admin` / `admin123` 登录。

默认配置我调过，基本是冲着"开箱能过滤"去的：面板在 `0.0.0.0:13800`，带了 11 个过滤规则和 1 个白名单，日志和统计留 30 天（查询日志只放内存，不写闪存，这点对路由器挺重要）。缓存、DNSSEC 这些默认是关的，不是它们没用，是开了容易和 fake-IP 打架，出问题的概率比带来的收益大。

第一次进控制台记得把密码改掉。

## 四、DNS 接管怎么选

这是最多人问的地方，我直接给结论。

**没装 OpenClash：选「接管 53 端口」，不用想。**

**装了 OpenClash：还是选「接管 53 端口」。**

对，就这么简单。以前 OpenClash 的 DNS 劫持会把设备的 53 查询直接拽到 `7874`，AdGuard Home 根本收不到，等于白装。现在插件会自己建一条 nftables 链 `agh_dns_redirect`（优先级 -101），排在 OpenClash 的劫持规则前面，把局域网设备的 53 查询先收回来交给 AdGuard Home。所以 OpenClash 那边劫持写成 `:53`、`:1745` 还是 `:7874`，都绕不过去。

完整链路是这样：

```
客户端 → 收回 53 → AdGuard Home（过滤 + 记录设备 IP）
      → DNSMasq 1745 → Clash DNS 7874（fake-IP、分流）→ 真实 DNS
```

过滤、逐设备统计、fake-IP、分流，一个都没少。

想确认生效没有，SSH 上去敲：

```sh
nft list chain inet fw4 agh_dns_redirect
```

看到里面有 `redirect to :53` 就对了。要是这条链不在，回插件里重新保存一次「接管 53 端口」模式。

还有个新加的东西：**不想被接管的设备和接口**。比如访客 WiFi 网段、你自己另搭的一台 DNS、或者跑旁路由的机器，原来一律会被拉进 AdGuard Home。现在基础设置里能勾「不参与接管的接口」（下拉里直接列当前网卡，勾一个排除一个），也能填客户端 IP 或网段。命中的查询会直接交给 DNSMasq（1745）应答，不进 AdGuard Home，也不占统计，留空就是全接管。

顺带说下，设置项现在会跟着接管方式变灰：排除项只有「接管 53」能改，选别的模式那两块是灰的；没装 OpenClash，「OpenClash 前置」点不了；「DNSMasq 上游」配着 OpenClash 会提醒你上游可能被覆盖。灰掉只是不让改，值都还在，切回「接管 53」立刻生效——该拦的别拦错，比事后排错省事。

提醒一句：被排除的设备，查 `8.8.8.8` 这类外部 DNS 也是直接放行的，既不过滤、也不会被 Clash 劫持带走。要是它只能靠运营商 DNS，可能就解析不了，这点自己心里有数就行。

另外提一句，之前有个「OpenClash 串联」模式，我已经干掉了。原因很实在：OpenClash 会把 `server=127.0.0.1#7874` 写进 DNSMasq，而且排在 `conf-dir` 前面，`strict-order` 下 DNSMasq 先问 Clash，Clash 一应答就不往 AdGuard Home 走了。表现出来就是"面板显示已接管，实际一条都没拦"。旧配置在保存或者启动时会自动迁移成「接管 53」，不用手动改。

还有个「OpenClash 前置」模式，链路是 Clash → AdGuard Home → 真实 DNS。什么时候用？只有一种情况：你死活不想让 AdGuard Home 占 53。代价是 AdGuard Home 看到的来源全是 `127.0.0.1`，没法按设备统计，Clash 的 fake-IP 也会让被拦的域名在 DNS 层不显示成 `0.0.0.0`。能不用就不用。

## 五、几个实际会遇到的问题

**启用后上不了网。** 概览页点「停止并关闭自启」，插件会把 DNSMasq 的设置还原回去。还不行就 SSH：

```sh
/etc/init.d/adguardhome_lite stop && /etc/init.d/dnsmasq restart
```

**设备连着 WiFi 但打不开网页。** 大概率是设备没拿到 IPv4 的 DNS。在路由器上补一条 DHCP 下发：

```sh
uci add_list dhcp.lan.dhcp_option='6,192.168.1.1'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

把 `192.168.1.1` 换成你路由器的 LAN 地址，设备重连一下就好。

**重启路由器后内核没了。** 内核装在 `/tmp`，重启就清空。重新点一次安装，或者装到内置存储。

**页面上的广告还是能看见。** 路由器端只能按域名拦，页面里的广告位、同域名的推广、追踪脚本它管不了。想在浏览器里干净，再装个 AdGuard 浏览器扩展或者 uBlock Origin，两边一起用才能到 95% 以上。手机、电视这种装不了扩展的设备，就靠路由器端。

**Clash 停了就解析不了。** 「接管 53」这套链路里 DNSMasq 的上游是 Clash 的 7874，Clash 必须开着。这是设计如此，不是 bug。

## 六、版本和更新

插件页面上现在会显示自己的版本号，有新版本会在标题下面提示，点一下就跳到 Release。检查是后台跑的，24 小时一次，不占你页面加载时间，网络不通就顺延到下一轮。

更新的时候：

- 脚本装的：直接用上面的 `-f` 强制更新，不用等版本号；
- ipk 装的：下载新包 `--force-reinstall`，或者直接升版本。

启动顺序我也调好了，**DNSMasq（19）→ AdGuard Home（95）→ OpenClash（99）**，不用你手动改。OpenClash 重启的时候 DNS 会断个一两秒，正常。

## 最后

项目在 <https://github.com/Ozero-top/luci-app-adguardhome-lite>，Release 里同时给了 ipk、legacy ipk 和离线的 `.run` 包，还有 SHA256 校验。

用着有问题直接提 issue，把固件型号、架构和插件日志一起贴上，我好定位。别只写"不能用"，那我也没法猜。
