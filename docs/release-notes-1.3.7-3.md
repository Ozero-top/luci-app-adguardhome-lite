# AdGuard Home 管理中心 v1.3.7-3

本次更新修复 25.12 设备切换预置规则档位失败的问题。

## 修复

- **档位切换误报**：AdGuard Home 没有黑名单订阅时返回 `"filters": null`，插件此前把它当成接口读取失败，提示「读取规则列表失败，请确认 AdGuard Home 正在运行」。现在按空列表处理。
- **预置列表拉取兜底**：部分网络下 AGH 直连 `cdn.jsdelivr.net` / `raw.githubusercontent.com` 会 TLS 报错（如 `EOF`），新增按「jsDelivr → GitHub raw → 配置的 GitHub 反代（默认 gh-proxy.org）→ ghfast.top」依次重试，切换档位可正常写入列表。
- **失败可见**：预置列表添加失败不再静默返回成功，会指出具体列表并提示检查网络或更换反代。

## 验证

- iStoreOS 25.12（apk）：切换到 512MB 档成功，安全防护 13,090 条、中文广告 60,000 条、全站广告 60,000 条；重复切换返回 `changed=0`，列表不重复下载；规则页可正常读取。
- 同一设备 AGH 直连 jsDelivr 失败时，自动改走 gh-proxy 添加成功。

## 升级方式

页面内点击「发现 v1.3.7-3，立即更新」，或使用安装包 / 脚本：

```sh
opkg install --force-reinstall luci-app-adguardhome-lite_1.3.7-3_all.ipk
# 或
sh install.sh -v 1.3.7-3
```

## 兼容性

- OpenWrt 22.03 及更早：使用 `legacy` 安装包。
- OpenWrt 23.05 / 24.10 / iStoreOS 24.10：使用 modern 安装包。
- OpenWrt / iStoreOS 25.12（apk）：使用通用模式；apk 资产仍为实验性，失败会自动回退。
- 适配 AdGuard Home v1.0.0。

## 校验

Release 附带 `SHA256SUMS` 与 `manifest-1.3.7-3.txt`：

```sh
sha256sum -c SHA256SUMS
```

## 注意

- 在线更新会重启 AdGuard Home，DNS 会短暂中断。
- 预置列表添加成功后会由 AdGuard Home 继续定期更新；若后续直连失效，可在「插件配置 → GitHub 反代」更换可用节点。
