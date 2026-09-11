# perf2：Core Animation 渲染对照

实验版本 1.0.1 build 28；性能分支，不替换 main 或 1.0.0 Release。

## 实现

增加 SpectrumRendering 接口和 LayerSpectrumRenderer。性能版默认使用图层后端；设置环境变量 YINQI_RENDERER=metal 可选择保留的 Metal 后端进行对照。

图层后端使用固定数量的 CAShapeLayer、CAGradientLayer 和 LED 遮罩，关闭隐式动画，主线程计时器按目标帧率更新。保留双声道排序、渐变、LED、顶部/底部圆角、四方向、峰值标记、透明度、静音暂停、编辑及窗口共享策略。静音由现有 10 Hz 唤醒轮询处理。计时器不是显示同步保证，实际高刷表现须补验。

## 测量

M4 / macOS 27 Beta，独立进程运行约 5 秒后 vmmap。默认屏幕安全区 70% 长度、96 pt 厚度、64 柱、60 FPS。数据是合成频谱，没有音频或设置窗口。

| 场景 | Physical footprint |
|---|---:|
| 完整 Metal 后端，固定频谱 | 74.7 MB |
| 完整图层后端，固定频谱 | 15.2 MB |
| Metal，动态渐变+峰值标记 | 74.6 MB |
| 图层，动态渐变+峰值标记 | 15.4 MB |
| 图层，动态 LED+峰值标记 | 15.3 MB |

ps 的瞬时 CPU 样本分别约 0.8%、0.5%、0.4%（最后三项），不作为稳定 CPU/能耗基准。未测 WindowServer 的额外开销，因此不能推断系统总资源消耗同幅下降。

完整应用短时启动快照约 20.5 MB，但未确认真实音频驱动状态，不把它算作实际播放验收；它也不是打开过所有设置后的稳态结果。

## 验证

构建、签名、核心/DSP/设置测试和既有 Metal 回归通过。新增 LayerRendererTests：实际层合成像素验证四方向、零间距、水平/垂直渐变、LED、峰值颜色、隐藏及恢复；路径测试覆盖声道内倒序与基部圆角。

仍需用户实际音频、所有常用外观、长期内存、设置打开关闭、截图隐藏、跨应用全屏、屏幕切换/高刷新率验收。未承诺所有场景低于 50 MB。

测试包：build/performance-layers/Yinqi.app、dist/Yinqi-1.0.1-perf2-arm64.zip。原 1.0.0 和 perf1 包保留。
