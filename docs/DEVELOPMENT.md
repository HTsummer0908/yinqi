# 音栖开发文档

[中文](DEVELOPMENT.md) | [English](DEVELOPMENT.en.md) | [返回产品首页](../README.md)

本文集中保存源码构建、项目结构、本地化、配置、测试和兼容边界等技术信息。面向普通用户的产品介绍与下载入口见仓库根目录 README。

## 开发环境

- 部署目标：macOS 26.0+
- 架构：Apple Silicon（arm64）
- 已验证：Apple M4、macOS 27.0 Beta（26A428）
- 工具链：Swift 6.4、Swift 5 语言模式、Xcode 27 Beta、Icon Composer 2

完整 Xcode 用于编译原生分层图标。其他系统、Intel 架构及工具链版本尚未验证。

## 构建

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Yinqi.app
```

产物为 `build/Yinqi.app`。构建脚本会寻找常见 Xcode 路径，也可显式指定：

```sh
ICON_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" bash scripts/build.sh
```

项目没有第三方运行依赖或 SwiftPM 下载，主要使用 Core Audio、Accelerate、AppKit、SwiftUI、MetalKit 和 C11 原子队列。

## 源码结构

- `Sources/Realtime`：实时音频单生产者/单消费者队列。
- `Sources/Yinqi`：系统音频采集、频谱分析、渲染、设置和应用界面。
- `Resources`：Info.plist、本地化资源和品牌图标。
- `Tests`：实时队列、DSP、配置、本地化、渲染及退出测试。
- `scripts`：构建与测试入口。

截图隐藏使用 AppKit 的窗口共享属性，其策略参考 [LyricsX](https://github.com/MxIris-LyricsX-Project/LyricsX)。

## 配置与生命周期

设置文件位于 `~/Library/Application Support/local.xinfei.yinqi/settings.json`。旧配置自动迁移，不删除旧文件，也不覆盖已存在的新设置。

导出的 JSON 包含版本标识及可移植设置，不包含屏幕标识、启动记录和频谱启停状态。导入失败、非法文件或保存失败时保留原设置。语言或渲染方式变更需要重启。

应用以菜单栏为主要入口，可选显示 Dock 图标。诊断仅在用户主动打开窗口时运行；关闭设置窗口不会退出应用。

## 渲染与性能

Core Animation 是默认渲染方式，Metal 可在设置中选择。更改渲染方式后通过“立即重启 / 稍后重启”流程生效，避免进程内热切换残留。

帧率提供 10/15/30/60/120 预设、自定义 10–1000，或跟随屏幕最高刷新率。目标帧率仍受显示器和系统调度限制。静音后频谱淡出并暂停持续绘制。

详细测量与历史优化记录见 [`docs/performance`](performance)。独立探针结果不等于完整应用长期播放表现。

## 本地化

支持 `zh-Hans`、`zh-HK`、`zh-TW`、`en`、`fr`、`de`、`ja` 和 `ko`。默认跟随系统首个受支持语言，无匹配时使用英语。

- 界面翻译：`Resources/<语言>.lproj/Localizable.strings`
- 应用名称和权限说明：同目录 `InfoPlist.strings`
- 支持语言注册：`AppLanguage.codes` 和 `CFBundleLocalizations`

新增或修改译文时须保留 `%@` 参数，并运行 `bash scripts/test-localization.sh`。

## 测试

核心测试：

```sh
bash scripts/test.sh
```

需要图形会话的原生窗口与像素测试会短暂显示窗口：

```sh
bash scripts/test-rendering.sh
bash scripts/test-localization.sh
bash scripts/test-termination.sh
```

历史测试记录见 [`docs/testing`](testing)。静态或合成测试不能替代所有系统版本、显示器与长期播放场景的实机验证。

## 隐私与分发边界

系统音频只在本机实时分析，不录制、不保存、不上传。应用不自动检查更新或发送遥测；只有用户点击项目链接时才访问网络。

当前安装包采用 ad-hoc 签名，未进行 Developer ID 签名或 Apple 公证。SHA-256 只能验证文件一致性，不能替代开发者签名。截图隐藏已在当前环境确认，不承诺所有录屏工具均能排除窗口。

项目采用 [Mozilla Public License 2.0](../LICENSE)。许可证摘要不替代正式文本。

## 发布资料

- 当前发布说明：[`docs/releases/1.1.0.md`](releases/1.1.0.md)
- 历史发布说明：[`docs/releases`](releases)
- 设置预设设计：[`docs/design/settings-presets.md`](design/settings-presets.md)
- 功能架构记录：[`2026-09-11-macos-spectrum-functional-architecture.md`](../2026-09-11-macos-spectrum-functional-architecture.md)
