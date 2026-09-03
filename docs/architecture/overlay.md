# 浮层与交互架构

> 核对日期：2026-09-03；源码基线：`a5691d8`。静态实现快照，非真实 UI 验收记录。相关选择见 [ADR-002：NSPanel Overlay vs SwiftUI Window](../adr/002-nspanel-over-swiftui-window.md)。

## 职责与边界

浮层模块负责在不切断目标应用工作流的前提下展示剪贴板历史，并协调键盘、搜索、筛选、选择、预览、拖拽和跨应用粘贴。持久化查询由 `StoreManager` 和 `DatabaseManager` 提供，剪贴板读写由 `ClipboardMonitor` 与 `PasteboardWriter` 提供；这些能力不属于浮层内部实现。

## 关键类型

- `ClipboardOverlayPanel`：允许成为 key 的非激活 `NSPanel`，统一处理 Esc、搜索快捷键和需要进入 AppKit responder chain 的事件。
- `OverlayPanelManager`：创建、复用、显示和隐藏面板，保存上一个前台应用，协调粘贴、拖拽穿透、Quick Look 和失焦收起。
- `OverlayView`：SwiftUI 内容树，组合工具栏、卡片带、搜索、筛选、确认层及生命周期通知。
- `OverlayKeyboardRouter`：本地键盘 monitor；按当前键盘所有者把事件交给搜索框、备注编辑器或卡片导航。
- `SelectionState`：与 UI 框架无关的单选、散选、区间选择和光标状态机。
- `OverlayInteractionModel`：把鼠标修饰键和点击转换为可测试的选择行为。

## 面板生命周期

源码入口：[OverlayPanelManager](../../Sources/Pastry/UI/OverlayPanelManager.swift)、[OverlayView](../../Sources/Pastry/UI/OverlayView.swift)、[键盘路由](../../Sources/Pastry/UI/OverlayKeyboardRouter.swift)、[选择状态机](../../Sources/Pastry/UI/SelectionState.swift)。面板回归见 [OverlayPanelManagerTests](../../Tests/PastryTests/OverlayPanelManagerTests.swift)。

1. 全局快捷键或菜单栏入口调用 `OverlayPanelManager.show()` / `toggle()`。
2. 管理器记录当前前台应用，并在鼠标所在屏幕创建或复用全屏 `ClipboardOverlayPanel`。
3. 面板使用 `.borderless`、`.fullSizeContentView` 和 `.nonactivatingPanel`，层级为 `.popUpMenu`，并加入所有 Space 和全屏辅助窗口。
4. `OverlayView` 接收 `overlayWillShow`，恢复默认选择、预取图标并执行入场状态。
5. 点击背景、Esc 或失焦最终请求 dismiss；视图先完成退出状态，再由管理器清理 monitor、预览和面板状态。
6. 粘贴路径先确认辅助功能权限、挂起剪贴板监听、激活原目标应用并隐藏面板，再写回剪贴板和投递粘贴快捷键。

启动后会使用一个不可交互、近乎透明的临时面板预热 `NSHostingView`、材质和卡片首帧布局。预热面板不能进入正常事件和诊断生命周期。

## 键盘与关闭层级

键盘所有者只有三种：面板导航、搜索框和收藏备注编辑器。文本输入拥有键盘时，普通编辑键必须交还系统；卡片级快捷键只在面板导航态消费。

Esc 按当前 UI 层级逐层处理：确认层、备注编辑、筛选、Quick Look、搜索，最后才关闭面板。同一次 Esc 关闭 Quick Look 或备注编辑后可能级联触发第二次 cancel，管理器用短暂的吞键窗口阻止面板被一并关闭。

面板通过 `NSWindow.didResignKeyNotification` 自动收起。Quick Look 正在显示或刚关闭时会暂时保留面板并重新取得 key；粘贴、确认层和拖拽穿透期间不会走普通失焦收起路径。

## 选择与拖拽

`SelectionState` 是选择行为的事实来源。`OverlayView` 只负责从键盘或鼠标事件获取意图，再把可见条目顺序交给状态机。

单选和多选拖拽都使用 SwiftUI `.onDrag`。多选时由 `DragPayloadBuilder.providerForSelection` 生成一个多行文本 `NSItemProvider`；不要在卡片上重新引入 AppKit 事件覆盖层，因为覆盖层会截获 mouseDown，破坏 Command/Shift 选择。

拖拽开始后，`beginDragThrough()` 让面板忽略鼠标事件并立即 `orderOut`，持续检查鼠标按键释放后再完成清理，使目标应用能够接收拖拽。

## 渲染不变量与已知限制

- 面板层级保持 `.popUpMenu`；`.screenSaver` 会破坏 `NSMenu` 右键事件链。
- 透明面板中的托盘背景使用 `NSVisualEffectView(.hudWindow)`。当前实现没有采用 `NSGlassEffectView`；如需重新评估，必须先验证透明面板、浅深桌面和阴影边界。
- 材质 view 必须启用 layer、裁剪圆角并关闭 layer 阴影，避免圆角外残留暗边。
- 受最大高度约束的内容需要显式 `.clipped()`，否则 SwiftUI 子视图仍可能绘制到 frame 之外。
- 侧边栏选择不依赖 `NavigationSplitView` 中的 `List(selection:)`，当前设置导航使用显式按钮状态。
- 面板相关状态和 AppKit 调用保持在主线程；不要从后台线程读写键盘所有者或布局状态。

## 主要验证

- `OverlayPanelManagerTests`：面板配置、失焦保留和辅助逻辑。
- `OverlayInteractionModelTests`、`SelectionStateTests`：点击、键盘导航和多选状态。
- `FilePreviewTests`、`DragPayloadBuilderTests`：单选和多选拖拽载荷。
- `ClipboardCardSnapshotTests`：卡片主要视觉状态。
- `mise run smoke`：真实面板、快捷键、拖拽和应用间交互。

完整验证入口见[测试说明](../TESTING.md)。
