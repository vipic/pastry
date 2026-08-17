import SwiftUI
import AppKit
import Carbon
import OSLog

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let metricMinHeight: CGFloat = 70
        static let metricPadding: CGFloat = 12
        static let navGlyphSize: CGFloat = 22
        static let navRowHeight: CGFloat = 34
        static let paneHeaderMaxWidth: CGFloat = 460
        static let rowVerticalPadding: CGFloat = 10
        static let sectionSpacing: CGFloat = 18
        static let sidebarBottomPadding: CGFloat = 14
        static let sidebarBrandIconSize: CGFloat = 40
        static let sidebarBrandSpacing: CGFloat = 10
        static let sidebarHorizontalPadding: CGFloat = 12
        static let sidebarTopPadding: CGFloat = 52
        static let sidebarWidth: CGFloat = 206
        static let sidebarOpacity: Double = 0.92
        static let windowMinHeight: CGFloat = 520
        static let windowMinWidth: CGFloat = 760
    }
}

extension Notification.Name {
    static let settingsSelectTab = Notification.Name("settingsSelectTab")
}


// MARK: - 设置视图

struct SettingsSceneView: View {

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    var soundEnabled = false

    @AppStorage(UserDefaultsKeys.cardClickMode)
    var cardClickModeRaw = CardClickMode.default.rawValue

    @AppStorage(UserDefaultsKeys.deleteRequiresConfirmation)
    var deleteRequiresConfirmation = true

    @AppStorage(UserDefaultsKeys.linkPreviewNetworkEnabled)
    var linkPreviewNetworkEnabled = false
    @AppStorage(UserDefaultsKeys.performanceLoggingEnabled)
    var performanceLoggingEnabled = false
    @AppStorage(UserDefaultsKeys.historyMaxItems)
    var historyMaxItems = HistoryRetentionPolicy.defaultMaxItems
    @AppStorage(UserDefaultsKeys.historyMaxAgeDays)
    var historyMaxAgeDays = HistoryRetentionPolicy.defaultMaxAgeDays

    @AppStorage(UserDefaultsKeys.hotkeyKeyCode)
    var hotkeyKeyCode = Int(GlobalHotkeyManager.defaultKeyCode)
    @AppStorage(UserDefaultsKeys.hotkeyModifiers)
    var hotkeyModifiers = Int(GlobalHotkeyManager.defaultModifiers)

    @State var showingClearConfirm = false
    @State var accessibilityTrusted = false
    @State var selectedTab: SettingsTab?
    @State var selectedLanguage: Language
    @State var excludedBundleIDs: [String] = []
    @State var versionUpdateState: UpdateState = .upToDate(
        version: AppVersion.displayCurrent,
        build: AppVersion.displayBuild,
        lastCheckDate: nil,
        lastReleaseNotes: nil
    )
    @State var versionReleaseNotes: String?
    @State var versionReleaseHistory: [UpdateChecker.ReleaseNote] = []
    @State var versionCurrentVersion: String?
    @State var versionLatestVersion: String?
    @State var didAutoCheckVersionInCurrentWindow = false
    @State var isVersionCheckInFlight = false
    @State var isRecordingShortcut = false
    @State var shortcutPreviewKeyCode: Int?
    @State var shortcutPreviewModifiers = 0

    enum Language: String, CaseIterable, Identifiable {
        case system
        case zhHans = "zh-Hans"
        case en
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return L10n["lang.system"]
            case .zhHans: return L10n["lang.zh_hans"]
            case .en:     return L10n["lang.en"]
            }
        }
    }

    init(initialTab: SettingsTab = .general) {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        let pref = UserDefaults.standard.string(forKey: UserDefaultsKeys.language) ?? ""
        _selectedTab = State(initialValue: initialTab)
        _selectedLanguage = State(initialValue: Language(rawValue: pref) ?? .system)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, shortcut, security, version, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:  return L10n["settings.tab.general"]
            case .shortcut: return L10n["settings.tab.shortcut"]
            case .security: return L10n["settings.tab.security"]
            case .version:  return L10n["settings.tab.version"]
            case .about:    return L10n["settings.tab.about"]
            }
        }
        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .shortcut: return "command"
            case .security: return "shield"
            case .version:  return "exclamationmark.circle"
            case .about:    return "info.circle"
            }
        }
        var usesSymbolIcon: Bool {
            true
        }
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                settingsSidebar
                    .navigationSplitViewColumnWidth(
                        min: Local.Settings.sidebarWidth,
                        ideal: Local.Settings.sidebarWidth,
                        max: Local.Settings.sidebarWidth
                    )
            } detail: {
                detail(for: selectedTab ?? .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SettingsPalette.cream)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .background(SettingsPalette.cream)
            .ignoresSafeArea(.container, edges: .top)
            .background(
                SettingsWindowChromeConfigurator(
                    minSize: NSSize(
                        width: Local.Settings.windowMinWidth,
                        height: Local.Settings.windowMinHeight
                    )
                )
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.root)
            .onAppear { refreshAccessibilityStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshAccessibilityStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsSelectTab)) { note in
                guard let rawValue = note.object as? String,
                      let tab = SettingsTab(rawValue: rawValue) else { return }
                withAnimation(.easeInOut(duration: UIConstants.Motion.fast)) {
                    selectedTab = tab
                }
            }

            if showingClearConfirm {
                ConfirmationOverlay(
                    title: L10n["settings.clear_confirm_title"],
                    message: L10n["settings.clear_warning"],
                    cancelTitle: L10n["settings.clear_cancel"],
                    confirmTitle: L10n["settings.clear_btn"],
                    onCancel: { showingClearConfirm = false },
                    onConfirm: {
                        StoreManager.shared.clearAll()
                        showingClearConfirm = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            minWidth: Local.Settings.windowMinWidth,
            minHeight: Local.Settings.windowMinHeight
        )
    }

    var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: Local.Settings.sectionSpacing) {
            HStack(spacing: Local.Settings.sidebarBrandSpacing) {
                AppIconImageView(size: Local.Settings.sidebarBrandIconSize)
                    .shadow(color: .black.opacity(UIConstants.Shadow.Icon.opacity), radius: UIConstants.Shadow.Icon.radius, x: 0, y: UIConstants.Shadow.Icon.y)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pastry")
                        .font(.system(size: UIConstants.TypeSize.title, weight: .bold))
                        .foregroundStyle(.white.opacity(UIConstants.OnDark.textPrimary))
                    Text(L10n["settings.sidebar.subtitle"])
                        .font(.system(size: UIConstants.TypeSize.label))
                        .foregroundStyle(.white.opacity(UIConstants.OnDark.textTertiary))
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarTabButton(tab)
                }
            }

            Spacer()

            sidebarFooterNote
        }
        .padding(.horizontal, Local.Settings.sidebarHorizontalPadding)
        .padding(.top, Local.Settings.sidebarTopPadding)
        .padding(.bottom, Local.Settings.sidebarBottomPadding)
        .frame(width: Local.Settings.sidebarWidth)
        .background(SettingsPalette.sidebar.opacity(Local.Settings.sidebarOpacity))
        .ignoresSafeArea(.container, edges: .top)
    }

    var sidebarFooterNote: some View {
        Text(L10n["settings.sidebar.footer"])
            .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
            .foregroundStyle(.white.opacity(UIConstants.OnDark.textTertiary))
            .lineSpacing(2)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .fill(Color.black.opacity(UIConstants.OnDark.fillHover))
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                            .strokeBorder(Color.white.opacity(UIConstants.OnDark.fillSubtle), lineWidth: UIConstants.Stroke.hairline)
                    )
            )
    }

    func sidebarTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let selectTab = {
            withAnimation(.easeInOut(duration: UIConstants.Motion.fast)) {
                selectedTab = tab
            }
        }
        return Button(action: selectTab) {
            HStack(spacing: 8) {
                sidebarTabGlyph(tab, isSelected: isSelected)
                Text(tab.label)
                    .font(.system(size: UIConstants.TypeSize.body, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(UIConstants.OnDark.textIdle))
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: Local.Settings.navRowHeight)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    .fill(isSelected ? .white.opacity(UIConstants.OnDark.fillHover) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                            .stroke(isSelected ? .white.opacity(UIConstants.OnDark.fillSubtle) : .clear, lineWidth: UIConstants.Stroke.hairline)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityRepresentation {
            Button(tab.label, action: selectTab)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.sidebarTab(tab.rawValue))
        }
    }

    @ViewBuilder
    func sidebarTabGlyph(_ tab: SettingsTab, isSelected: Bool) -> some View {
        let foreground = isSelected ? PastryPalette.warmInk : .white.opacity(UIConstants.OnDark.textSecondary)
        let background = isSelected ? PastryPalette.warmGold : .white.opacity(UIConstants.OnDark.fillSubtle)

        Group {
            if tab.usesSymbolIcon {
                Image(systemName: tab.icon)
                    .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
            } else {
                Text(tab.icon)
                    .font(.system(size: UIConstants.TypeSize.callout, weight: .heavy))
            }
        }
        .foregroundStyle(foreground)
        .frame(width: Local.Settings.navGlyphSize, height: Local.Settings.navGlyphSize)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                .fill(background)
        )
    }


    // MARK: - 详情内容

    @ViewBuilder
    func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:  generalTab
        case .shortcut: shortcutTab
        case .security: securityTab
        case .version:  versionTab
        case .about:    aboutTab
        }
    }

    func settingsPaneHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Local.Settings.sectionSpacing) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: UIConstants.TypeSize.display, weight: .bold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(subtitle)
                    .font(.system(size: UIConstants.TypeSize.body))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineSpacing(1)
                    .frame(maxWidth: Local.Settings.paneHeaderMaxWidth, alignment: .leading)
            }

            Spacer()
        }
        .padding(.bottom, 6)
    }

    func metricCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: UIConstants.TypeSize.headline, weight: .bold))
                .foregroundStyle(SettingsPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundStyle(SettingsPalette.muted)
                .lineLimit(1)
        }
        .padding(Local.Settings.metricPadding)
        .frame(maxWidth: .infinity, minHeight: Local.Settings.metricMinHeight, alignment: .leading)
        .settingsCardChrome(fill: SettingsPalette.cardFillSoft)
    }

    func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: UIConstants.TypeSize.label, weight: .bold))
                .foregroundStyle(SettingsPalette.muted)
                .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 9)

            Rectangle()
                .fill(SettingsPalette.ink.opacity(UIConstants.Settings.hairlineOpacity))
                .frame(height: 1)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .settingsCardChrome(clip: true)
    }

    func settingsRow<Control: View>(
        title: String,
        help: String? = nil,
        danger: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(danger ? PastryPalette.danger : SettingsPalette.ink)
                if let help {
                    Text(help)
                        .font(.system(size: UIConstants.TypeSize.label))
                        .foregroundStyle(SettingsPalette.muted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
        .padding(.vertical, Local.Settings.rowVerticalPadding)
        .frame(minHeight: UIConstants.Settings.rowMinHeight)
        .background(danger ? PastryPalette.danger.opacity(UIConstants.Settings.washOpacity) : Color.clear)
    }

    var settingsDivider: some View {
        Rectangle()
            .fill(SettingsPalette.ink.opacity(UIConstants.Settings.hairlineOpacity))
            .frame(height: 1)
            .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
    }
}
