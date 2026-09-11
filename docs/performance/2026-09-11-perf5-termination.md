# perf5：立即重启时应用不退出

2026-09-11，1.0.1 build 31，性能分支实验包。

## 根因与证据

重启弹窗从 DispatchQueue.main.async 进入，在该主队列任务尚未返回时调用 NSApp.terminate。applicationShouldTerminate 返回 terminateLater，AppKit 进入嵌套运行循环等待确认。AudioCaptureService.stop 原先将停止完成回调再次投递到 DispatchQueue.main；主队列无法重入，确认无法执行，应用不退出。重启助手一直等待旧 PID，用户手动退出后助手才能继续。因此不由 Applications 安装位置导致。

先用仅含 AppKit 和工作队列的最小程序复现：日志依次到 terminate requested、should terminate、worker finished，5 秒仍不退出。再用生产 AudioCaptureService.stop（不启动音频）复现同一超时。将完成回调改为 RunLoop.main.perform，指定 default/modalPanel/eventTracking 模式后，确认送达并正常退出。

## 修复

仅调整停止完成回调的主线程投递机制，保留控制队列上先停止 HAL、释放资源，再回主线程确认退出的顺序。不绕过退出委托，不强制 kill，不靠延迟掩盖竞态。运行循环投递不依赖被嵌套阻塞的主队列任务返回。

## 验证

- `bash scripts/test-termination.sh`：修复前 dispatch 场景超时；修复后 dispatch 和普通计时器事件场景均完成真实 stop 回调及 AppKit 退出。
- 隔离应用完整重启：使用生产停止接口与生产重启助手，旧 PID 947 自动退出后新 PID 950 启动并正常退出。含空格与 `$` 的路径正确处理。无系统音频权限请求，不触碰真实用户配置。
- `bash scripts/build.sh`：优化构建与临时签名通过。
- 打包后签名验证与 ZIP 完整性检查通过。

上一版测试只覆盖旧 PID 消失后重开，未覆盖主队列触发的真实 AppKit 退出链路，本版补上回归脚本。

## 边界

完整用户界面点击弹窗与正在播放的真实 HAL 停止仍需用户实机确认。未模拟设备驱动停止卡住、LaunchServices 拒绝启动。此次修复不增加自动更新功能；未来可复用正常退出路径，但更新文件替换、验证及恢复需要独立验收。

包：build/performance-restart/Yinqi.app、dist/Yinqi-1.0.1-perf5-arm64.zip。1.0.0 发布包、GitHub 私有状态保持不变。
