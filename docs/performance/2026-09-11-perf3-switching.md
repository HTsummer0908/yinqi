# perf3：后端切换与 Metal 参数缓存

日期：2026-09-11。分支 `perf/memory-cpu-optimization`，1.0.1 build 29；不修改已验证的 1.0.0 发布包。

## 改动

- 动画页提供 Core Animation / Metal 选择，默认 Core Animation。即时切换，同一 NSPanel 保持布局、编辑状态和截图共享属性。动画/峰值状态短暂重置。
- 切换先创建替代后端，再停止旧时钟、清空回调、移除旧视图；Metal 归还 drawable。创建失败保留旧后端并恢复设置选择。
- 后端选择持久化，支持配置导入导出。旧配置补默认值，未知后端回退 Core Animation。
- Metal 布局、配色、样式参数按设置、画布尺寸、柱数变化缓存；逐帧只改不透明度及频谱/峰值数据。移除逐帧方向字典构建，沿用 setFragmentBytes。
- 暂未引入额外 compute pass、GPU 动画状态、环形缓冲或新的显示时钟。这些需要独立收益验证。

## CPU 采样

M4 / macOS 27 Beta，优化编译并带符号，Time Profiler 各 10 秒。独立 64 柱动态渐变+峰值标记探针，无真实音频、无设置窗口。排除前 3 秒启动样本，统计调用栈包含指定方法的样本数：

| 样本 | 优化前 | 优化后 |
|---|---:|---:|
| 全部样本 | 569 | 580 |
| SpectrumRenderer.draw(in:) | 149 | 131 |
| SpectrumRenderer.encodeBars(using:size:) | 22 | 6 |

方向上与减少重复参数计算一致，但只有一次短时采样，绝对数量少，不能据此声称稳定 CPU 降幅或能耗改善。优化前叶子样本包括 iokit_user_client_trap、mach_msg2_trap 等系统调用；不应把绘制调用链全部归因于柱条 shader。

两次 xctrace 均报告录制完成并生成可导出的 time-profile 表，命令退出码为 54；因此保留此采集异常说明，不将它当作无异常完成的测量。完整 trace 和 XML 仅留在忽略目录 output/performance，不随仓库或发布包分发。

## 切换内存

同一独立进程，64 柱动态渐变与峰值标记，保持相同窗口，每阶段运行约 5 秒后用 vmmap -summary 读取 Physical footprint：

| 阶段 | 内存 |
|---|---:|
| 初始 Core Animation | 15.4 MB |
| 切到 Metal | 75.0 MB |
| 切回 Core Animation | 22.3 MB |

自动测试另用弱引用确认旧渲染器对象已释放。切回后大部分内存回收，但并未回到初始值，仍有约 6 MB IOSurface 区域；不能承诺切换后清除所有图形缓存。这不是完整应用的真实播放内存，也不是所有场景低于 50 MB 的保证。

## 构建与验证

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/test-rendering.sh
```

本次通过：原子配置保存/重载、配置往返导入导出及失败回滚、未知后端回退、FIFO/溢出/并发与消毒器、DSP；切换面板身份和旧对象释放；实际 Metal shader 像素、声道布局、渐变、圆角、方向；图层像素、LED、峰值、隐藏与恢复。

包：build/performance-switching/Yinqi.app、dist/Yinqi-1.0.1-perf3-arm64.zip。arm64 / macOS 26+，临时签名，未公证。

## 未验证

- 完整应用持续真实音频播放、长期反复切换后的稳态内存及泄漏。
- 用户手动操作设置选择、不同机器、高刷/多显示器及休眠恢复。
- 本版切换后的跨应用全屏、截图排除与鼠标穿透实机验收。
- WindowServer、系统总 GPU/能耗、Metal System Trace 和 Power Profiler；未将低应用内存等同于低系统总资源。
- Metal 创建失败的真实设备故障注入；错误路径目前仅代码审查。
