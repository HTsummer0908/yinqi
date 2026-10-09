# 音栖 Yinqi

[简体中文](README.md) | [English](README.en.md)

<p align="center">
  <img src="Resources/Branding/v2/previews/yinqi-preview.svg.png" width="128" alt="音栖 Yinqi 应用图标">
</p>

<p align="center"><strong>让声音栖于桌面。</strong></p>
<p align="center">轻量、原生的 macOS 系统音频频谱悬浮工具。</p>

**最新版本：[1.1.0 · build 33](https://github.com/HTsummer0908/yinqi/releases/tag/v1.1.0)**

音栖实时分析 Mac 正在播放的系统音频，在桌面边缘呈现可定制的透明频谱。音频只在本机处理，不录制、不保存、不上传。

## 产品亮点

- 原生 macOS 透明悬浮层，日常使用时保持鼠标穿透。
- 支持顶部、底部、左侧和右侧停靠，可拖动、缩放和快速铺满。
- 提供纯色、渐变、复古 LED，以及 8 套可继续调整和恢复的主题预设。
- 支持合并、左、右声道与对称频率排列，柱条、峰值和动画均可调节。
- 提供 Core Animation 与 Metal 渲染方式，静音后自动淡出并暂停持续绘制。
- 支持简繁中文、英语、法语、德语、日语和韩语，并可导入、导出设置。

## 效果预览

| 桌面频谱效果 | 音乐播放效果 |
| --- | --- |
| ![音栖在 macOS 桌面底部显示频谱](docs/images/desktop-spectrum.jpg) | ![音栖配合音乐播放界面显示频谱](docs/images/music-playback.jpg) |
| 在桌面底部保持透明悬浮 | 随系统播放音频实时响应 |

| 外观二次调整 | 布局与编辑 |
| --- | --- |
| ![外观二次调整截图占位](docs/images/placeholder-appearance-controls.svg) | ![布局与编辑截图占位](docs/images/placeholder-layout-editing.svg) |
| 截图待补充 | 截图待补充 |

## 下载与使用

从 [GitHub Releases](https://github.com/HTsummer0908/yinqi/releases/latest) 下载 `Yinqi-1.1.0-arm64.zip`，解压后将 `Yinqi.app` 放入“应用程序”。

- 系统要求：**macOS 26.0+**、**Apple Silicon（arm64）**。
- 首次使用时，在设置中开启频谱，并按 macOS 提示允许系统音频访问。
- 当前安装包使用 ad-hoc 签名，尚未进行 Developer ID 签名和 Apple 公证；其他电脑可能遇到 Gatekeeper 拦截。

## 本地构建

需要完整 Xcode。已验证 Swift 6.4、Swift 5 语言模式和 Xcode 27 Beta。

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Yinqi.app
```

如果 Xcode 不在默认位置，可通过 `ICON_DEVELOPER_DIR` 指定其 `Contents/Developer` 目录。更完整的构建、架构、本地化和测试说明见 [开发文档](docs/DEVELOPMENT.md)。

## 更多资料

- [开发文档](docs/DEVELOPMENT.md) · [Development guide](docs/DEVELOPMENT.en.md)
- [1.1.0 发布说明](docs/releases/1.1.0.md)
- [测试记录](docs/testing) · [性能记录](docs/performance)
- [Mozilla Public License 2.0](LICENSE)
- [授权范围与第三方素材说明](LICENSING.md)
