import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Quartz

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Badge {
        static let countCornerRadius: CGFloat = UIConstants.Radius.button
        static let countPadding: CGFloat = 7
        static let countSize: CGFloat = 24
    }
    enum Card {
        static let animationDuration = UIConstants.Motion.fast
        static let appIconSize: CGFloat = 72
        static let contentHorizontalPadding: CGFloat = 10
        static let cornerRadius: CGFloat = UIConstants.Radius.card
        static let favoriteNoteActionSize: CGFloat = 24
        static let favoriteNoteBottomPadding: CGFloat = 12
        static let favoriteNoteHeight: CGFloat = 24
        static let headerHeight: CGFloat = 48
        static let headerThemeLeadingOpacity: Double = 0.74
        static let headerThemeTrailingOpacity: Double = 0.58
        static let hoverActionCornerRadius: CGFloat = UIConstants.Radius.sm
        static let iconShadowOpacity: Double = 0.30
        static let iconShadowRadius: CGFloat = 8
        static let iconShadowY: CGFloat = 3
        static let hoverActionIconSize: CGFloat = UIConstants.TypeSize.caption2
        static let hoverActionReserveWidth: CGFloat = 68
        static let hoverActionSize: CGFloat = 20
        static let hoverActionSpacing: CGFloat = 4
        static let hoverBorderOpacity: CGFloat = 0.30
        static let idleBorderOpacity: CGFloat = 0.22
        static let noteAccentStrokeOpacity: Double = 0.18
        static let noteIdleFillOpacity: Double = 0.035
        static let pasteScale: CGFloat = 0.95
        static let selectedBorderWidth: CGFloat = UIConstants.Stroke.emphasis
    }
}

// MARK: - 剪贴板卡片视图
struct ClipboardCardView: View {

    let item: ClipboardItem
    let isSelected: Bool
    let cmdBadgeIndex: Int?
    @Binding var selectedIds: Set<UUID>
    let onTap: (ClipboardItem) -> Void
    let onPin: (ClipboardItem, Set<UUID>) -> Void
    let onDelete: (ClipboardItem) -> Void

    @AppStorage(UserDefaultsKeys.language) private var language = ""
    @AppStorage(UserDefaultsKeys.cardClickMode) private var cardClickModeRaw = CardClickMode.default.rawValue
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appIcon: NSImage?
    @State private var themeColor: Color = .accentColor
    @State private var usesDarkHeaderForeground = AppIconProvider.prefersDarkForeground(on: .controlAccentColor)
    @State private var didPaste = false
    @State private var isHovered = false
    @State private var hoverAction: CardHoverAction? = nil
    @State private var isEditingFavoriteNote = false

    private enum CardHoverAction {
        case favorite
        case copy
        case delete
    }
    @State private var favoriteNoteDraft = ""
    @State private var isFavoriteNoteHovered = false
    @State private var isFavoriteNoteCommitHovered = false
    @State private var isFavoriteNoteCancelHovered = false
    @State private var isFavoriteNoteDeleteHovered = false
    @FocusState private var favoriteNoteFocused: Bool

    /// 链接预览版本号（递增触发重绘，配合计算属性从缓存读取）
    @State private var previewLoadTrigger = 0

    // 异步加载状态 — 避免主线程同步 I/O 触发 TCC 死锁
    @State private var asyncFilePreview: NSImage?
    @State private var asyncFileIcons: [URL: NSImage] = [:]
    @State private var asyncFileSizes: [URL: Int64] = [:]
    @State private var missingFileURLs: Set<URL> = []

    /// 路径 → NSImage 缓存，避免重绘时重复创建实例导致闪烁
    private nonisolated(unsafe) static let imageCache = NSCache<NSString, NSImage>()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        return f
    }()

    private var cardClickMode: CardClickMode {
        CardClickMode.resolved(stored: cardClickModeRaw)
    }

    var body: some View {
        cardBase
            .overlay(alignment: .bottomTrailing) {
                if showHoverActions {
                    hoverActionBar
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.instant), value: showHoverActions)
            .onHover { isHovered = $0 }
            .onTapGesture {
                handlePrimaryClick()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(isSelected ? L10n["card.selected"] : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction {
                handlePrimaryClick()
            }
            .accessibilityAction(named: Text(item.isPinned ? L10n["context.unpin"] : L10n["context.pin"])) {
                onPin(item, selectedIds)
            }
            .accessibilityAction(named: Text(L10n["context.copy"])) {
                copyItem()
            }
            .accessibilityAction(named: Text(L10n["context.delete"])) {
                onDelete(item)
            }
            .overlay(
                RightClickDetector(
                    onViewReady: { CardPreviewAnchorRegistry.register(item.id, view: $0) },
                    onRightClick: { view, event in
                        _ = language
                        showContextMenu(with: event, for: view)
                    }
                )
            )
            .onAppear {
                // 禁用隐式动画：否则会吃到托盘入场 spring，主题色/图标/缩略图像「从简陋长出来」。
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    loadAppInfo()
                    applyCachedFilePreviewIfAvailable()
                }
            }
            .onDisappear { CardPreviewAnchorRegistry.unregister(item.id) }
            .task(id: item.id) { await fetchLinkPreviewIfNeeded() }
            .onChange(of: item.content) { old, _ in
                Self.imageCache.removeObject(forKey: old as NSString)
            }
            .task(id: filePreviewTaskID) {
                guard item.sourceFormat == .image || item.sourceFormat == .fileURL else { return }
                await loadFilePreviewsIfNeeded()
            }
    }

    private var showHoverActions: Bool {
        isHovered && !isEditingFavoriteNote && !isFavoriteNoteHovered
    }

    private var accessibilitySummary: String {
        var parts = [cardTypeLabel]
        if let preview = accessibilityContentPreview {
            parts.append(preview)
        }
        if item.isHandoff {
            parts.append(L10n["card.handoff_label"])
        } else if let appName = item.appName, !appName.isEmpty {
            parts.append(appName)
        }
        parts.append(formattedTime)
        return parts.joined(separator: ", ")
    }

    private var accessibilityContentPreview: String? {
        let raw: String?
        switch item.sourceFormat {
        case .image:
            raw = item.textAnnotation
        case .fileURL:
            let names = item.content
                .components(separatedBy: .newlines)
                .compactMap { URL(string: $0)?.lastPathComponent.removingPercentEncoding }
                .filter { !$0.isEmpty }
            raw = names.isEmpty ? nil : names.prefix(3).joined(separator: ", ")
        case .text, .rtf, .html:
            raw = item.linkTitle ?? item.content
        }

        guard let raw else { return nil }
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(160))
    }

    /// 卡片基础渲染（样式 + 内容，不含手势和生命周期）
    private var cardBase: some View {
        VStack(spacing: 0) {
            topBar
                .layoutPriority(2)
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Local.Card.contentHorizontalPadding)
                .padding(.top, UIConstants.Card.contentVerticalPadding)
                // 有备注时收紧底部，避免域名与备注之间再空出一整段 content padding
                .padding(.bottom, contentBottomPadding)
                .layoutPriority(0)
                .clipped()
            favoriteNoteStrip
                .padding(.horizontal, Local.Card.contentHorizontalPadding)
                .padding(.bottom, Local.Card.favoriteNoteBottomPadding)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            footerBar
                .padding(.horizontal, Local.Card.contentHorizontalPadding)
                .padding(.bottom, UIConstants.Card.footerBottomPadding)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
        .frame(width: UIConstants.Card.size, height: UIConstants.Card.size)
        .background(cardSurface)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: Local.Card.cornerRadius, style: .continuous))
        // Inset stroke only: centered `.stroke` bleeds outside the card and gets clipped
        // by the horizontal strip ScrollView (edge cards sit flush with no side padding).
        .overlay(
            RoundedRectangle(cornerRadius: Local.Card.cornerRadius, style: .continuous)
                .strokeBorder(cardChromeBorderColor, lineWidth: cardChromeBorderWidth)
                .animation(reduceMotion ? nil : .easeInOut(duration: Local.Card.animationDuration), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.paste), value: didPaste)
        )
        .overlay(alignment: .bottomTrailing) {
            if let idx = cmdBadgeIndex {
                cmdBadge(idx)
                    .transition(.scale(scale: 0.74, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Local.Card.animationDuration), value: isHovered)
        .scaleEffect(reduceMotion ? 1 : (didPaste ? Local.Card.pasteScale : 1.0))
        .animation(reduceMotion ? nil : .spring(response: UIConstants.Motion.fast, dampingFraction: UIConstants.Motion.pasteDamping), value: didPaste)
        .animation(reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.fast), value: item.isPinned)
        .animation(reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.fast), value: isEditingFavoriteNote)
        .contentShape(RoundedRectangle(cornerRadius: Local.Card.cornerRadius))
    }

    // MARK: - 打开文件

    /// 可打开的 URL（文件路径或文本中的 URL）。多文件时返回第一个存在的文件，全缺失返回 nil。
    var openableURL: URL? {
        switch item.sourceFormat {
        case .fileURL:
            return existingFileURLs.first
        case .image:
            return imageOpenableURL
        case .text, .rtf, .html:
            return detectedLink
        }
    }

    /// 是否为文本类（text / rtf / html）—— 可预览、可分享
    var isTextType: Bool {
        item.sourceFormat == .text || item.sourceFormat == .rtf || item.sourceFormat == .html || item.tags.isURL
    }

    // MARK: - DisplayMode（统一切换展示类型）

    /// 从来源格式和语义标记派生展示模式（逻辑见 `DisplayMode.resolve`）
    var displayMode: DisplayMode {
        DisplayMode.resolve(item: item, hasMissingFiles: !missingFileURLs.isEmpty)
    }

    /// Single chrome stroke for all card states (no glow / dual-ring stack).
    private var cardChromeBorderColor: Color {
        if didPaste { return Color.green }
        if isSelected { return PastryPalette.warmAccent }
        if isHovered { return .white.opacity(Local.Card.hoverBorderOpacity) }
        return .white.opacity(Local.Card.idleBorderOpacity)
    }

    /// Keep selection visible across light and dark desktops without adding an outer glow.
    @ViewBuilder
    private var cardSurface: some View {
        if isSelected && !didPaste {
            Color(nsColor: NSColor.windowBackgroundColor)
                .overlay(PastryPalette.warmAccent.opacity(UIConstants.Overlay.accentFillOpacity))
        } else {
            Color(nsColor: NSColor.windowBackgroundColor)
        }
    }

    private var cardChromeBorderWidth: CGFloat {
        if didPaste || isSelected {
            return Local.Card.selectedBorderWidth
        }
        return UIConstants.Stroke.hairline
    }


    /// ⌘+数字角标 — 按住 ⌘ 时在卡片右下角显示序号
    private func cmdBadge(_ idx: Int) -> some View {
        Text("\(idx)")
            .font(.system(size: UIConstants.TypeSize.callout, weight: .heavy, design: .rounded))
            .foregroundColor(PastryPalette.warmInk)
            .frame(width: Local.Badge.countSize, height: Local.Badge.countSize)
            .background(
                RoundedRectangle(cornerRadius: Local.Badge.countCornerRadius, style: .continuous)
                    .fill(PastryPalette.warmAccent)
            )
            .padding(Local.Badge.countPadding)
    }

    // MARK: - 顶部栏（始终使用主题色背景）

    private var topBar: some View {
        HStack(spacing: 0) {
            Image(systemName: item.sourceFormat.iconName)
                .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                .foregroundColor(headerPrimaryForeground)
                .padding(.leading, Local.Card.contentHorizontalPadding)

            Text(cardTypeLabel)
                .font(.system(size: UIConstants.TypeSize.caption, weight: .semibold))
                .foregroundColor(headerSecondaryForeground)
                .lineLimit(1)
                .padding(.leading, 5)

            if isSelected && differentiateWithoutColor {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: UIConstants.TypeSize.caption, weight: .semibold))
                    .foregroundColor(headerPrimaryForeground)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }

            Spacer()
        }
        .frame(height: Local.Card.headerHeight)
        .background(
            LinearGradient(
                colors: [themeColor.opacity(Local.Card.headerThemeLeadingOpacity), themeColor.opacity(Local.Card.headerThemeTrailingOpacity)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(Color.white.opacity(UIConstants.OnDark.fillSubtle))
        .clipped()
        .overlay(alignment: .topTrailing) {
            appIconOverlay
        }
    }

    private var cardTypeLabel: String {
        if item.tags.isURL { return L10n["filetype.link"] }
        if item.tags.isMultiFile { return L10n["filter.type.fileURL"] }
        return item.sourceFormat.label
    }

    private var headerPrimaryForeground: Color {
        usesDarkHeaderForeground
            ? PastryPalette.ink.opacity(UIConstants.OnDark.textPrimary)
            : Color.white.opacity(UIConstants.OnDark.textPrimary)
    }

    private var headerSecondaryForeground: Color {
        usesDarkHeaderForeground
            ? PastryPalette.ink.opacity(UIConstants.OnDark.textSecondary)
            : Color.white.opacity(UIConstants.OnDark.textSecondary)
    }

    /// 应用图标 — 60×60，标题栏内垂直居中，右移 50% 让一半溢出卡片被裁切
    @ViewBuilder
    private var appIconOverlay: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Local.Card.cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(Local.Card.iconShadowOpacity), radius: Local.Card.iconShadowRadius, x: 0, y: Local.Card.iconShadowY)
            } else if item.isHandoff {
                // Handoff 来源：SF Symbol 图标
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: Local.Card.appIconSize * 0.55, weight: .light))
                    .foregroundColor(headerSecondaryForeground)
            } else {
                Color.clear
            }
        }
        .frame(width: Local.Card.appIconSize, height: Local.Card.appIconSize)
        .offset(x: 12, y: (Local.Card.headerHeight - Local.Card.appIconSize) / 2 - 2)
        .animation(reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.medium), value: appIcon != nil)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        switch item.sourceFormat {
        case .image:   imagePreview
        case .fileURL: fileURLContent
        case .html:    htmlWithImagePreview
        default:
            if isMultiURL { multiLinkContent(detectedLinks) }
            else if item.tags.isURL, let url = detectedLink { linkContent(url) }
            else { textPreview }
        }
    }

    // MARK: - 链接预览（缩略图 + 标题 + 描述 + 域名 —— 始终用卡片框架，字段独立降级）

    @ViewBuilder
    private func linkContent(_ url: URL) -> some View {
        let text = Self.linkCardText(url: url, preview: linkPreview)
        ClipboardLinkContentView(
            preview: linkPreview,
            text: text,
            compactMedia: showsFavoriteNoteStrip
        )
    }

    /// 备注条可见（编辑中或已有备注）
    private var showsFavoriteNoteStrip: Bool {
        isEditingFavoriteNote || favoriteNoteText != nil
    }

    /// 图片卡为 hover 操作预留独立底部空间；其他卡片保持既有静止布局。
    private var contentBottomPadding: CGFloat {
        if showsFavoriteNoteStrip { return 2 }
        if item.sourceFormat == .image { return Local.Card.hoverActionSize }
        return UIConstants.Card.contentVerticalPadding
    }

    @ViewBuilder
    private var imagePreview: some View {
        let nsImage: NSImage? = {
            // 缓存命中 (已在后台加载过)
            let key = item.content as NSString
            if let cached = Self.imageCache.object(forKey: key) { return cached }
            // 异步加载中或失败 → 返回 nil，用 asyncFilePreview 的 placeholder
            return nil
        }()
        ClipboardImageContentView(image: asyncFilePreview ?? nsImage, annotation: item.textAnnotation)
    }

    // MARK: - 文件预览

    /// 文件预览策略（扩展：加 case + 在 filePreviewStyle 中匹配即可）
    enum FilePreviewStyle {
        case thumbnail   // 图片 → NSImage 缩略图
        case systemIcon  // 其他 → NSWorkspace 系统图标
    }

    nonisolated static func filePreviewStyle(for url: URL) -> FilePreviewStyle {
        if imageExtensions.contains(url.pathExtension.lowercased()) { return .thumbnail }
        return .systemIcon
    }

    @ViewBuilder
    private var fileURLContent: some View {
        FilePreviewContent(
            urls: fileURLs,
            missingURLs: missingFileURLs,
            thumbnailImage: asyncFilePreview,
            fileIcons: asyncFileIcons,
            fileSizes: asyncFileSizes,
            styleForURL: Self.filePreviewStyle(for:)
        )
    }

    private var filePreviewTaskID: String {
        "\(item.id.uuidString):\(item.sourceFormat.rawValue):\(item.content)"
    }

    /// 异步加载文件预览 — 避免主线程同步 I/O 触发 TCC 权限弹窗死锁
    private func loadFilePreviewsIfNeeded() async {
        guard item.sourceFormat == .image || item.sourceFormat == .fileURL else { return }

        // 图片类型 — 异步加载 NSImage
        if item.sourceFormat == .image {
            let path = item.content
            let key = path as NSString

            // 文件已删除 → 清除缓存，显示缺失状态
            if !FileManager.default.fileExists(atPath: path) {
                Self.imageCache.removeObject(forKey: key)
                await MainActor.run {
                    missingFileURLs.insert(URL(fileURLWithPath: path))
                    asyncFilePreview = nil
                }
                return
            }

            if let cached = Self.imageCache.object(forKey: key) {
                guard !Task.isCancelled else { return }
                asyncFilePreview = cached
                return
            }
            let imageLoadTask = Task.detached(priority: .userInitiated, operation: { () -> NSImage? in
                guard !Task.isCancelled else { return nil }
                return NSImage(contentsOfFile: path)
            })
            let img = await withTaskCancellationHandler {
                await imageLoadTask.value
            } onCancel: {
                imageLoadTask.cancel()
            }
            guard !Task.isCancelled else { return }
            if let img = img {
                Self.imageCache.setObject(img, forKey: key)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    asyncFilePreview = img
                }
            }
            return
        }

        // 文件 URL 类型 — 异步检查存在性并加载图标和文件大小
        if item.sourceFormat == .fileURL {
            let urls = fileURLs
            let fileLoadTask = Task.detached(priority: .userInitiated, operation: { () -> (missing: Set<URL>, icons: [(URL, NSImage, Bool)], sizes: [URL: Int64]) in
                var missing: Set<URL> = []
                var icons: [(URL, NSImage, Bool)] = []
                var sizes: [URL: Int64] = [:]
                for url in urls {
                    guard !Task.isCancelled else { break }
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        missing.insert(url)
                        continue
                    }

                    // 收集文件大小
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let fileSize = attrs[.size] as? Int64 {
                        sizes[url] = fileSize
                    }

                    let style = Self.filePreviewStyle(for: url)
                    let cacheKey: NSString
                    let needsThumbnail: Bool
                    switch style {
                    case .thumbnail:
                        cacheKey = url.path as NSString
                        needsThumbnail = true
                    case .systemIcon:
                        cacheKey = "icon:\(url.path)" as NSString
                        needsThumbnail = false
                    }

                    if let cached = Self.imageCache.object(forKey: cacheKey) {
                        icons.append((url, cached, needsThumbnail))
                        continue
                    }

                    let loaded: NSImage? = needsThumbnail
                        ? NSImage(contentsOfFile: url.path)
                        : NSWorkspace.shared.icon(forFile: url.path)

                    if let loaded = loaded {
                        Self.imageCache.setObject(loaded, forKey: cacheKey)
                        icons.append((url, loaded, needsThumbnail))
                    }
                }
                return (missing, icons, sizes)
            })
            let result = await withTaskCancellationHandler {
                await fileLoadTask.value
            } onCancel: {
                fileLoadTask.cancel()
            }

            guard !Task.isCancelled else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                missingFileURLs = result.missing
                asyncFileSizes = result.sizes
                for (url, icon, isThumbnail) in result.icons {
                    if isThumbnail { asyncFilePreview = icon }
                    else { asyncFileIcons[url] = icon }
                }
            }
        }
    }

    // MARK: - 文件列表（多文件 → 小图标行）

    // MARK: - 多链接列表（多个 URL 换行复制时的展示）

    @ViewBuilder
    private func multiLinkContent(_ urls: [URL]) -> some View {
        ClipboardMultiLinkContentView(urls: urls)
    }

    nonisolated static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif",
    ]

    private var textPreview: some View {
        Text(previewText).lineLimit(7).font(.system(size: UIConstants.TypeSize.label)).foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// HTML 图文预览：按 segments 原始顺序渲染
    @ViewBuilder
    private var htmlWithImagePreview: some View {
        if let segs = item.segments, !segs.isEmpty {
            ClipboardHTMLSegmentsContentView(segments: segs)
        } else if isMultiURL {
            multiLinkContent(detectedLinks)
        } else if item.tags.isURL, let url = detectedLink {
            linkContent(url)
        } else {
            textPreview
        }
    }

    // MARK: - 场景备注

    @ViewBuilder
    private var favoriteNoteStrip: some View {
        if isEditingFavoriteNote || favoriteNoteText != nil {
            Group {
                if isEditingFavoriteNote {
                    HStack(spacing: 5) {
                        Image(systemName: "note.text")
                            .font(.system(size: UIConstants.TypeSize.caption2, weight: .semibold))
                            .foregroundColor(themeColor)

                        TextField(L10n["favorite_note.placeholder"], text: $favoriteNoteDraft)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled(true)
                            .font(.system(size: UIConstants.TypeSize.caption))
                            .foregroundColor(.primary)
                            .focused($favoriteNoteFocused)
                            .onSubmit { commitFavoriteNote() }
                            .onKeyPress(.escape) {
                                cancelFavoriteNoteEditing()
                                return .handled
                            }
                            .onChange(of: favoriteNoteFocused) { _, focused in
                                if focused {
                                    OverlayPanelManager.shared.keyboardOwner = .favoriteNoteEditor
                                }
                            }

                        Button(action: commitFavoriteNote) {
                            Image(systemName: "checkmark")
                                .font(.system(size: UIConstants.TypeSize.caption2, weight: .bold))
                                .frame(width: Local.Card.favoriteNoteActionSize, height: Local.Card.favoriteNoteActionSize)
                                .background(
                                    Circle()
                                        .fill(isFavoriteNoteCommitHovered ? themeColor.opacity(UIConstants.OnDark.fillHover) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(themeColor)
                        .onHover { hovering in
                            isFavoriteNoteCommitHovered = hovering
                            if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                        }

                        Button(action: cancelFavoriteNoteEditing) {
                            Image(systemName: "xmark")
                                .font(.system(size: UIConstants.TypeSize.caption2, weight: .bold))
                                .frame(width: Local.Card.favoriteNoteActionSize, height: Local.Card.favoriteNoteActionSize)
                                .background(
                                    Circle()
                                        .fill(isFavoriteNoteCancelHovered ? Color.black.opacity(UIConstants.OnDark.fillSubtle) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .onHover { hovering in
                            isFavoriteNoteCancelHovered = hovering
                            if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                            .fill(themeColor.opacity(UIConstants.OnDark.fillSubtle))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                            .stroke(themeColor.opacity(Local.Card.noteAccentStrokeOpacity), lineWidth: UIConstants.Stroke.hairline)
                    )
                    .onAppear {
                        OverlayPanelManager.shared.keyboardOwner = .favoriteNoteEditor
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            guard isEditingFavoriteNote else { return }
                            favoriteNoteFocused = true
                        }
                    }
                    .onDisappear {
                        if OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
                            OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
                        }
                    }
                } else {
                    HStack(spacing: 5) {
                        Button(action: beginFavoriteNoteEditing) {
                            HStack(spacing: 5) {
                                Image(systemName: "note.text")
                                    .font(.system(size: UIConstants.TypeSize.caption2, weight: .semibold))
                                    .foregroundColor(themeColor)
                                Text(favoriteNoteText ?? L10n["favorite_note.add"])
                                    .font(.system(size: UIConstants.TypeSize.caption))
                                    .foregroundColor(favoriteNoteText == nil ? .secondary : .primary.opacity(UIConstants.OnLight.textStrong))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isFavoriteNoteHovered {
                            Button(action: clearFavoriteNote) {
                                Image(systemName: "xmark")
                                    .font(.system(size: UIConstants.TypeSize.caption2, weight: .bold))
                                    .frame(width: Local.Card.favoriteNoteActionSize, height: Local.Card.favoriteNoteActionSize)
                                    .background(
                                        Circle()
                                            .fill(isFavoriteNoteDeleteHovered
                                                  ? Color.black.opacity(UIConstants.OnDark.fillSubtle)
                                                  : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help(L10n["favorite_note.delete"])
                            .accessibilityLabel(L10n["favorite_note.delete"])
                            .onHover { hovering in
                                isFavoriteNoteDeleteHovered = hovering
                                if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                            .fill(isFavoriteNoteHovered ? themeColor.opacity(UIConstants.OnDark.fillSubtle) : Color.black.opacity(Local.Card.noteIdleFillOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                            .stroke(isFavoriteNoteHovered ? themeColor.opacity(Local.Card.noteAccentStrokeOpacity) : Color.clear, lineWidth: UIConstants.Stroke.hairline)
                    )
                    .onHover { hovering in
                        isFavoriteNoteHovered = hovering
                        if !hovering { isFavoriteNoteDeleteHovered = false }
                    }
                    .animation(.easeInOut(duration: UIConstants.Motion.fast), value: isFavoriteNoteHovered)
                }
            }
            .frame(height: Local.Card.favoriteNoteHeight)
            .onReceive(NotificationCenter.default.publisher(for: .overlayCancelFavoriteNoteEditing)) { _ in
                guard isEditingFavoriteNote else { return }
                cancelFavoriteNoteEditing()
            }
        }
    }

    var favoriteNoteText: String? {
        let trimmed = item.favoriteNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func beginFavoriteNoteEditing() {
        favoriteNoteDraft = favoriteNoteText ?? ""
        isEditingFavoriteNote = true
        OverlayPanelManager.shared.keyboardOwner = .favoriteNoteEditor
    }

    private func commitFavoriteNote() {
        StoreManager.shared.updateFavoriteNote(item.id, note: favoriteNoteDraft)
        isEditingFavoriteNote = false
        favoriteNoteFocused = false
        if OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
        }
    }

    private func cancelFavoriteNoteEditing() {
        favoriteNoteDraft = favoriteNoteText ?? ""
        isEditingFavoriteNote = false
        favoriteNoteFocused = false
        OverlayPanelManager.shared.noteFavoriteNoteEditingCancelled()
    }

    func clearFavoriteNote() {
        StoreManager.shared.updateFavoriteNote(item.id, note: nil)
        isFavoriteNoteHovered = false
        isFavoriteNoteDeleteHovered = false
    }

    // MARK: - 底部栏

    private var footerBar: some View {
        HStack(spacing: 4) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: UIConstants.TypeSize.caption2, weight: .semibold))
                    .foregroundColor(themeColor)
                Text("·").font(.caption2).foregroundColor(.secondary)
            }
            Text(formattedTime).font(.system(size: UIConstants.TypeSize.caption2)).foregroundColor(.secondary)
            if item.isHandoff {
                Text("·").font(.caption2).foregroundColor(.secondary)
                Text(L10n["card.handoff_label"]).font(.system(size: UIConstants.TypeSize.caption2)).foregroundColor(.secondary).lineLimit(1)
            } else if let app = item.appName {
                Text("·").font(.caption2).foregroundColor(.secondary)
                Text(app).font(.system(size: UIConstants.TypeSize.caption2)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: showHoverActions ? Local.Card.hoverActionReserveWidth : 0)
        }
    }

    // MARK: - Hover 轻操作

    private var hoverActionBar: some View {
        HStack(spacing: Local.Card.hoverActionSpacing) {
            hoverActionButton(
                action: .favorite,
                icon: item.isPinned ? "pin.fill" : "pin",
                label: item.isPinned ? L10n["context.unpin"] : L10n["context.pin"],
                tint: item.isPinned ? themeColor : .secondary
            ) {
                onPin(item, selectedIds)
            }
            hoverActionButton(
                action: .copy,
                icon: AppIcons.copy,
                label: L10n["context.copy"],
                tint: .secondary
            ) {
                copyItem()
            }
            hoverActionButton(
                action: .delete,
                icon: AppIcons.delete,
                label: L10n["context.delete"],
                tint: PastryPalette.dangerStrong
            ) {
                onDelete(item)
            }
        }
        .padding(.trailing, Local.Card.contentHorizontalPadding)
        .padding(.bottom, UIConstants.Card.footerBottomPadding)
    }

    private func hoverActionButton(
        action: CardHoverAction,
        icon: String,
        label: String,
        tint: Color,
        perform: @escaping () -> Void
    ) -> some View {
        let isActionHovered = hoverAction == action
        return Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: Local.Card.hoverActionIconSize, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: Local.Card.hoverActionSize, height: Local.Card.hoverActionSize)
                .background(
                    RoundedRectangle(cornerRadius: Local.Card.hoverActionCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(isActionHovered ? UIConstants.OnDark.fillHover : UIConstants.OnDark.fillSubtle))
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .scaleEffect(isActionHovered ? 1.06 : 1.0)
        .animation(.easeOut(duration: UIConstants.Motion.instant), value: isActionHovered)
        .onHover { hovering in
            if hovering {
                hoverAction = action
                NSCursor.arrow.push()
            } else {
                if hoverAction == action { hoverAction = nil }
                NSCursor.pop()
            }
        }
    }

    // MARK: - 时间戳

    private var formattedTime: String {
        let now = Date()
        let diff = now.timeIntervalSince(item.timestamp)
        if diff < 60 { return L10n["time.just_now"] }
        else if diff < 3600 {
            let count = Int(diff / 60)
            return String(format: L10n[count == 1 ? "time.minute_ago" : "time.minutes_ago"], count)
        } else if diff < 86400 {
            let count = Int(diff / 3600)
            return String(format: L10n[count == 1 ? "time.hour_ago" : "time.hours_ago"], count)
        } else if diff < 604800 {
            let count = Int(diff / 86400)
            return String(format: L10n[count == 1 ? "time.day_ago" : "time.days_ago"], count)
        }
        Self.timeFormatter.locale = Locale(identifier: L10n.currentLanguageIdentifier)
        if Self.timeFormatter.dateFormat != L10n["time.date_format"] {
            Self.timeFormatter.dateFormat = L10n["time.date_format"]
        }
        return Self.timeFormatter.string(from: item.timestamp)
    }

    // MARK: - 链接

    struct LinkCardText: Equatable {
        let title: String
        let description: String?
        let host: String
        let titleLineLimit: Int
    }

    static func linkCardText(url: URL, preview: LinkPreviewLoader.Preview?) -> LinkCardText {
        let host = normalizedLinkText(preview?.host) ?? url.host ?? ""
        let rawTitle = normalizedLinkText(preview?.title)
        let rawDescription = normalizedLinkText(preview?.description)
        let title = sanitizedLinkTitle(rawTitle, host: host) ?? fallbackLinkTitle(for: url)
        let usesCompactDescription = title.count <= 34
        let description = usesCompactDescription ? rawDescription : nil

        return LinkCardText(
            title: title,
            description: description,
            host: host,
            titleLineLimit: description == nil ? 2 : 1
        )
    }

    private static func normalizedLinkText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func sanitizedLinkTitle(_ title: String?, host: String) -> String? {
        guard var title else { return nil }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let siteNames = [host, bareHost]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for site in siteNames {
            for separator in [" - ", " | ", " · ", " — "] where title.hasSuffix(separator + site) {
                title.removeLast((separator + site).count)
                return normalizedLinkText(title)
            }
        }
        return title
    }

    private static func fallbackLinkTitle(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return host }
        return "\(host)/\(path)"
    }

    private var detectedLink: URL? {
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPS(url) }
        if let d = Self.linkDetector,
           let m = d.firstMatch(in: item.content, range: NSRange(item.content.startIndex..., in: item.content)),
           let url = m.url, let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPS(url) }
        return nil
    }

    /// NSDataDetector 返回 http:// 裸域名时升级为 https://，避免重定向和不必要的 HTTP 请求
    private func upgradeToHTTPS(_ url: URL) -> URL {
        DisplayMode.upgradeToHTTPS(url)
    }

    /// 链接预览：缓存优先，body 求值时同步读取，零帧延迟
    private var linkPreview: LinkPreviewLoader.Preview? {
        _ = previewLoadTrigger
        guard let url = detectedLink else { return nil }
        return LinkPreviewLoader.shared.cachedPreview(for: url.absoluteString)
    }

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func fetchLinkPreviewIfNeeded() async {
        guard let url = detectedLink else { return }
        if linkPreview != nil { return }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        await withCheckedContinuation { continuation in
            LinkPreviewLoader.shared.load(url: url) { preview in
                guard let preview else { continuation.resume(); return }
                let title = preview.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    StoreManager.shared.updateLinkTitle(item.id, linkTitle: title)
                }
                self.previewLoadTrigger &+= 1
                continuation.resume()
            }
        }
    }

    // MARK: - 辅助

    private var previewText: String {
        let t = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 240 ? String(t.prefix(240)) + "…" : t
    }

    var fileURLs: [URL] {
        item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// 所有实际存在于磁盘的文件 URL（从异步加载的 missingFileURLs 反推，不阻塞主线程）
    var existingFileURLs: [URL] {
        guard item.sourceFormat == .fileURL || item.sourceFormat == .image else { return [] }
        if item.sourceFormat == .image, !item.content.contains("\n") {
            return imageOpenableURL.map { [$0] } ?? []
        }
        // 异步检测还没跑完 → 暂时当作全部存在（不触发 TCC）
        return fileURLs.filter { !missingFileURLs.contains($0) }
    }

    private var imageOpenableURL: URL? {
        if item.content.contains("\n") {
            return fileURLs.first { FileManager.default.fileExists(atPath: $0.path) }
        }
        let preferredPath = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
        let url = URL(fileURLWithPath: preferredPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 是否为多文件条目
    var isMultiFile: Bool {
        item.sourceFormat == .fileURL && item.content.contains("\n")
    }

    /// 内容中的全部 http/https URL
    var detectedLinks: [URL] {
        DisplayMode.detectedLinks(from: item)
    }

    /// 是否为多链接条目
    var isMultiURL: Bool {
        item.tags.isURL && detectedLinks.count > 1
    }

    private func loadAppInfo() {
        let provider = AppIconProvider.shared
        let name: String? = item.isHandoff ? "📱 Handoff" : item.appName
        let isHandoff = item.isHandoff

        // 命中缓存则同步贴上，首帧就与正式版一样完整；未命中再后台补，避免扫盘卡入场。
        if let cached = provider.cachedThemeColor(for: name) {
            themeColor = Color(nsColor: cached)
            usesDarkHeaderForeground = AppIconProvider.prefersDarkForeground(on: cached)
        }
        if isHandoff {
            appIcon = nil
        } else if let cached = provider.cachedIcon(for: name) {
            appIcon = cached
        }

        let needsColor = provider.cachedThemeColor(for: name) == nil
        let needsIcon = !isHandoff && provider.cachedIcon(for: name) == nil
        guard needsColor || needsIcon else { return }

        Task {
            let (color, icon) = await Task.detached(priority: .userInitiated) {
                let color = provider.themeColor(for: name)
                let icon: NSImage? = isHandoff ? nil : provider.icon(for: name)
                return (color, icon)
            }.value
            guard !Task.isCancelled else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                themeColor = Color(nsColor: color)
                usesDarkHeaderForeground = AppIconProvider.prefersDarkForeground(on: color)
                if let icon {
                    appIcon = icon
                }
            }
        }
    }

    /// 打开托盘时先同步贴上已缓存的文件/图片预览，避免先空白再「长出来」。
    private func applyCachedFilePreviewIfAvailable() {
        switch item.sourceFormat {
        case .image:
            let key = item.content as NSString
            if let cached = Self.imageCache.object(forKey: key) {
                asyncFilePreview = cached
            }
        case .fileURL:
            var icons: [URL: NSImage] = [:]
            var thumbnail: NSImage?
            for url in fileURLs {
                let style = Self.filePreviewStyle(for: url)
                let cacheKey: NSString
                switch style {
                case .thumbnail:
                    cacheKey = url.path as NSString
                case .systemIcon:
                    cacheKey = "icon:\(url.path)" as NSString
                }
                guard let cached = Self.imageCache.object(forKey: cacheKey) else { continue }
                switch style {
                case .thumbnail:
                    thumbnail = cached
                case .systemIcon:
                    icons[url] = cached
                }
            }
            if !icons.isEmpty { asyncFileIcons = icons }
            if let thumbnail { asyncFilePreview = thumbnail }
        case .text, .rtf, .html:
            break
        }
    }

    private func handlePrimaryClick() {
        if isEditingFavoriteNote {
            commitFavoriteNote()
            return
        }

        // currentEvent ∪ live：onTapGesture 触发时 currentEvent 常丢 ⌘/⇧
        let flags = OverlayInteractionModel.readCardTapModifierFlags()
        let commandOrShift = flags.command || flags.shift
        switch OverlayInteractionModel.cardClickAction(
            mode: cardClickMode,
            isSelected: isSelected,
            isInMultiSelection: selectedIds.count > 1 && selectedIds.contains(item.id),
            commandOrShift: commandOrShift
        ) {
        case .select:
            onTap(item)
        case .paste:
            pasteItem()
        }
    }

    private func pasteItem() {
        didPaste = true
        DeveloperDiagnostics.record(DiagnosticsEvent.cardClickPaste)
        Task { await OverlayPanelManager.shared.hideAndPaste(item) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            didPaste = false
        }
    }

    // MARK: - 测试入口

    /// 供单元测试：扩展名 → 预览策略映射
    static func filePreviewStyleForTesting(extension ext: String) -> FilePreviewStyle {
        filePreviewStyle(for: URL(fileURLWithPath: "/tmp/test.\(ext)"))
    }

    /// 供单元测试：图片扩展名集合
    static var imageExtensionsForTesting: Set<String> { imageExtensions }

    /// 供单元测试：contentType → 是否为文本类（.text / .rtf / .html）
    static func isTextTypeForTesting(sourceFormat: SourceFormat) -> Bool {
        sourceFormat == .text || sourceFormat == .rtf || sourceFormat == .html
    }

    /// 供单元测试：文本统计（字符数 / 单词数 / 行数）
    static func textStatisticsForTesting(_ text: String) -> (chars: Int, words: Int, lines: Int) {
        let chars = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return (chars, words, lines)
    }

    /// 供单元测试：多选条目 → 拼接文本（hideAndPasteMultiple 的核心逻辑）
    static func multiSelectTextForTesting(_ items: [ClipboardItem]) -> String {
        items.compactMap { item -> String? in
            switch item.sourceFormat {
            case .text, .rtf, .html, .fileURL: return item.content
            default: return nil
            }
        }.joined(separator: "\n")
    }

    /// 供单元测试：单选拖拽 → 按类型返回 (isFile: Bool, content: String)
    static func dragPayloadForTesting(_ item: ClipboardItem) -> (isFile: Bool, content: String) {
        switch item.sourceFormat {
        case .image, .fileURL:
            return (true, item.content)
        default:
            return (false, item.content)
        }
    }

    /// 供单元测试：content → 是否为多文件条目
    static func isMultiFileForTesting(content: String, sourceFormat: SourceFormat) -> Bool {
        sourceFormat == .fileURL && content.contains("\n")
    }

    /// 供单元测试：item → openableURL 计算（单文件/多文件兼容）
    static func openableURLForTesting(_ item: ClipboardItem) -> URL? {
        switch item.sourceFormat {
        case .fileURL:
            let urls = item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            return urls.first { FileManager.default.fileExists(atPath: $0.path) }
        case .image:
            let path = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .text, .rtf, .html:
            return detectedLinkForTesting(in: item.content)
        }
    }

    /// 供单元测试：从文本中检测 URL（与 detectedLink 逻辑一致）
    private static func detectedLinkForTesting(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPSTesting(url) }
        if let d = linkDetector,
           let m = d.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let url = m.url, let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPSTesting(url) }
        return nil
    }

    /// 测试专用：http → https 升级
    private static func upgradeToHTTPSTesting(_ url: URL) -> URL {
        DisplayMode.upgradeToHTTPS(url)
    }

}
