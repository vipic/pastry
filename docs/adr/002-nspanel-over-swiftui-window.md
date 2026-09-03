# ADR-002: NSPanel Overlay vs SwiftUI Window

## 状态
已采纳

## 背景
Pastry 需要一个全局浮层显示剪贴板历史。该浮层需：
- 不主动激活 Pastry 应用，同时允许面板成为 key window 接收键盘输入
- 可拖拽到其他应用
- 支持原生 Cocoa 事件（右键菜单、beginDragThrough）
- 带模糊半透明材质背景

考察选项：
- **SwiftUI `Window`** — SwiftUI 原生窗口
- **SwiftUI `Menu`** — 系统菜单（纯 SwiftUI）
- **`NSPanel`** — AppKit 浮动面板

## 决策
使用 AppKit `NSPanel`（`.nonactivatingPanel` 风格）作为宿主容器，内部嵌入 SwiftUI 视图。

## 理由
- **非激活面板** — `.nonactivatingPanel` 区分应用激活与窗口 key 状态；当前面板允许成为 key 并接收键盘输入，不能把它描述成“不抢 key”
- **完整 AppKit 事件链** — 右键菜单（NSMenu）、拖拽到其他应用（beginDragThrough）依赖 AppKit 事件系统
- **原生材质** — `NSVisualEffectView` 提供系统级模糊半透明效果，与 macOS 26 HUD 风格一致
- **精细生命周期控制** — `orderFront/orderOut` 精确控制显隐，避开了 SwiftUI Window 的 `onAppear/onDisappear` 不确定性
- **Esc 键链** — 可通过 `cancelOperation:` 实现层级关闭（预览 popover → 搜索栏 → 面板）

## 代价
- SwiftUI 视图通过 `NSHostingView` 桥接到 NSPanel 内容视图，增加一层间接
- 需要手动管理 SwiftUI 和 AppKit 之间的布局约束和尺寸计算
- 无法使用 SwiftUI 的 `.windowStyle()` 等修饰符

## 备选方案
- **SwiftUI Window** — 项目未采用；所需的非激活面板、层级和事件控制直接由 AppKit 承担，不把 key window 与应用激活混为一谈
- **SwiftUI Menu** — 无法自定义布局，无限滚动、搜索栏、多选等交互不可行

2026-09-03 术语校正：以上区分依据当前 [OverlayPanelManager](../../Sources/Pastry/UI/OverlayPanelManager.swift)；当前生命周期和约束见[浮层地图](../architecture/overlay.md)。
