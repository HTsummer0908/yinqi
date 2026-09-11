# 菜单栏图标

2026-09-11。20 × 18 pt，六柱高低错落，柱宽 2 pt，间距 1 pt，顶部圆角 0.5 pt。去掉底色、渐变与基线，以保证小尺寸辨识度。

SVG 为编辑源，PDF 为透明矢量资源。接入时使用 NSImage 加载 PDF，设置 size 为 20 × 18，isTemplate = true，然后赋给 NSStatusBarButton.image 并清空原文字。

menu-preview.png 左浅右深，上方放大 6 倍，下方原尺寸，仅为黑白外观示意，不是系统菜单栏实测截图。尚未接入应用。
