# AdGuard Home 管理中心 v1.3.7-2

本次更新用于验证插件在线更新链路，并修正一个设置文案问题。

## 验证

- **24.10 / opkg**
  - 强制通用模式降级到 1.3.5-2、版本固定、安装包回退、GitHub 渠道、`opkg --force-downgrade` 全部通过。
  - 验证后已恢复 1.3.6-1，配置与 DNS 正常。
- **25.12 / apk**
  - 通过页面后端完整走通在线更新：manifest 获取、SHA256 校验、下载与安装。
  - apk 包格式不被 apk-tools 识别时，自动回退通用模式并成功升级到 1.3.7。
- **在线更新链路**
  - 国内加速（jsDelivr → gh-proxy → ghfast → 直连）与 GitHub 直连均可回退。
  - 进度、日志、失败原因与重新打开页面后的进度恢复均正常。

## 修复

- **设置文案**：更新方式中的「源码覆盖」更名为「通用模式」，避免误解为需要编译源码。
  - 界面：`自动（通用模式）` / `安装包（可选）`
  - 日志与进度：`通用模式` / `安装包模式`
  - 内部参数仍为 `method=source`，旧版本与接口保持兼容。

## 升级方式

页面内点击「发现 v1.3.7-2，立即更新」，或使用安装包 / 脚本：

```sh
opkg install --force-reinstall luci-app-adguardhome-lite_1.3.7-2_all.ipk
# 或
sh install.sh -v 1.3.7-2
```

## 兼容性

- OpenWrt 22.03 及更早：使用 `legacy` 安装包。
- OpenWrt 23.05 / 24.10 / iStoreOS 24.10：使用 modern 安装包。
- OpenWrt / iStoreOS 25.12（apk）：使用通用模式；apk 资产仍为实验性，失败会自动回退。
- 适配 AdGuard Home v1.0.0。

## 校验

Release 附带 `SHA256SUMS` 与 `manifest-1.3.7-2.txt`：

```sh
sha256sum -c SHA256SUMS
```

## 注意

- 在线更新会重启 AdGuard Home，DNS 会短暂中断。
- 强制更新/降级前会自动备份 UCI 配置；降级可能遇到配置结构变化。
- apk 产物仍为实验性，本次实测会触发格式错误并自动回退通用模式，不影响最终升级。
