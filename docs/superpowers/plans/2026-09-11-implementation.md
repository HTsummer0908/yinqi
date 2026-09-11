# Yinqi 分阶段实施计划

**Goal:** 按既有设计先验证真实系统采集和窗口兼容，再进入频谱与完整交互。
**Architecture:** Swift/AppKit 单进程；Core Audio Tap → 预分配 SPSC PCM 队列 → DSP → Metal。主线程管理窗口，串行队列管理音频资源。
**Tech Stack:** macOS 26+、Swift 5 稳定语言模式、C11 atomics、系统框架，无第三方依赖。
**Spec:** ../../../2026-09-11-macos-spectrum-functional-architecture.md

用户已授权按该设计实施；不重新讨论方向，不提交或发布。当前目录无 Git，不另建会隔离交付文件的工作树。

## 实际执行状态（2026-09-11）

A 的真实音频、普通透明覆盖、Chrome 原生全屏和用户穿透/焦点确认已有证据。B/C 源码已实现并经自动化/独立审查，最终构建成功；新构建系统重授权未完成，最终整链路仍待验。D 已交付构建说明与 F01–F15 测试矩阵，性能/其他实机项明确未验证。以下未勾项表示尚无完整验收证据，不代表没有源码。

## A — 核心风险门禁
- [x] C 预分配有界 PCM 队列：先测试交错/非交错、溢出、不覆盖读取、清空。
- [x] Sources/Yinqi/AudioCaptureService.swift：创建私有非静音全局 tap，排除自身；读取格式；建立 aggregate 和 C IOProc；逆序释放；可见错误。
- [x] Sources/Yinqi/OverlayWindowController.swift：非激活透明穿透 panel；公开 collectionBehavior；静态、明确标记的验证标尺。
- [x] Sources/Yinqi/main.swift：菜单栏、首次说明、手动启用、停止、重试、诊断窗口。
- [x] scripts/build.sh + Resources/Info.plist：命令行构建与 ad-hoc 签名 .app；声明系统音频用途。
- [ ] 在真实 .app 中测试授权、已知外部声音、原输出、普通应用/Spaces/全屏/点击与焦点；记录环境和证据。
- [ ] 核心链路未通过则定位；需要用户完成系统权限或肉眼听觉验证时明确记录门禁，不扩展外观。

## B — A 通过后执行
- [x] SpectrumAnalyzer：8192 Hann FFT，hop 1024，独立声道功率平均，对数加权频段、低频插值、dt 平滑；合成音频自动测试。
- [ ] Metal renderer + 最新帧快照；64 柱、静音滞回/淡出/暂停绘制、有声恢复。
- [ ] 协调显示/隐藏、设备与格式重建、有限重试、睡眠/锁屏恢复。

## C — B 通过后执行
- [ ] 编辑拖动/四边缩放/吸附/屏幕恢复；几何边界测试。
- [x] SwiftUI 设置、16/32/64/128、方向、纯色/渐变/LED。
- [x] schema 1 JSON 原子保存、防抖、校验、损坏回退提示；配置自动测试。

## D — 验收
- [x] docs/testing/RESULTS.md 逐项 F01–F15，区分通过/失败/未验证/未实现。
- [x] README.md 构建、启动、权限、清理说明与交付范围。
- [ ] 可用工具范围内 Release 性能；无法完成 Instruments 或其他系统测试明确列出。
