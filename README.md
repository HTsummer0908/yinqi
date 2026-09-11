# 音栖 Yinqi

让声音栖于桌面。轻量的原生 macOS 系统音频频谱工具。

**版本：1.0.0** · 仓库目前为私有，公开将在单独确认后进行。

## 功能

- 实时分析系统播放音频，支持合并声道、左右声道与对称频率排列。
- 透明悬浮、鼠标穿透；支持四边停靠、铺满、拖动和缩放。
- 纯色、渐变、复古 LED；可调柱数、间距、圆角、透明度与峰值标记。
- 普通模式提供语义档位滑块；关于页开启高级设置后可精确输入。
- 帧率预设 10/15/30/60/120，自定义 10–1000，或跟随屏幕最高刷新率；静音后淡出并暂停持续绘制。
- 菜单栏常驻，可选 Dock 显示；诊断仅在主动打开时运行。
- 配置 JSON 导入与导出，方便备份和跨电脑分享。
- 可选“屏幕截图时隐藏”，同时作用于频谱窗和编辑工具栏。

## 系统要求与安装

部署目标为 **macOS 26.0+**，当前构建产物仅支持 **Apple Silicon（arm64）**。
已验证开发环境：Apple M4、macOS 27.0 Beta（26A428）。macOS 26 和 Intel 尚未验证，不提供 Intel 安装包。

从仓库 Releases 下载 `Yinqi-1.0.0-arm64.zip`，解压后可将 `Yinqi.app` 放入“应用程序”，双击启动。
当前包使用 **ad-hoc 签名，未进行 Developer ID 签名与 Apple 公证**；其他电脑可能遇到 Gatekeeper 拦截，尚未验证跨机安装流程。校验 SHA-256 只能验证文件一致性，不替代开发者签名。

首次启动在设置中开启“启用频谱”，按系统提示允许系统音频访问，然后从其他应用播放声音。关闭设置窗口不会退出应用；菜单栏可重新打开设置。

## 使用

- **常规**：启用频谱、Dock 显示、截图隐藏，以及上/下/左/右四边铺满。
- **频谱**：声道、柱数、频率排列与间距；独立的“频率范围”分组中，向右拖动表示缩减更多。
- **动画**：帧率、音量灵敏度（−24～+24 dB）、回落速度。
- **外观**：柱条样式、颜色和峰值标记；关闭峰值标记时隐藏其配置。
- **位置**：停靠、生长方向、边缘间距与编辑开关。编辑时可拖动主体、四边与四角，完成后锁定恢复穿透。
- **关于**：高级设置、项目信息和配置导入导出。info 图标悬停 800 ms 展示说明。

导出的 JSON 包含版本标识及设置，不包含原电脑屏幕标识、启动记录和频谱启停状态。导入后立即应用；非法文件或保存失败保留原设置。

设置文件：`~/Library/Application Support/local.xinfei.yinqi/settings.json`。旧版设置可自动迁移；不会删除旧文件或覆盖已有新设置。

## 从源码构建

需要 Apple 工具链及完整 Xcode（用于编译原生分层图标）。本机使用 Swift 6.4、Swift 5 语言模式、Xcode 27 Beta / Icon Composer 2；其他版本工具链尚未验证。

```sh
# 在仓库根目录执行，目录名称和位置可自由更改
bash scripts/test.sh
bash scripts/build.sh
open build/Yinqi.app
```

脚本会寻找常见 Xcode 路径，也可显式指定：

```sh
ICON_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" bash scripts/build.sh
```

输出为 `build/Yinqi.app`。无第三方运行依赖或 SwiftPM 下载；使用 Core Audio、Accelerate、AppKit、SwiftUI、MetalKit 和 C11 原子队列。

原生窗口与 Metal 像素回归需要图形会话，会短暂显示测试窗口：

```sh
bash scripts/test-rendering.sh
```

## 隐私与兼容范围

音频仅在本机实时分析，不录制、不保存、不上传。不自动检查更新，不发送遥测。点击 GitHub 链接时由浏览器访问网站。

截图隐藏使用 AppKit 的窗口共享属性，用户已确认当前环境截图生效；不承诺录屏排除。帧率受屏幕和系统调度限制，目标数值不代表实际性能保证。

详见 [1.0.0 验证记录](docs/testing/RESULTS-1.0.0.md) 和 [发布说明](docs/releases/1.0.0.md)。历史测试与设计见 [0.3 测试报告](docs/testing/RESULTS-0.3.md)、[设计文档](2026-09-11-macos-spectrum-functional-architecture.md)。

## 开发与项目状态

开发者：[HTsummer0908](https://github.com/HTsummer0908)。仓库：[yinqi](https://github.com/HTsummer0908/yinqi)。

主要代码：`Sources/Realtime`（实时队列）、`Sources/Yinqi`（采集、分析、渲染和 UI）。图标源文件位于 `Resources/Branding`。
截图隐藏实现参考 [LyricsX](https://github.com/MxIris-LyricsX-Project/LyricsX) 的公开 AppKit 窗口共享策略。

开源许可证待确认；私有准备阶段不授予额外开源许可。公开仓库前应完成许可证与分发方式确认。
