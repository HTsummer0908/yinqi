# Instruments 与图形内存隔离实验

环境：M4 / macOS 27 Beta 26A428，性能分支 b5df3aa。2026-09-11。

## 采集过程

Developer Tools 授权已启用。发现同应用标识使 xctrace launch 启动了 /Applications 中的旧安装实例；分析副本改用独立 bundle id，并通过精确 PID 附加，15 秒 Allocations 采集成功。分析副本使用 -O -g 及 get-task-allow，仅在忽略目录，不用于发布。

Instruments 当前统计视图：Persistent 7.60 MiB、Total 13.71 MiB（附加后的堆/匿名 VM 记录，并非完整进程 footprint）。独立分析进程 vmmap footprint 94.5 MB，graphics 类别常驻 48.6 MB；它与先前现场快照启动条件不同，不可据此声称优化收益。

## 隔离实验

同一优化编译的最小程序，无音频采集和设置窗口。每个变体独立进程，运行约 3 秒后 vmmap，再退出。窗口使用默认设置与固定 64 柱合成输入；这不是实际系统音频证据。

| 场景 | Physical footprint |
|---|---:|
| 仅初始化 AppKit | 6241 KB |
| 创建渲染器和 pipeline，不显示窗口 | 8049 KB |
| 显示悬浮窗，不提交绘制 | 15.3 MB |
| 只绘制一次 | 20.5 MB |
| 持续绘制 | 74.7 MB |
| 持续绘制，2 个 drawable | 72.9 MB |
| 参数全部改用显式 MTLBuffer | 74.5 MB |
| 每次等待 GPU 完成再继续 | 74.7 MB |
| 持续清屏，不编码柱条 draw | 74.3 MB |

所有持续绘制变体的 owned unmapped (graphics) 常驻类别均约 48.6 MB。说明当前环境主要增量与持续 Metal 呈现路径相关，无法归因于 FFT、频谱 shader、参数 setBytes 或提交堆积。该类别并不能指明某个具体驱动内部对象；不据此断言 macOS 泄漏或所有系统均有此固定成本。

## 决定

以上无显著效果的实验不合入产品。保留 perf1；未达到 50 MB 目标。下一步可比较原生 Core Animation 图层绘制与当前 Metal 呈现的实际 footprint、CPU、画质和高帧率表现，验证后再决定是否替换。

原始 trace、内存快照和实验源码位于忽略目录 output/performance，trace 含本机进程环境信息，不作为仓库或 Release 附件上传。Instruments 窗口已打开成功的采集记录。正式 1.0.0 与远端未修改。
