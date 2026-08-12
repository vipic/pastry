# Pastry — Agent Onboarding

> macOS 26+ 剪贴板管理器。Swift + SwiftUI，SQLCipher 静态库 vendored 到仓库内，无需包管理器拉第三方依赖。全屏半透明 overlay 面板 + 应用主题色卡片。

## Build & Deploy

### 快速开发部署

```bash
./deploy.sh   # debug 编译 → 签名 → 启动，部署到 ~/Applications/Pastry Dev.app
```

### 生产发布

```bash
./release.sh <version>   # 统一验证 → release 编译 → 签名 → DMG → 正式制品烟测
./release.sh <version> --publish   # 原子推 main + tag，并创建不可覆盖的 GitHub Release
```

### 一次性设置：代码签名证书

为了让 TCC 权限（辅助功能等）在更新时不丢失，需要固定签名证书。当前脚本默认使用作者级共享证书 `Nekutai`，也可以通过 `CODESIGN_IDENTITY` 指定任意稳定的代码签名证书：自签名代码签名证书或开发者账号证书都可以。同一个作者的多个应用可以共用同一张证书。

| 脚本 | 证书名称 | Bundle ID |
|---|---|---|
| `deploy.sh` | `${CODESIGN_IDENTITY:-Nekutai}` | `com.nekutai.pastry.dev` |
| `release.sh` | `${CODESIGN_IDENTITY:-Nekutai}` | `com.nekutai.pastry` |

**创建方法（只需一次，30 秒）：**

1. 打开 **Keychain Access**（钥匙串访问）
2. 菜单 **钥匙串访问 → 证书助理 → 创建证书**
3. 名称填 `Nekutai`（或你自己的作者证书名）
4. 身份类型：**自签名根**
5. 证书类型：**代码签名**
6. 勾选 **覆盖默认**（覆盖默认值）
7. 点击「继续」→「创建」

Pastry 需要辅助功能授权，不能使用 ad-hoc 签名。证书缺失、签名失败或显式设置 `CODESIGN_IDENTITY="-"` 时，脚本会直接停止；请先创建自签名代码签名证书，或使用开发者账号证书。

### 手动命令（备用）

```bash
# 构建
swift build -c release

# 部署（必须 kill 旧进程，否则运行中的二进制不更新）
cp .build/release/Pastry ~/Applications/Pastry.app/Contents/MacOS/Pastry

# 重签
rm -rf ~/Applications/Pastry.app/Contents/_CodeSignature
codesign --force --sign "${CODESIGN_IDENTITY:-Nekutai}" ~/Applications/Pastry.app

# 重启
pkill -f Pastry; sleep 0.5; open ~/Applications/Pastry.app
```

## Architecture

```
Sources/Pastry/
├── PastryApp.swift                # @main + AppDelegate (LSUIElement)
├── SettingsView.swift             # 设置窗口（General / Shortcut / Security）
├── Core/
│   ├── ClipboardItem.swift        # Codable 数据模型 (SourceFormat + ContentTags)
│   ├── ClipboardMonitor.swift     # NSPasteboard 轮询引擎
│   ├── ClipboardMonitorReaders.swift # 文本/RTF/HTML/文件/图片读取器
│   └── ImageCacheManager.swift    # 图片缓存与原图映射
├── Persistence/
│   ├── DatabaseManager.swift      # SQLite3 C API + FTS5 全文搜索 + SQLCipher 全库加密
│   ├── DatabaseKeyManager.swift   # 数据库密钥文件 + 旧 Keychain 迁移
│   ├── DatabaseMigrator.swift     # 明文数据库 → SQLCipher 迁移
│   └── StoreManager.swift         # @MainActor ObservableObject 桥接
├── CSQLCipher/                    # SQLCipher 静态库（vendored，无需外部下载）
│   ├── libsqlcipher.a             # 预编译静态库（CommonCrypto 后端）
│   ├── include/shim.h             # 定义 SQLITE_HAS_CODEC + SQLCIPHER_CRYPTO_CC
│   ├── include/module.modulemap   # SPM module 定义
│   └── include/sqlite3.h          # SQLCipher 头文件
├── UI/
│   ├── OverlayPanelManager.swift  # NSPanel 全屏 overlay 管理
│   ├── OverlayView.swift          # SwiftUI 内容层（透明底 + 卡片托盘）
│   ├── ClipboardCardView.swift    # 卡片视图主体
│   ├── ClipboardCardActions.swift # 右键菜单、打开、预览、分享
│   ├── LinkPreviewLoader.swift    # 链接预览抓取 + 图片选取
│   ├── RemoteThumbnail.swift      # 远程缩略图渲染
│   ├── FilePreviewContent.swift   # 文件/多文件卡片内容
│   ├── SelectionState.swift       # 多选状态机
│   ├── UpdateView.swift           # 更新检查窗口
│   ├── GlassBackground.swift      # NSVisualEffectView(.hudWindow) 托盘背景
│   ├── HotkeyRecorder.swift       # 快捷键录制器
│   ├── UIConstants.swift          # 尺寸 / 圆角 / 字号 / 透明度 / 动效 token
│   └── MenuBarManager.swift       # NSStatusBar 菜单栏入口
├── Settings/
│   ├── SettingsChrome.swift       # PastryPalette 颜色 token + settingsCardChrome
│   ├── SettingsControls.swift     # Pill / Switch 等控件样式
│   └── Settings*Tab.swift         # General / Shortcut / Security / Version / About
└── Utils/
    ├── AppDirectories.swift       # 应用数据目录
    ├── AppIconProvider.swift      # 提取应用图标 + 主题色
    ├── AppVersionInfo.swift       # About / Settings 版本展示
    ├── Constants.swift            # SF Symbols、UserDefaults key、pastryWarmAccent
    ├── DragPayloadBuilder.swift   # 单选/多选拖拽载荷
    ├── GlobalHotkeyManager.swift  # Carbon RegisterEventHotKey 全局快捷键
    ├── HistoryRetentionPolicy.swift # 历史容量/保留周期策略
    ├── L10n.swift                 # 本地化读取
    ├── NetworkAccessPolicy.swift  # 远程预览 URL 安全过滤
    ├── PasteboardWriter.swift     # 写回剪贴板
    └── RemoteImageLoader.swift    # 远程图片下载 + 内存缓存

Tests/PastryTests/
├── ClipboardMonitorTests.swift    # 剪贴板读取/过滤
├── DatabaseManagerTests.swift     # SQLite CRUD + FTS + 迁移
├── StoreManagerTests.swift        # 存储层桥接
├── LinkPreviewLoaderTests.swift   # 链接预览抓取 + 图片选取逻辑
├── FilePreviewTests.swift         # 文件预览 + 拖拽载荷核心逻辑
├── PasteboardWriterTests.swift    # 写回剪贴板
├── SelectionStateTests.swift      # 多选状态机
├── UpdateCheckerTests.swift       # 更新检查/版本比较
└── 其他：目录、版本、图标、热键、本地化、网络策略、签名配置等
```

## Design Tokens

UI 色与尺寸使用两层权威源，**禁止在调用点新增 `Color(red:)` 字面量**：

- **颜色**：`PastryPalette`（[`Settings/SettingsChrome.swift`](Sources/Pastry/Settings/SettingsChrome.swift)）；`SettingsPalette` 为兼容 typealias
- **尺寸 / 圆角 / 字号 / 透明度 / 动效**：`UIConstants`（[`UI/UIConstants.swift`](Sources/Pastry/UI/UIConstants.swift)）
- **全局 token 需 ≥2 文件使用**；单文件布局值下沉为该文件的 `private enum Local`，不进 `UIConstants`
- 阶梯已收敛，新增值优先吸附现有档位：字号 9 档（9–24）、圆角 6 档（4/6/8/10/12/24）、动效时长 5 档（0.10/0.15/0.22/0.28/0.50）
- 防回潮：`scripts/check_design_tokens.sh`（CI 自动跑）拦截调用点新增 `Color(red:)` / 字号 / 圆角字面量
- 视觉参考：[`docs/design-tokens.html`](docs/design-tokens.html)

## Critical Pitfalls

以下是踩过的坑，Agent 接手时能省大量时间：

### 1. Timer 必须用 `.common` modes

```swift
// ❌ 错误 — 右键菜单 / 拖拽时 Timer 暂停，永不恢复
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { ... }

// ✅ 正确
let timer = Timer(timeInterval: 0.5, repeats: true) { ... }
RunLoop.main.add(timer, forMode: .common)
```

macOS 进入 tracking mode（右键、拖拽、滚动）时，default mode 的 Timer 会暂停。

### 2. NSGlassEffectView 在透明 NSPanel 中渲染异常

macOS 26 的 `NSGlassEffectView` 在透明 NSPanel 中渲染为**白色半透明**，无法产生真实液态玻璃效果。当前使用 `NSVisualEffectView(.hudWindow)` 替代：

```swift
// GlassBackground.swift
view.material = .hudWindow       // 深色半透明磨砂，浅/深桌面都稳定
view.blendingMode = .withinWindow
view.state = .active
```

### 3. NSGlassEffectView 自带阴影需手动关闭

```swift
glass.wantsLayer = true          // 必须先设为 true
glass.layer?.shadowOpacity = 0   // 关闭圆角外暗色阴影
glass.layer?.masksToBounds = true
```

### 4. NSPanel 层级：用 `.popUpMenu`，不用 `.screenSaver`

```swift
panel.level = .popUpMenu  // 101，能承载 NSMenu 事件
// ❌ .screenSaver (1000) — 会截断 NSMenu 事件链，右键菜单全部无响应
```

正确的 `styleMask` 和激活策略：

```swift
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.orderFrontRegardless()  // 不激活 app
panel.makeKey()               // 接收键盘事件但 app 保持后台
```

### 5. NSPanel Esc 关闭：通过通知 + 动画，不要直接 cleanup

```swift
// 键盘监听器发送通知
NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)

// OverlayView 监听并先播退出动画
.onReceive(NotificationCenter.default.publisher(for: .overlayRequestDismiss)) { _ in
    dismiss()  // 动画结束后调 OverlayPanelManager.hide()
}
```

### 6. `.frame(maxHeight:)` 必须配合 `.clipped()`

```swift
// ❌ 没有视觉效果 — 内容渲染超出 frame 边界
VStack { ... }
    .frame(maxHeight: 248)

// ✅
VStack { ... }
    .frame(maxHeight: 248)
    .clipped()
```

### 7. NavigationSplitView List(selection:) 侧边栏点击无效

SwiftUI macOS 26 的 `List(selection:)` 在 `NavigationSplitView` 侧边栏中点击不响应。解决方案：

```swift
Button(action: { selectedItem = item }) { ... }
    .buttonStyle(.plain)
    .listRowBackground(selectedItem == item ? Color.accentColor.opacity(0.1) : Color.clear)
```

### 8. 授权懒加载（仅粘贴操作）

剪贴板记录通过 `NSPasteboard.changeCount` 定时轮询，来源使用当前前台应用；面板滚轮只处理应用内的 `NSEvent`。项目不创建全局 `CGEvent` 监听，因此不需要 Input Monitoring 权限。

`simulatePaste()` 中的 `CGEventSource(stateID: .privateState)` + `postToPid` 需要辅助功能权限。只在用户首次执行跨应用粘贴时主动请求；剪贴板记录、来源识别和全局快捷键不依赖该权限。

### 9. git restore . 会丢弃未提交改动

`git restore .` 会丢弃所有未跟踪改动，包括之前特意保留的修复。需要先确认是否有需要保留的部分。

## SQLCipher 全库加密

### 架构

`clips.db` 使用 SQLCipher 全库加密，保护剪贴板历史不被直接读取。密钥通过设备派生 KEK 加密后存储在数据库旁的 `.key` 文件中，无 Keychain 依赖。

- **密钥生成**：首次启动时 `SecRandomCopyBytes` 生成 256-bit 随机密钥，使用设备派生 KEK 加密后写入 `.key` 文件
- **旧密钥迁移**：如果 `.key` 不存在但 Keychain 里有旧版密钥，会读取一次并迁移到 `.key`，然后删除 Keychain 条目
- **加密激活**：`sqlite3_key()` 在打开数据库后立即调用
- **透明性**：FTS5 全文搜索正常工作，查询逻辑无变化
- **测试跳过**：`init(dbPath:)` 构造函数通过 `openDatabase(useEncryption: false)` 跳过加密

### 迁移流程

升级安装时，如果检测到旧明文数据库（`sqlite3_key` 后 SELECT 失败），自动执行：

1. 以只读方式打开明文数据库
2. 导出 schema + 全部数据为 SQL dump
3. 创建新加密数据库
4. 执行 schema + 数据导入
5. 删除明文数据库，重新打开加密数据库

迁移日志输出 `明文数据库迁移完成 → 加密`。

### 重新编译 libsqlcipher.a

当需要更新 SQLCipher 版本或启用新扩展时，重新编译静态库：

```bash
# 下载 SQLCipher 源码
curl -sL "https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.6.1.tar.gz" -o sqlcipher.tar.gz
tar xzf sqlcipher.tar.gz && cd sqlcipher-4.6.1

# 配置（CommonCrypto 后端 + FTS5）
./configure --with-crypto-lib=commoncrypto \
  CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_TEMP_STORE=2 -DSQLCIPHER_CRYPTO_CC -O2"

# 编译对象文件
make -j8 2>&1  # 链接 CLI 工具会失败（缺少 framework 链接），但 sqlite3.o 已生成

# 打包静态库
ar rcs libsqlcipher.a sqlite3.o

# 复制到项目
cp libsqlcipher.a Sources/CSQLCipher/libsqlcipher.a
cp sqlite3.h sqlite3ext.h sqlite_cfg.h Sources/CSQLCipher/include/
```

编译标志说明：
- `SQLITE_HAS_CODEC`：启用加密 API（sqlite3_key）
- `SQLITE_ENABLE_FTS5`：启用 FTS5 全文搜索
- `SQLITE_ENABLE_FTS5_PARENTHESIS`：FTS5 支持括号分组查询
- `SQLCIPHER_CRYPTO_CC`：使用 Apple CommonCrypto（无外部依赖）
- `SQLITE_TEMP_STORE=2`：临时表存内存

## Testing Strategy

### 独立 Pasteboard（关键）

测试**绝不**使用 `NSPasteboard.general`。每个测试类使用独立 pasteboard：

```swift
let pasteboard = NSPasteboard.withUniqueName()  // "test.hermes.pastry.<uuid>"
```

原因：`NSPasteboard.general` 的写入会触发后台运行的 Pastry 的 `changeCount` 监听，导致复制提示音响起，干扰测试环境。

### 运行测试

```bash
swift test --enable-code-coverage
scripts/check_coverage.sh
```

完整命令速查（snapshot、coverage、smoke、release 前检查）见 `docs/TESTING.md`。

## Key Design Patterns

### App 来源检测（高频 AX 缓存 + CGEvent 四层兜底）

记录剪贴板来源时，四层策略（按优先级）：

1. **高频 AX 焦点缓存**（0.1s 刷新，0.15s 窗口）：0.1s 间隔持续轮询 `kAXFocusedApplicationAttribute` 并缓存。浮动面板（1Password Quick Open）关闭后才触发 poll——此缓存保存关闭前的焦点
2. **CGEvent 按键目标进程**（0.5s 窗口）：Event tap 在按键瞬间捕获 `eventTargetUnixProcessID`
3. **实时 Accessibility 焦点**：poll 触发时浮动面板尚未关闭的兜底
4. **前台 App**（`NSWorkspace.shared.frontmostApplication`）：终级回退

核心创新是 Layer 1 的高频缓存——将 Accessibility 查询与剪贴板 poll 解耦，0.1s 间隔独立运行，在浮动面板存活期间捕获焦点。

### 剪贴板清除策略

删除路径的不同行为：
- **设置页「清空全部记录」** → 清空全部记录，并清空系统剪贴板
- **面板工具栏 / 键盘删除** → 删除选中记录（含收藏）；若清空后历史为空则同步清空系统剪贴板
- **右键删除** → 删除目标记录（含收藏），不动系统剪贴板（用户可继续 ⌘V）
- **自动历史保留** → 只清理非收藏记录

收藏只豁免自动清理，不豁免用户删除。删除确认开启且选中含收藏时，文案会提示收藏条数。

### 开发诊断记录

设置 → Security → Privacy「开发诊断记录」开关（UserDefaults `performance_logging_enabled`）同时控制：

- `~/Library/Logs/Pastry/perf.log`：面板 / 粘贴计时（`scripts/bench.sh --report` 可读）
- `~/Library/Logs/Pastry/usage.json`：功能使用次数累加（收藏、删除、预览、筛选、粘贴路径等）

仅本地文件，不上报。环境变量 `PASTRY_DIAGNOSTICS=1` 或 `PASTRY_PERF_LOG=1` 也可强制开启。

### 多选拖拽策略

多选拖拽与单选一样走 SwiftUI `.onDrag`：`isInMultiSelection` 时用 `DragPayloadBuilder.providerForSelection` 生成**单个** `NSItemProvider`（多行文本），拖拽图为系统卡片快照。

**历史教训**：曾用 AppKit `MultiSelectionDragSourceView` 覆盖层做自定义拖拽图（两张叠卡 + 自绘数量角标），但该覆盖层的 `hitTest` 会吃掉左键 mouseDown，导致 ⌘/⇧ 点选永远到不了卡片手势，且 `hitTest` 穿透方案会落到托盘空白手势触发 `selection.reset()` 整批清空。**不要再引入盖住卡片的 AppKit 事件层**；自定义拖拽图价值远低于点选正确性。

当前取舍：多选拖拽只暴露拼接的多行文本 flavor（不再有独立 `.webloc` / 多 file URL），批量文件投递建议走工具栏「粘贴 / 复制」。

### 链接预览图片选取

优先级：`og:image` → `twitter:image` → 语义排序（黑名单过滤 avatar/logo/icon 等噪音关键词，尺寸过滤 <100px，语义加分 hero/featured 等）→ 保底最大图。支持 `data-src` 懒加载降级。

### 链接预览骨架图

卡片加载中使用 SwiftUI `.redacted(reason: .placeholder)` 实现骨架屏，利用已知缩略图尺寸避免布局抖动。不用 ProgressView 转圈。

### 提示音时机

- **复制提示音**：`changeCount` 变化瞬间响（不等 debounce/去重）
- **粘贴提示音**：`simulatePaste()` 方法第一行响

### 自动关闭面板

面板失焦通过 `NSWindow.didResignKeyNotification` 自动收起。拖拽开始时调用 `beginDragThrough()`，先 `orderOut` 面板并临时允许鼠标事件穿透，避免覆盖层截断目标应用的拖拽接收。

## GitHub Actions

- `.github/workflows/tests.yml`：`main` push 和 pull request 自动触发，执行 `mise run check`，与本地验证入口同源
- `.github/workflows/release-build-verification.yml`：仅 `workflow_dispatch` 手动触发，执行 `mise run check`；CI 不持有稳定签名私钥，不生成或上传正式 DMG

## macOS 26 Specifics

- **LaunchPad 已更名 Apps**：路径 `/System/Applications/Apps.app`
- **Liquid Glass API**：`NSGlassEffectView` 当前 beta 阶段在透明 NSPanel 中渲染异常，降级用 `NSVisualEffectView(.hudWindow)`
- **辅助功能授权**：macOS 26 强制要求跨进程键盘事件授权，只有 `.privateState` + `postToPid` 是最小权限方案

<!-- workspace-policy:start hash=2b7fa55c1aed -->
## 跨项目统一规则

以下区块由私有 `workspace-meta` 生成；项目专属规则请写在区块外。

### 协作

- [LANG-001] 文档、提交标题和用户可见文案默认使用中文。

### Git

- [GIT-001] 提交使用 Conventional Commits，格式为 `<type>(<optional-scope>): <中文说明>`，标题不以句号结尾。
- [GIT-002] 未明确要求时不要自动提交；需要提交时先检查 status、diff 和近期提交风格。
- [GIT-003] 禁止使用 `--no-verify`，不得擅自 amend，也不得添加 Co-Authored-By 或其他 AI/工具署名 trailer。

### 安全

- [SAFE-001] 保留用户已有和无关改动，不做顺手重构，不使用破坏性 Git 或文件操作。
- [SAFE-002] 不得提交 `.env`、密钥、个人数据、日志、报告、缓存或构建产物。

### 验证

- [VERIFY-001] 修改后运行仓库声明的统一验证入口；涉及页面流程时补跑对应 E2E。

### 依赖

- [DEPS-001] 改动保持最小，不引入项目基线之外的新框架、构建工具或生产依赖，除非用户明确要求。

### 文档

- [DOCS-001] 行为、命令或部署方式变化时同步 README 和相关文档，不保留过期引用。

### 工具链

- [MISE-001] 先运行 `mise tasks` 查看入口；构建、测试和部署统一使用 `mise run <task>`，不绕过 mise 手拼命令。

### macOS 应用

- [SWIFT-001] 使用 SwiftPM executable（swift-tools 6.0）和既有脚本组装应用，不新增 Xcode project。
- [SWIFT-002] 保持 Nekutai 自签名链路与 `com.nekutai.*` bundle id，严禁 ad-hoc 签名。
- [SWIFT-003] 新增 shell 脚本纳入 `lint:scripts`；发布继续使用既有 release.sh、DMG 和 GitHub Release 流程。
<!-- workspace-policy:end -->
