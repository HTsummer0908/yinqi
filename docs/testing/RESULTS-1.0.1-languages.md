# 多语言测试版：1.0.1 build 32

日期：2026-09-11。性能分支延续，未合并 main、未推送或修改 GitHub 发布状态。

## 改动范围

- 8 套独立资源：zh-Hans、zh-HK、zh-TW、en、fr、de、ja、ko，各 209 条文案。覆盖设置分类/选项、帮助、菜单、重启弹窗、诊断、音频及渲染错误、工具条辅助说明。
- 常规页语言下拉框；保存的是稳定语言代码，system 为默认值。按系统首个支持语言匹配，不支持时回退 en；港澳与台湾脚本/地区别名测试覆盖。
- 启动时固定应用语言，并使用进程内 volatile AppleLanguages 对齐系统控件；不写系统全局或持久 AppleLanguages。手动变更和配置导入在重启后生效，待重启状态不导出。
- 中英文应用名称和音频权限说明随 InfoPlist.strings 打包；可执行文件和包文件名仍为 Yinqi。
- 调整日语侧栏以及德语、日语快速布局文字；缩短导入导出按钮，减少小窗口截断。
- 渲染成功状态的译文仅初始化时解析，避免在每一绘制帧查询语言资源。

## 已执行验证

```sh
bash scripts/build.sh
bash scripts/test-localization.sh
bash scripts/test.sh
bash scripts/test-rendering.sh
bash scripts/test-termination.sh
```

- 全部 8 套资源键集合、209 条译文非空、格式占位符数量、静态 L 查找覆盖检查通过。
- 显式语言覆盖系统偏好、香港/澳门/台湾及脚本变体、法语加拿大、德语奥地利、日韩地区、未支持语言列表、空列表回退通过。
- 设置默认值、未知语言、保存重载、导入导出、待重启和改回当前选择通过。
- 独立原生 .app 进程的 bootstrap 测试：8 种语言均为 Bundle 首选项；CFBundleDisplayName 中文音栖/音棲、其他 Yinqi；权限文案与所选语言一致。
- FIFO/并发消毒器、DSP、设置回归、Metal 和图层像素、真实停止接口与完整退出/重开回归通过；无真实音频权限请求。
- 隔离 SwiftUI 布局探针在 681×560 内容区域渲染 8 种语言的 6 个分类，使用临时设置并仅替换测试视图初始分类；未启动真实采集。人工查看德语和日语重点页面及港澳常规截图，修正已发现的按钮截断/侧栏换行。长页面使用纵向滚动；fittingSize 为理想尺寸，不代表最小窗口宽度要求。探针应用图标/版本占位不作为生产图标验收。

## 未验证范围

- 全部译文尚未经各语言母语审校，尤其区域术语及系统底层错误的自然语言表达。
- 未实际切换 macOS 系统语言或 Finder 全局状态；系统名称缓存、手动改过包名、不同地区系统显示需实机确认。原生 Bundle 本地化已测，不等同于 Finder 所有入口的展示验证。
- 用户实际操作语言下拉框、全部系统权限/文件/颜色弹窗、VoiceOver 朗读及长时间音频播放未本轮验收。
- 性能未重新测量；本轮没有新增周期性语言任务或网络请求，不承诺长期内存数值。

## 交付

`build/Yinqi.app`、`build/multilingual/Yinqi.app`、`dist/Yinqi-1.0.1-languages-arm64.zip`。

macOS 26+ / Apple Silicon；临时签名、未公证。既有 1.0.0 及性能测试 ZIP 保留。

名称实现依据 [Apple CFBundleDisplayName 文档](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)：本地化键同时提供 CFBundleDisplayName 与 CFBundleName，保留 Yinqi.app 与基础显示名称一致。
