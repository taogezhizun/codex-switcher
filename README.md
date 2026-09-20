<p align="center">
  <img src="docs/images/app-icon.png" width="88" height="88" alt="Codex Switcher 图标">
</p>
<h1 align="center">Codex Switcher</h1>
<p align="center">简体中文 · <a href="README.en.md">English</a></p>
<p align="center">切换 Codex 账号，随时查看额度。</p>
<p align="center">
  <a href="https://github.com/taogezhizun/codex-accounts-mac/releases/latest/download/Codex-Accounts-macOS-arm64.dmg"><strong>下载 Apple Silicon 版 ↓</strong></a>
  &nbsp; · &nbsp;
  <a href="https://github.com/taogezhizun/codex-accounts-mac/releases/latest/download/Codex-Accounts-macOS-x86_64.dmg"><strong>下载 Intel 版 ↓</strong></a>
</p>
<p align="center"><sub>macOS 14+ &nbsp; / &nbsp; 原生 SwiftUI &nbsp; / &nbsp; 免费开源</sub></p>

<p align="center">
  <img src="docs/images/app-overview.svg" width="960" alt="Codex Switcher 界面示意：快速切换账号并查看剩余额度，所有数据均为虚构。">
</p>
<p align="center"><sub>界面示意 · 账号与额度均为虚构</sub></p>

- **切换账号** — 在主窗口或菜单栏选择账号，确认后重开 Codex 桌面 App。
- **掌握额度** — 每 5 分钟刷新所有已保存账号，支持一键刷新全部；状态栏显示当前账号剩余百分比。
- **本机保存** — 账号与恢复备份保存在本机私有文件；旧版账号可主动迁移。
- **应用内更新** — 菜单内提示新版本，确认后原位升级。

**当前版本 0.4.5：菜单更清晰，管理窗口只保留一个。** 修复菜单上下边缘和背景透明问题；账号行新增“今日已用≈X%”，没有足够记录时显示“—”，按本机时区统计当天观察到的消耗。 已有账号和设置继续保留，通过 App 内更新即可升级。新安装和完成迁移后的账号操作不访问钥匙串；旧数据仅在你点击“开始迁移”时请求读取授权。文件保存完整登录凭据，未经过应用层加密。详见[本地存储与迁移](docs/USAGE.md#本地存储与迁移)。凭据失效的账号暂停自动刷新并提示重新登录，其他账号照常更新。

## 安装

1. 下载适合你的 Mac 的 **DMG**：M 系列芯片选择 Apple Silicon，Intel 芯片选择 Intel。
2. 打开 DMG，将应用图标拖到右侧 **Applications** 文件夹。
3. 从「应用程序」启动工具，再推出磁盘映像。

已有旧版？推荐使用「设置 → 应用更新」原位升级。为兼容已有安装，App 包和下载文件保留 `Codex Accounts` / `Codex-Accounts` 旧文件名；界面显示为 Codex Switcher，不需要另装一份。手动安装时先退出旧工具，再拖入并替换同名 App。

当前使用 ad-hoc 签名，未经过 Apple 公证；首次打开可能出现系统安全提示。详见[安装与兼容性说明](docs/USAGE.md)。[所有版本与 ZIP 下载](https://github.com/taogezhizun/codex-accounts-mac/releases)。

## 开始使用

1. 在设置中确认 Codex 桌面 App 和认证目录，点击「保存当前账号」。
2. 通过「浏览器添加账号」登录另一个自己的账号。
3. 暂停 Codex 中的任务，选择目标账号，确认「切换并重开」。
4. 在重开的 Codex 中核对账号，然后回到工具确认；遇到问题可恢复上次认证。

添加账号不会立即切换。邮箱默认隐藏；备注仍可见，公开截图请使用演示模式。

[完整使用指南](docs/USAGE.md) · [安全与数据](SECURITY.md) · [反馈问题](https://github.com/taogezhizun/codex-accounts-mac/issues)

<details>
<summary>兼容性与验证范围</summary>

支持 ChatGPT 登录和文件认证；暂不支持 API Key、系统 keyring 认证或受管理的认证策略。需要已安装官方 Codex 桌面 App，认证目录必须与它一致。共用同一认证目录的其他客户端可能受到切换影响。

Apple Silicon 已完成本地构建与演示检查；Intel 已构建，尚待实机验收。测试与打包结果见验收记录。真实账号登录、自动额度刷新、桌面切换与恢复仍需本机验收；不将“认证文件已替换”视为“桌面登录已验证”。详见[验收清单](docs/VALIDATION.md)。

</details>

## 开发

```sh
./scripts/build-app.sh
swift test
python3 scripts/privacy-check.py
```

需要 Swift 5.9+ / Xcode 15+。构建产物位于 `dist/`，自用无需付费 Apple Developer 账号。

演示预览：退出正在运行的工具后，执行 `open "dist/Codex Accounts.app" --args --demo`。演示模式不读取真实账号；不要将真实账号截图提交到仓库。

[架构设计](docs/DESIGN.md) · [UI 设计](docs/UI-DESIGN.md) · [DMG 打包与签名发布](docs/UPDATES.md)

## 作者

由 [taogezhizun](https://github.com/taogezhizun) 开发与维护。欢迎通过 [Issues](https://github.com/taogezhizun/codex-accounts-mac/issues) 提出建议。

## 致谢与许可

本项目的多账号管理理念受到 [cjg1995/codex-account-switcher](https://github.com/cjg1995/codex-account-switcher) 启发。感谢原作者。本项目面向 macOS 独立开发，与 OpenAI 及原项目作者无隶属或背书关系。

该项目的公开实现曾用于评估可移植性；本仓库根据功能需求与官方协议重新实现，没有复制或逐行翻译其源代码，也没有使用其图标、截图或文档。上游在 2026-09-10 核查时未声明许可证，因此这里的 MIT 许可仅覆盖本仓库的原创内容，不授予上游代码的使用权。

本项目采用 [MIT License](LICENSE)。接口依据：[OpenAI Authentication](https://learn.chatgpt.com/docs/auth)、[Codex App Server](https://learn.chatgpt.com/docs/app-server)；UI 使用 Apple SwiftUI / AppKit；应用更新使用 [Sparkle 2.9.6](https://sparkle-project.org)，保留其[完整许可证](docs/licenses/Sparkle.txt)。自动刷新节奏与缓存反馈参考 [OpenUsage](https://github.com/robinebers/openusage/blob/main/docs/refreshing.md)，未复制其实现或素材。

0.4.0 的紧凑菜单、当前行高亮与文件存储思路参考 [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)。实现独立编写，未复制其源码或素材；上游采用 MIT 许可。

维护者签名和发布步骤见 [更新与发布](docs/UPDATES.md)。
