# AGHTools管理器（Android）

路由器插件 `luci-app-adguardhome-lite` 的手机管理端。登录 LuCI 后，直接调用插件的 JSON 接口，完成状态查看、服务控制、过滤规则、查询日志、参数设置、内核与插件更新等操作。

## 环境要求

- JDK 17
- Android SDK（compileSdk 35，build-tools 35.0.0）
- 路由器已安装 `luci-app-adguardhome-lite`，且插件版本包含 `/session` 接口

`local.properties` 中的 `sdk.dir` 指向本机 Android SDK。

## 构建

```bash
# Debug
./gradlew assembleDebug

# Release（使用 android/keystore/agh-release.jks 签名）
./gradlew assembleRelease

# 单元测试
./gradlew testDebugUnitTest
```

产物位置：

- `app/build/outputs/apk/debug/app-debug.apk`
- `app/build/outputs/apk/release/app-release.apk`

发布时重命名为 `AGHTools<版本>.apk`（例如 `AGHTools1.3.7-9.apk`）。

签名口令通过环境变量提供：

- `AGH_KEYSTORE_PASS`
- `AGH_KEY_ALIAS`（默认 `agh`）
- `AGH_KEY_PASS`

`keystore/` 已加入 `.gitignore`，不会提交到仓库。

## 安装

```bash
adb install -r app/build/outputs/apk/release/app-release.apk
```

## 连接路由器

1. 填写路由器地址与 LuCI 端口（默认 80）。
2. 输入 LuCI 账号密码（通常为 `root`）。
3. 点击「连接」。

账号密码保存在 Android 加密存储（EncryptedSharedPreferences）中；部分设备 Keystore 异常时会退回普通存储以保证可用。

登录流程：

1. `POST /cgi-bin/luci/` 取会话 Cookie；
2. `GET /cgi-bin/luci/admin/services/adguardhome_lite/session` 取 CSRF 令牌；
3. 所有写操作携带 `token` 表单字段；会话过期（403）时自动重新登录并重试一次。

## 页面

- **概览**：运行状态、统计、服务启停 / 重启、清空统计、DNS 自检、内核通道切换（正式版 / 预发布版）。
- **日志**：系统日志（可按级别筛选）与查询日志（拦截状态、域名搜索、分页）。
- **规则**：过滤开关（安全搜索 / 家长控制 / 成人内容，成人内容与家长控制互斥）、预置档位与下载源、订阅增删启停、自定义规则。
- **设置**：接管方式、端口、内核位置、缓存、上游 DNS、排除列表、保留周期、YAML 编辑。
- **更多**：内核安装 / 更新、插件检查 / 更新、面板密码、旧版残留扫描清理。

客户端过滤不占用底部标签，需在登录页点「仅使用客户端过滤（不连接路由器）」进入。

所有写操作都会弹出确认框，操作结果显示在页面顶部并以 Toast 提示。

## 客户端过滤（手机 VPN）

从登录页底部的「仅使用客户端过滤（不连接路由器）」进入，使用 `VpnService` 建立一个只接管 DNS 的本地 VPN：

- 系统 DNS 指向 `10.111.222.1`，仅该地址的 UDP 53 流量进入 tun，其它流量不经过 VPN。
- 命中去重后的规则返回 NXDOMAIN，其余查询转发到自定义上游（默认 `223.5.5.5, 119.29.29.29`）。
- 内置基础清单保证离线可用；更新时固定使用 2GB 档位的全部六类规则（安全、中文、跟踪、广告、网页干扰、外语），从 jsDelivr / GitHub 下载并写入应用私有目录。
- 通知栏可「暂停 30 秒」或停止；快捷设置磁贴点击可在开启、暂停、恢复之间切换。
- 应用分流支持「全部应用 / 仅选中应用 / 排除选中应用」，应用列表只读取有桌面入口的应用（通过 `<queries>` 声明，不申请 `QUERY_ALL_PACKAGES`）；修改后会重启过滤立即生效。
- 开机自启：开关打开、且关机前过滤处于开启状态、VPN 授权仍有效时，开机后自动恢复过滤。
- 拦截日志：记录最近 300 条被客户端拦截的域名（时间、查询类型），只记录拦截、不记录放行，每页 15 条，可一键清空；写入应用私有目录。
- 匹配使用排序后的域名数组 + 后缀二分查找，纯 Kotlin 实现，不依赖 NDK。

注意：浏览器或应用启用 DoH（安全 DNS）、或系统「私人 DNS」设为自动 / 指定 DoT 时，DNS 查询会绕过客户端过滤。

## 说明

- HTTP 明文请求通过 `usesCleartextTraffic` 允许，适用于局域网。若路由器启用 HTTPS，请在登录页打开「使用 HTTPS」。
