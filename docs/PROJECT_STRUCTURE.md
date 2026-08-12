# 项目结构

本文档按当前 Git 已跟踪内容说明 Pastry 各目录与文件的职责。`.build/`、`dist/`、`.local/` 等本机生成目录不属于源码，统一列在文末。

```text
Pastry/
├── .github/
│   └── workflows/
│       ├── tests.yml                 # CI：shell、设计 token、测试、覆盖率和 release 编译
│       └── release-build-verification.yml # 手动验证 release 构建，不生成正式 DMG
│
├── Resources/
│   ├── AppIcon.icns                  # 打包进 App Bundle 的正式应用图标
│   ├── Copy.aiff                     # 复制提示音
│   ├── Paste.aiff                    # 粘贴提示音
│   ├── dmg-background.png            # DMG 普通分辨率背景
│   └── dmg-background@2x.png         # DMG Retina 背景
│
├── Sources/
│   ├── CSQLCipher/
│   │   ├── libsqlcipher.a            # vendored SQLCipher 静态库
│   │   └── include/
│   │       ├── module.modulemap      # SwiftPM C 模块定义
│   │       ├── shim.c                # C 模块最小编译单元
│   │       ├── shim.h                # SQLCipher 编译宏和头文件入口
│   │       ├── sqlite3.h             # SQLCipher 对应的 SQLite 主头文件
│   │       ├── sqlite3ext.h          # SQLite 扩展接口
│   │       └── sqlite_cfg.h          # SQLCipher 构建配置头文件
│   │
│   ├── Pastry/
│       ├── PastryApp.swift           # @main、AppDelegate、窗口和应用生命周期
│       │
│       ├── Core/
│       │   ├── ClipboardItem.swift           # 剪贴板记录、格式、标签和去重模型
│       │   ├── ClipboardMonitor.swift        # NSPasteboard 轮询、去重和来源识别
│       │   ├── ClipboardMonitorReaders.swift # 文本、URL、RTF、HTML、图片和文件读取器
│       │   └── ImageCacheManager.swift       # 图片缩略图、原图映射和缓存清理
│       │
│       ├── Generated/
│       │   └── Version.generated.swift       # release.sh 写入的构建版本占位文件
│       │
│       ├── Persistence/
│       │   ├── DatabaseManager.swift         # SQLCipher CRUD、FTS5、统计和保留清理
│       │   ├── DatabaseKeyManager.swift      # 数据库密钥生成、保存和旧 Keychain 迁移
│       │   ├── DatabaseMigrator.swift        # 旧明文数据库迁移为加密数据库
│       │   └── StoreManager.swift            # SwiftUI 主状态、搜索、筛选和删除桥接
│       │
│       ├── Resources/
│       │   ├── Localizable.xcstrings         # 界面本地化字符串
│       │   └── placeholder-icon.png          # 来源应用图标占位图
│       │
│       ├── Settings/
│       │   ├── SettingsSceneView.swift       # 设置窗口、侧边栏和页签路由
│       │   ├── SettingsGeneralTab.swift      # 语言、启动、声音、点击和历史设置
│       │   ├── SettingsShortcutTab.swift     # 全局快捷键录制和清除
│       │   ├── SettingsSecurityTab.swift     # 网络、诊断、授权和排除应用
│       │   ├── SettingsVersionTab.swift      # 版本状态、版本说明和更新操作
│       │   ├── SettingsAboutTab.swift        # 作者、版权、源码和许可
│       │   ├── SettingsChrome.swift          # PastryPalette 和设置卡片外观
│       │   └── SettingsControls.swift        # 设置页复用按钮、开关和行布局
│       │
│       ├── UI/
│       │   ├── OverlayPanelManager.swift     # 全屏透明 NSPanel 与粘贴生命周期
│       │   ├── OverlayView.swift             # 主面板、工具栏、卡片、搜索和多选
│       │   ├── OverlayKeyboardRouter.swift   # 面板键盘事件路由
│       │   ├── OverlayInteractionModel.swift # 点击、滚动和选中目标决策
│       │   ├── OverlayEmptyStateModel.swift  # 空历史和无结果状态模型
│       │   ├── OnboardingFlow.swift          # 首次启动引导状态机
│       │   ├── OnboardingView.swift          # 首次启动引导界面
│       │   ├── ClipboardCardView.swift       # 卡片主体、手势、备注和拖拽入口
│       │   ├── ClipboardCardContentViews.swift # 不同格式的卡片内容视图
│       │   ├── ClipboardCardActions.swift    # 右键菜单、复制、打开、分享和删除
│       │   ├── ClipboardDisplayMode.swift    # 卡片展示类型判定
│       │   ├── ClipboardItemPreviewBuilder.swift # Quick Look/文本预览内容构建
│       │   ├── FilePreviewContent.swift      # 单文件、多文件和缺失文件预览
│       │   ├── LinkPreviewLoader.swift       # 网页标题、描述和预览图抓取
│       │   ├── RemoteThumbnail.swift         # 远程缩略图渲染
│       │   ├── FilterPopoverContent.swift    # 来源、类型、时间等筛选弹窗
│       │   ├── SelectionState.swift          # 单选、散选和区间选择状态机
│       │   ├── CardStripScrollDriver.swift   # 卡片带滚动和定位
│       │   ├── CardPreviewAnchorRegistry.swift # 卡片预览锚点注册
│       │   ├── ConfirmationOverlay.swift     # 删除等危险操作确认界面
│       │   ├── GlassBackground.swift         # NSVisualEffectView 托盘背景
│       │   ├── HistoryRetentionSettingsView.swift # 历史容量和保留周期界面
│       │   ├── HotkeyRecorder.swift          # 快捷键捕获控件
│       │   ├── MenuBarManager.swift          # 菜单栏图标和入口
│       │   ├── MenuBarMenuFactory.swift      # 可测试的菜单结构构造器
│       │   ├── QuickLookPreviewHelper.swift  # 系统 Quick Look 调用
│       │   ├── RightClickDetector.swift      # SwiftUI/AppKit 右键桥接
│       │   ├── SearchFieldAutofillSuppressor.swift # 搜索框输入辅助抑制
│       │   ├── AccessibilityPermissionRowModel.swift # 授权状态展示模型
│       │   ├── AppIconImageView.swift        # 应用图标 SwiftUI 组件
│       │   ├── AboutView.swift               # 独立帮助窗口内容
│       │   ├── UpdateView.swift              # 独立更新窗口
│       │   └── UIConstants.swift             # 尺寸、圆角、字号和动效 token
│       │
│       └── Utils/
│           ├── Constants.swift               # UserDefaults key、通知名和通用常量
│           ├── L10n.swift                    # 本地化读取和格式化
│           ├── AppDirectories.swift          # 数据、缓存和日志目录
│           ├── AppVersionInfo.swift          # 生成版本与 Bundle 版本组合
│           ├── AppIconProvider.swift         # 来源应用图标和主题色
│           ├── AccessibilityIdentifiers.swift # UI 自动化稳定标识
│           ├── AccessibilityPermissionChecker.swift # 辅助功能授权查询和请求
│           ├── GlobalHotkeyManager.swift     # Carbon 全局快捷键
│           ├── LaunchAtLoginManager.swift    # 登录时启动管理
│           ├── HistoryRetentionPolicy.swift  # 历史容量与保留周期规则
│           ├── NetworkAccessPolicy.swift     # HTTPS、内网和响应大小安全策略
│           ├── RemoteImageLoader.swift       # 远程图片下载和内存缓存
│           ├── RemoteResourceRedirectDelegate.swift # 重定向 SSRF 检查
│           ├── PasteboardWriter.swift        # 各格式写回系统剪贴板
│           ├── DragPayloadBuilder.swift      # 单选和多选拖拽载荷
│           ├── SoundFeedback.swift           # 复制、粘贴和无效操作声音
│           ├── DeveloperDiagnostics.swift    # runtime、perf 和 usage 诊断日志
│           ├── UpdateChecker.swift           # GitHub Release 查询、比较和下载
│           ├── UpdateInstallScriptBuilder.swift # 更新安装 helper 脚本生成
│           └── Watchdog.swift                # 主线程卡死检测、采样和恢复
│   └── PastryReleaseSmoke/
│       └── main.swift                         # 正式 DMG 首次启动验收器
│
├── Tests/
│   └── PastryTests/
│       ├── AccessibilityIdentifiersTests.swift       # 辅助功能标识稳定性
│       ├── AccessibilityPermissionCheckerTests.swift # 授权查询和提示
│       ├── AccessibilityPermissionRowModelTests.swift # 授权状态展示
│       ├── AppDirectoriesTests.swift                  # 应用目录计算和创建
│       ├── AppIconProviderTests.swift                 # 图标、主题色和缓存
│       ├── AppVersionInfoTests.swift                  # 版本信息降级逻辑
│       ├── ClipboardItemTests.swift                   # 模型、格式和去重 key
│       ├── ClipboardItemPreviewBuilderTests.swift     # 文件和文本预览构建
│       ├── ClipboardMonitorTests.swift                # 剪贴板读取、过滤和去重
│       ├── ClipboardSearchTests.swift                 # 内容、备注和应用名搜索
│       ├── ClipboardCardSnapshotTests.swift           # 卡片 PNG 快照测试
│       ├── ConstantsTests.swift                       # 默认值和配置 key
│       ├── DatabaseKeyManagerTests.swift              # 密钥保存、权限和迁移
│       ├── DatabaseManagerTests.swift                 # SQLCipher、CRUD、FTS 和迁移
│       ├── DeveloperDiagnosticsTests.swift            # 日志、脱敏和轮转
│       ├── DisplayModeTests.swift                     # 卡片展示模式
│       ├── DragPayloadBuilderTests.swift              # 文本、URL 和文件载荷
│       ├── FTSQueryBuilderTests.swift                 # FTS5 查询转义
│       ├── FilePreviewTests.swift                     # 文件预览和多文件行为
│       ├── HotkeyUtilsTests.swift                     # 键码和快捷键显示
│       ├── ImageCacheManagerTests.swift               # 图片缓存和淘汰
│       ├── L10nTests.swift                            # 本地化 key 和降级
│       ├── LaunchAtLoginManagerTests.swift            # 登录启动封装
│       ├── LinkPreviewLoaderTests.swift               # 网页元数据和图片选择
│       ├── MenuBarMenuFactoryTests.swift              # 菜单结构和点击路由
│       ├── NetworkAccessPolicyTests.swift             # 内网、IPv4 和响应限制
│       ├── OnboardingFlowTests.swift                  # 引导状态机和激活交接
│       ├── OverlayEmptyStateModelTests.swift          # 空状态文案
│       ├── OverlayInteractionModelTests.swift         # 点击、滚动和修饰键交互
│       ├── OverlayPanelManagerTests.swift             # 面板配置和辅助逻辑
│       ├── PasteboardWriterTests.swift                # 独立 pasteboard 写回
│       ├── RemoteResourceRedirectDelegateTests.swift  # 重定向安全过滤
│       ├── SelectionStateTests.swift                  # 多选和区间选择
│       ├── SettingsViewTests.swift                    # 设置页签和路由
│       ├── SigningConfigurationTests.swift            # 签名脚本和文档一致性
│       ├── SnapshotTestSupport.swift                  # 快照记录和对比基础设施
│       ├── StoreManagerTests.swift                    # 搜索、筛选、收藏和删除
│       ├── UpdateCheckerTests.swift                   # 版本比较和下载验证
│       ├── UpdateInstallScriptBuilderTests.swift      # 安装脚本安全性
│       └── __Snapshots__/
│           ├── clipboard-card-html.png
│           ├── clipboard-card-link.png
│           ├── clipboard-card-multi-file.png
│           ├── clipboard-card-text-selected-command.png
│           └── clipboard-card-text.png                # 卡片视觉回归基线
│
├── docs/
│   ├── DEVELOPMENT.md                 # 开发、签名、部署和 mise
│   ├── TESTING.md                     # 单测、覆盖率、快照、冒烟和性能
│   ├── RELEASE.md                     # DMG、GitHub Release 和更新排查
│   ├── DIAGNOSTICS.md                 # 应用及本地命令日志说明
│   ├── PRODUCT.md                     # 当前产品行为与验收场景
│   ├── PROJECT_STRUCTURE.md           # 本文件：完整项目树和职责说明
│   ├── design-tokens.html             # UI token 可视化参考
│   ├── adr/
│   │   ├── 001-sqlite-over-coredata.md       # SQLite/SQLCipher 架构决策
│   │   └── 002-nspanel-over-swiftui-window.md # NSPanel 架构决策
│   └── screenshots/
│       ├── icon.png                   # README 应用图标
│       └── showcase.png               # README 主界面截图
│
├── scripts/
│   ├── bench.sh                       # 性能基准和 perf.log 报告
│   ├── smoke.sh                       # 部署、填充样本、唤起和截图
│   ├── populate_clipboard.sh          # 写入各格式剪贴板测试样本
│   ├── pbwrite.swift                  # NSPasteboard 测试写入工具源码
│   ├── diagnostics.sh                 # 查看应用和命令日志
│   ├── check_shell.sh                 # 全部 shell 语法检查
│   ├── check_coverage.sh              # Swift 覆盖率门槛
│   ├── check_design_tokens.sh         # UI token 防回潮检查
│   ├── next_version.sh                # Conventional Commits → SemVer
│   ├── verify_release.sh              # 正式 App 结构、版本和签名检查
│   ├── release_smoke.sh               # 挂载、复制并首次启动正式 DMG
│   ├── layout_dmg.applescript          # 在最终可写卷上生成 Finder 布局
│   ├── lib/
│   │   └── command_log.sh             # deploy/release 命令耗时日志
│   └── tasks/
│       ├── release.sh                 # mise release 参数检查和转发
│       ├── release-auto.sh            # mise 自动版本发布包装
│       └── publish.sh                 # mise GitHub 发布包装
│
├── deploy.sh                          # Debug 编译、签名并启动开发版
├── release.sh                         # 测试、Release 编译、签名和 DMG 发布
├── mise.toml                          # mise 唯一任务定义入口
├── Package.swift                      # SwiftPM Target、资源和链接配置
├── README.md                          # 面向普通用户的功能和安装说明
├── AGENTS.md                          # Agent 架构、约定、坑点和验证要求
├── LICENSE                            # MIT 许可证
└── .gitignore                         # 构建、日志、IDE 和临时文件忽略规则
```

## 生成目录

以下目录不会提交到 Git，通常不应手工编辑：

```text
.build/             # SwiftPM 编译缓存、二进制和测试产物
.swiftpm/           # SwiftPM 本机配置
dist/               # DMG、冒烟截图和发布产物
.local/             # 本地命令日志和临时开发工具
.release_staging/   # release.sh 组装 App 与 DMG 的临时目录
*.app / *.dmg       # 本机应用包和磁盘镜像产物
```

## 主要依赖关系

```text
README / docs
      │
mise.toml ──→ deploy.sh
      ├─────→ scripts/tasks ──→ release.sh
      └─────→ scripts/* 检查、测试和诊断工具

PastryApp
   ├── Core           剪贴板采集与数据模型
   ├── Persistence    SQLCipher 存储、搜索和状态层
   ├── UI             面板、卡片、预览和交互
   ├── Settings       设置窗口
   └── Utils          热键、网络、更新和日志等基础能力
```
