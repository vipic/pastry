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
2. 管理器记录当前前台应用，并在鼠标所在屏幕创建或复用与托盘实际范围相同的 `ClipboardOverlayPanel`；面板外区域不会拦截其他应用的鼠标交互。
3. 面板使用 `.borderless`、`.fullSizeContentView` 和 `.nonactivatingPanel`，层级为 `.popUpMenu`，并加入所有 Space 和全屏辅助窗口。
4. 托盘顶部非按钮区域提供停靠拖拽；窗口本身不跟随指针平移。指针进入与目标托盘同尺寸的左、右或底部投放区域后，会显示半透明虚线目标框；只有在框内松手才切换布局、贴到对应边缘并记录最近位置，离开目标框则取消预览。
5. `OverlayView` 接收 `overlayWillShow`，恢复默认选择、预取图标并执行入场状态。
6. 未固定时，Esc 或失焦最终请求 dismiss；视图先完成退出状态，再由管理器清理 monitor、预览和面板状态。
7. 工具栏“固定”只维持当前显示会话：面板失焦后留在屏幕上，且不重新抢占 key window；显式关闭会解除固定。
8. 粘贴路径先确认辅助功能权限、挂起剪贴板监听、激活当前目标应用并暂时隐藏面板，再写回剪贴板和投递粘贴快捷键；固定状态下操作完成后在原停靠位置恢复。

启动后会使用一个不可交互、近乎透明的临时面板预热 `NSHostingView`、材质和卡片首帧布局。预热面板不能进入正常事件和诊断生命周期。

## 键盘与关闭层级

键盘所有者只有三种：面板导航、搜索框和收藏备注编辑器。文本输入拥有键盘时，普通编辑键必须交还系统；卡片级快捷键只在面板导航态消费。

Esc 按当前 UI 层级逐层处理：确认层、备注编辑、筛选、Quick Look、搜索，最后才关闭面板。同一次 Esc 关闭 Quick Look 或备注编辑后可能级联触发第二次 cancel，管理器用短暂的吞键窗口阻止面板被一并关闭。

面板通过 `NSWindow.didResignKeyNotification` 自动收起。固定时失焦不会收起或抢回焦点，用户可以直接操作其他应用；Quick Look 正在显示或刚关闭时会暂时保留面板并重新取得 key；粘贴、确认层和拖拽穿透期间不会走普通失焦收起路径。

搜索框保留输入即执行的普通关键词搜索。只有用户在通用设置中开启实验性的智能找回后，才显示单独的智能找回按钮；按钮仅在用户点击后请求设备端模型解析描述、执行本地语义召回并重排候选。运行中、已应用、模型不可用和失败状态由按钮图标及辅助说明反馈。编辑查询或清除筛选会使旧结果失效，避免迟到的异步结果覆盖新输入。

## 选择与拖拽

`SelectionState` 是选择行为的事实来源。`OverlayView` 只负责从键盘或鼠标事件获取意图，再把可见条目顺序交给状态机。

单选和多选拖拽都使用 SwiftUI `.onDrag`。多选时由 `DragPayloadBuilder.providerForSelection` 生成一个多行文本 `NSItemProvider`；不要在卡片上重新引入 AppKit 事件覆盖层，因为覆盖层会截获 mouseDown，破坏 Command/Shift 选择。

卡片拖拽开始后，`beginDragThrough()` 让面板忽略鼠标事件并立即 `orderOut`，持续检查鼠标按键释放：普通状态完成清理，固定状态则恢复原停靠位置，使用户可以连续向目标应用拖入多个素材。

## 渲染不变量与已知限制

- 面板层级保持 `.popUpMenu`；`.screenSaver` 会破坏 `NSMenu` 右键事件链。
- 透明面板中的托盘背景使用 `NSVisualEffectView(.hudWindow)`，托盘本身不绘制投影，使底部和左右停靠保持一致。当前实现没有采用 `NSGlassEffectView`。
- 材质 view 必须启用 layer、裁剪圆角并关闭 layer 阴影，避免圆角外残留暗边。
- 受最大高度约束的内容需要显式 `.clipped()`，否则 SwiftUI 子视图仍可能绘制到 frame 之外。
- 横向卡片带使用 SwiftUI `ScrollPosition` 坐标连续滚动，并用 `onScrollGeometryChange` 限制内容边界；侧滚轮限制单次位移用于微调，普通滚轮映射到横向并保留设备加速，传统滚轮只做一次行距换算。AppKit 桥接只接管发往托盘面板本身的滚轮事件；筛选 popover、设置窗口等独立窗口保留系统滚动链，因此来源应用列表会优先纵向滚动。实现不遍历或直接修改 SwiftUI 私有的 `NSScrollView` 层级。
- 底部托盘在宽屏使用横向卡带；左右托盘固定使用纵向列表并占用屏幕可见高度。实验功能中的紧凑列表开关缺省关闭；开启后左右托盘内容宽度从 320 pt 收窄到 272 pt，面板连同两侧 inset 共 296 pt，并把 240 pt 方形卡片替换为 84 pt 紧凑条目。纯文本和富文本保持全宽文字布局；链接显示抓取的网页标题和链接地址；带图片的 HTML、图片记录与单文件在右侧使用 92 pt 宽的预览，左侧沿用类型、名称、时间和来源应用布局；多文件不显示右侧大预览，改为与完整卡片一致的文件图标和名称纵向列表。侧边头部把搜索与设置按钮相对托盘外框保持 14 pt inset，使 10 pt 控件圆角与 24 pt 托盘圆角共享圆心。悬停轻操作始终锚定卡片右下角；左右分栏条目直接覆盖在预览区域上，并使用带描边的系统材质底板保证在图片与文件图标上可读，不得通过预览宽度把按钮推回左侧信息区。两种侧边视图共用选择、拖拽、收藏、复制、删除、右键菜单和键盘导航，底部卡带不受该开关影响。设置模式决定下次打开固定回到底部还是沿用最近吸附位置，不限制当前显示会话的拖拽。
- 侧边栏选择不依赖 `NavigationSplitView` 中的 `List(selection:)`，当前设置导航使用显式按钮状态。
- `OverlayKeyboardRouter` 在应用失去激活状态时必须清除 Command 角标状态，因为用户可能在切换到其他应用后才松开修饰键，当前进程收不到对应的 `flagsChanged`。
- Command 数字快捷选择以 `onScrollTargetVisibilityChange` 报告的当前视口卡片为准，再按筛选结果顺序稳定编号 1–9；角标显示与 `⌘1`–`⌘9` 粘贴必须消费同一组 ID，不能回退到整个结果列表的开头。
- 面板相关状态和 AppKit 调用保持在主线程；不要从后台线程读写键盘所有者或布局状态。

## 主要验证

- `OverlayPanelManagerTests`：面板配置、失焦保留和辅助逻辑。
- `OverlayInteractionModelTests`、`SelectionStateTests`：点击、键盘导航和多选状态。
- `FilePreviewTests`、`DragPayloadBuilderTests`：单选和多选拖拽载荷。
- `mise run smoke`：真实面板、快捷键、拖拽和应用间交互。

完整验证入口见[测试说明](../TESTING.md)。
