# 音栖 Yinqi

[简体中文](README.md) | [English](README.en.md)

<p align="center">
  <img src="Resources/Branding/v2/previews/yinqi-preview.svg.png" width="128" alt="音栖 Yinqi 应用图标">
</p>

让声音栖于桌面。轻量的原生 macOS 系统音频频谱工具。

**最新稳定版：1.0.1 · build 32**

`main` 分支还包含尚未发布的 8 套内置主题预设及预设后二次调整状态；Releases 中的 1.0.1 安装包暂不包含该功能。

## 功能

- 实时分析系统播放音频，支持合并声道、左右声道与对称频率排列。
- 透明悬浮、鼠标穿透；支持四边停靠、铺满、拖动和缩放。
- 纯色、渐变、复古 LED；可调柱数、间距、圆角、透明度与峰值标记。
- `main` 分支提供 8 套内置主题预设，选择后仍可继续调整，并可恢复到该预设的初始参数。
- 普通模式提供语义档位滑块；关于页开启高级设置后可精确输入。
- 帧率预设 10/15/30/60/120，自定义 10–1000，或跟随屏幕最高刷新率；静音后淡出并暂停持续绘制。
- 菜单栏常驻，可选 Dock 显示；诊断仅在主动打开时运行。
- 配置 JSON 导入与导出，方便备份和跨电脑分享。
- 可选“屏幕截图时隐藏”，同时作用于频谱窗和编辑工具栏。

## 界面预览

| 桌面频谱效果 | 内置主题预设 |
| --- | --- |
| ![桌面频谱效果截图占位](docs/images/placeholder-desktop-spectrum.svg) | ![内置主题预设截图占位](docs/images/placeholder-theme-presets.svg) |
| 待补充：`desktop-spectrum.png` | 待补充：`theme-presets.png` |

| 外观二次调整 | 布局与编辑 |
| --- | --- |
| ![外观二次调整截图占位](docs/images/placeholder-appearance-controls.svg) | ![布局与编辑截图占位](docs/images/placeholder-layout-editing.svg) |
| 待补充：`appearance-controls.png` | 待补充：`layout-editing.png` |

## 系统要求与安装

部署目标为 **macOS 26.0+**，当前构建产物仅支持 **Apple Silicon（arm64）**。
已验证开发环境：Apple M4、macOS 27.0 Beta（26A428）。macOS 26 和 Intel 尚未验证，不提供 Intel 安装包。

从仓库 Releases 下载 `Yinqi-1.0.1-arm64.zip`，解压后可将 `Yinqi.app` 放入“应用程序”，双击启动。
当前包使用 **ad-hoc 签名，未进行 Developer ID 签名与 Apple 公证**；其他电脑可能遇到 Gatekeeper 拦截，尚未验证跨机安装流程。校验 SHA-256 只能验证文件一致性，不替代开发者签名。

首次启动在设置中开启“启用频谱”，按系统提示允许系统音频访问，然后从其他应用播放声音。关闭设置窗口不会退出应用；菜单栏可重新打开设置。

## 使用

- **常规**：语言、启用频谱、Dock 显示、截图隐藏，以及上/下/左/右四边铺满。
- **频谱**：声道、柱数、频率排列与间距；独立的“频率范围”分组中，向右拖动表示缩减更多。
- **动画**：渲染方式、帧率、音量灵敏度（−24～+24 dB）、回落速度。
- **外观**：柱条样式、颜色和峰值标记；关闭峰值标记时隐藏其配置。
- **位置**：停靠、生长方向、边缘间距与编辑开关。编辑时可拖动主体、四边与四角，完成后锁定恢复穿透。
- **关于**：高级设置、项目信息和配置导入导出。info 图标悬停 800 ms 展示说明。

导出的 JSON 包含版本标识及设置，不包含原电脑屏幕标识、启动记录和频谱启停状态。导入后应用外观等设置；语言或渲染方式变更需重启。非法文件或保存失败保留原设置。

设置文件：`~/Library/Application Support/local.xinfei.yinqi/settings.json`。旧版设置可自动迁移；不会删除旧文件或覆盖已有新设置。

## 从源码构建

需要 Apple 工具链及完整 Xcode（用于编译原生分层图标）。本机使用 Swift 6.4、Swift 5 语言模式、Xcode 27 Beta / Icon Composer 2；其他版本工具链尚未验证。

```sh
# 在仓库根目录执行，目录名称和位置可自由更改
bash scripts/test.sh
bash scripts/build.sh
open build/Yinqi.app
```

脚本会寻找常见 Xcode 路径，也可显式指定。当前已使用外置硬盘中的 Xcode 27 Beta 完成全量构建验证：

```sh
ICON_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" bash scripts/build.sh
```

输出为 `build/Yinqi.app`。无第三方运行依赖或 SwiftPM 下载；使用 Core Audio、Accelerate、AppKit、SwiftUI、MetalKit 和 C11 原子队列。

原生窗口与 Metal 像素回归需要图形会话，会短暂显示测试窗口：

```sh
bash scripts/test-rendering.sh
bash scripts/test-localization.sh
bash scripts/test-termination.sh
```

## 界面语言与应用名称

“常规 → 语言”提供跟随系统、简体中文、繁體中文（港澳）、繁體中文（台灣）、English、Français、Deutsch、日本語和 한국어。初始及旧配置默认跟随系统的语言偏好列表，匹配首个支持的语言；无匹配时使用英文。港澳繁体与台湾繁体分别提供资源。

手动选择或导入语言设置后需重启，使用现有“立即重启 / 稍后重启”流程；不更改系统全局语言。配置导入导出包含语言选择。

安装包统一保留 `Yinqi.app`。中文显示名称为“音栖 / 音棲”，其余语言显示“Yinqi”。Finder 等系统位置依系统的本地化规则显示名称，不保证应用内更改语言立即刷新 Finder 的名称或缓存。

翻译资源位于 `Resources/<语言>.lproj/Localizable.strings`，名称和权限说明位于同目录 `InfoPlist.strings`。译文须保留 `%@` 参数；新增语言需同时注册 `AppLanguage.codes`、原文名称及 `CFBundleLocalizations`。构建后运行 `bash scripts/test-localization.sh` 检查覆盖、格式与原生 Bundle 行为。详细记录见 [多语言验证报告](docs/testing/RESULTS-1.0.1-languages.md)。

## 隐私与兼容范围

音频仅在本机实时分析，不录制、不保存、不上传。不自动检查更新，不发送遥测。点击 GitHub 链接时由浏览器访问网站。

截图隐藏使用 AppKit 的窗口共享属性，用户已确认当前环境截图生效；不承诺录屏排除。帧率受屏幕和系统调度限制，目标数值不代表实际性能保证。

当前版本见 [1.0.1 发布说明](docs/releases/1.0.1.md) 和 [多语言验证记录](docs/testing/RESULTS-1.0.1-languages.md)。此前版本见 [1.0.0 验证记录](docs/testing/RESULTS-1.0.0.md) 和 [发布说明](docs/releases/1.0.0.md)。历史测试与设计见 [0.3 测试报告](docs/testing/RESULTS-0.3.md)、[设计文档](2026-09-11-macos-spectrum-functional-architecture.md)。

## 开发与项目状态

开发者：[HTsummer0908](https://github.com/HTsummer0908)。仓库：[yinqi](https://github.com/HTsummer0908/yinqi)。

主要代码：`Sources/Realtime`（实时队列）、`Sources/Yinqi`（采集、分析、渲染和 UI）。图标源文件位于 `Resources/Branding`。
截图隐藏实现参考 [LyricsX](https://github.com/MxIris-LyricsX-Project/LyricsX) 的公开 AppKit 窗口共享策略。

## 开源许可证

本项目采用 [Mozilla Public License 2.0](LICENSE)。你可以使用、修改、分发及用于商业用途；如果对现有 MPL 文件进行修改并向外分发，需要公开这些修改文件的源码，并继续以 MPL-2.0 提供。与本项目组合的独立文件或模块不因此被要求采用 MPL。

本说明仅用于帮助理解，具体权利与义务以 [LICENSE](LICENSE) 正文为准。

## 渲染方式与性能

1.0.1 已整合性能分支与多语言功能。在“设置 → 动画 → 渲染方式”中选择 Core Animation 或 Metal，更改后提示“立即重启 / 稍后重启”，选择会保存并随配置导入导出。默认 Core Animation；原环境变量切换入口已由设置替代。重启前继续使用当前后端；新进程按保存的选择初始化，避免进程内热切换残留。

运行 `bash scripts/build.sh` 生成 `build/Yinqi.app`。发布包为 `dist/Yinqi-1.0.1-arm64.zip`。本次退出阻塞修复见 [perf5 报告](docs/performance/2026-09-11-perf5-termination.md)，重启机制见 [perf4 报告](docs/performance/2026-09-11-perf4-restart.md)，此前切换内存测量见 [perf3 报告](docs/performance/2026-09-11-perf3-switching.md)，此前的后端对照见 [perf2 报告](docs/performance/2026-09-11-perf2-layers.md)。
