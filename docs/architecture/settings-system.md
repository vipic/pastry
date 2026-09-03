# 设置与系统集成架构

> 源码核对：2026-09-03，基线 `a5691d8`。静态核对；系统授权、登录启动和窗口交接仍需真实 macOS 验收。

## 职责与入口

本模块连接应用生命周期、菜单栏、首次引导、设置存储和 macOS 服务。剪贴板历史、浮层交互及更新分别由相邻模块负责。

源码入口：[PastryApp / AppDelegate](../../Sources/Pastry/PastryApp.swift)、[SettingsSceneView](../../Sources/Pastry/Settings/SettingsSceneView.swift)、[OnboardingFlow](../../Sources/Pastry/UI/OnboardingFlow.swift)、[GlobalHotkeyManager](../../Sources/Pastry/Utils/GlobalHotkeyManager.swift)、[LaunchAtLoginManager](../../Sources/Pastry/Utils/LaunchAtLoginManager.swift)、[AccessibilityPermissionChecker](../../Sources/Pastry/Utils/AccessibilityPermissionChecker.swift)。

## 生命周期与设置

- `PastryApp` 启动存储层、清理孤儿图片、预热图标、注册 Carbon 热键与菜单栏，并安排下一轮 RunLoop 预热浮层。
- `AppDelegate` 管理设置、帮助、更新和引导窗口；应用启动时初始化默认排除应用、读取更新错误并按引导版本决定是否展示 onboarding。
- `SettingsSceneView` 以 `@AppStorage` / UserDefaults 保存配置，按 general、shortcut、security、version、about 五个页签组合视图。窗口复用时用 `settingsSelectTab` 通知切换目标页签。
- 侧边栏使用显式按钮修改选择状态，避免把导航建立在旧版曾失效的 `List(selection:)` 行为上。

## 热键、引导与登录启动

`GlobalHotkeyManager` 使用 Carbon `RegisterEventHotKey`，默认 Command + Shift + V；未设置与 keyCode 0 必须区分，负值表示禁用。配置变化才重新注册；录制快捷键时注销旧键，结束时强制恢复。热键回调先让引导流程确认操作，再决定是否切换浮层。

引导分 welcome、shortcut、copy、permission 四步。`OnboardingPreferences` 保存完成版本；复制检测以进入步骤时的记录 ID 集合作为基线。`OnboardingOverlayHandoff` 等应用失去 active 后再打开浮层，避免把引导窗口当成后续粘贴目标。

登录启动通过 `SMAppService.mainApp` 注册或注销。设置页在失败时恢复展示值并显示错误，不能仅写 UserDefaults 后假定系统状态已改变。

## 权限与隐私

- 采集剪贴板、来源快照和 Carbon 全局热键不需要 Input Monitoring 或辅助功能授权。
- `AccessibilityPermissionChecker` 区分只查询状态与主动弹窗；粘贴前请求权限，未授权时中止粘贴。用户也可以通过引导/设置明确打开系统授权页面。
- 日志不得包含剪贴板正文、搜索词、完整 URL 或密钥。文件诊断开关与系统 Unified Logging 的边界、轮转和排查命令见[诊断说明](../DIAGNOSTICS.md)，不在此重复路径清单。
- 颜色以 [PastryPalette](../../Sources/Pastry/Settings/SettingsChrome.swift) 为准，其他共享视觉尺寸以 [UIConstants](../../Sources/Pastry/UI/UIConstants.swift) 为准；单文件布局不升级成全局 token。

## 验证与边界

重点参考 [OnboardingFlowTests](../../Tests/PastryTests/OnboardingFlowTests.swift)、[HotkeyUtilsTests](../../Tests/PastryTests/HotkeyUtilsTests.swift)、[LaunchAtLoginManagerTests](../../Tests/PastryTests/LaunchAtLoginManagerTests.swift)、[AccessibilityPermissionCheckerTests](../../Tests/PastryTests/AccessibilityPermissionCheckerTests.swift)、[SettingsViewTests](../../Tests/PastryTests/SettingsViewTests.swift) 和 [DeveloperDiagnosticsTests](../../Tests/PastryTests/DeveloperDiagnosticsTests.swift)。

这些测试主要覆盖状态与可注入的服务接口，不能代替真实系统权限弹窗、快捷键冲突、登录项审批和多窗口激活验收。改动相关流程时按[测试说明](../TESTING.md)补做 smoke / 人工检查。
