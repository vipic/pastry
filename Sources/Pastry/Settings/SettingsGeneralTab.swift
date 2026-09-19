import SwiftUI
import AppKit
import OSLog

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let clickModeControlWidth: CGFloat = 172
        static let clickModeSpacing: CGFloat = 6
        static let controlColumnWidth: CGFloat = 112
        static let semanticProgressWidth: CGFloat = 180
        static let semanticStatusSpacing: CGFloat = 6
    }
}

// MARK: - General Tab

extension SettingsSceneView {
    // MARK: - 通用 Tab

    var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsPaneHeader(
                    title: L10n["settings.tab.general"],
                    subtitle: L10n["settings.general.subtitle"]
                )

                HStack(spacing: 10) {
                    metricCard(
                        value: store.stats.totalItems.formatted(.number.grouping(.automatic)),
                        label: L10n["settings.general.metric_current_items"]
                    )
                    metricCard(
                        value: store.items.filter(\.isPinned).count.formatted(.number.grouping(.automatic)),
                        label: L10n["settings.general.metric_favorites"]
                    )
                    metricCard(
                        value: Set(store.items.compactMap(\.appName)).count.formatted(.number.grouping(.automatic)),
                        label: L10n["settings.general.metric_sources"]
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    settingsSection(title: L10n["settings.general.section_application"]) {
                        settingsRow(
                            title: L10n["lang.label"],
                            help: L10n["settings.general.language_help"]
                        ) {
                            Picker("", selection: languageBinding) {
                                ForEach(Language.allCases) { Text($0.label).tag($0) }
                            }
                            .settingsMenuPickerChrome()
                            .frame(width: Local.Settings.controlColumnWidth)
                            .accessibilityLabel(L10n["lang.label"])
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.languagePicker)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.launch_at_login"],
                            help: launchAtLoginErrorMessage ?? L10n["settings.general.launch_help"]
                        ) {
                            Toggle(L10n["settings.launch_at_login"], isOn: $launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .onChange(of: launchAtLogin) { _, enabled in
                                    guard !isRevertingLaunchAtLogin else { return }
                                    do {
                                        try LaunchAtLoginManager.shared.setEnabled(enabled)
                                        launchAtLoginErrorMessage = nil
                                    } catch {
                                        Logger(subsystem: "com.nekutai.pastry", category: "settings")
                                            .error("开机启动切换失败: \(error.localizedDescription)")
                                        launchAtLoginErrorMessage = L10n["settings.general.launch_failed"]
                                        isRevertingLaunchAtLogin = true
                                        launchAtLogin = LaunchAtLoginManager.shared.isEnabled
                                        DispatchQueue.main.async {
                                            isRevertingLaunchAtLogin = false
                                        }
                                    }
                                }
                                .accessibilityRepresentation {
                                    Toggle(L10n["settings.launch_at_login"], isOn: $launchAtLogin)
                                }
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.launchAtLoginToggle)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.sound_enabled"],
                            help: L10n["settings.general.sound_help"]
                        ) {
                            Toggle(L10n["settings.sound_enabled"], isOn: $soundEnabled)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityRepresentation {
                                    Toggle(L10n["settings.sound_enabled"], isOn: $soundEnabled)
                                }
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.soundToggle)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.card_click_mode"],
                            help: L10n["settings.card_click_mode.help"]
                        ) {
                            CardClickModePicker(selection: cardClickModeBinding)
                                .frame(width: Local.Settings.clickModeControlWidth)
                                .accessibilityLabel(L10n["settings.card_click_mode"])
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.cardClickModeToggle)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.delete_requires_confirmation"],
                            help: L10n["settings.delete_requires_confirmation.help"]
                        ) {
                            Toggle(L10n["settings.delete_requires_confirmation"], isOn: $deleteRequiresConfirmation)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityRepresentation {
                                    Toggle(L10n["settings.delete_requires_confirmation"], isOn: $deleteRequiresConfirmation)
                                }
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.deleteRequiresConfirmationToggle)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: generalSectionHeight, alignment: .top)

                    settingsSection(title: L10n["settings.history.section"]) {
                        settingsRow(
                            title: L10n["settings.general.maximum_history"],
                            help: L10n["settings.general.max_items_help"]
                        ) {
                            Picker("", selection: maxItemsBinding) {
                                ForEach(HistoryRetentionPolicy.maxItemsOptions, id: \.self) { value in
                                    Text(HistoryRetentionPolicy.maxItemsLabel(value)).tag(value)
                                }
                            }
                            .settingsMenuPickerChrome()
                            .frame(width: Local.Settings.controlColumnWidth)
                            .accessibilityLabel(L10n["settings.general.maximum_history"])
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.maxItemsPicker)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.general.keep_records_for"],
                            help: L10n["settings.general.keep_records_help"]
                        ) {
                            Picker("", selection: maxAgeBinding) {
                                ForEach(HistoryRetentionPolicy.maxAgeDayOptions, id: \.self) { value in
                                    Text(HistoryRetentionPolicy.maxAgeLabel(value)).tag(value)
                                }
                            }
                            .settingsMenuPickerChrome()
                            .frame(width: Local.Settings.controlColumnWidth)
                            .accessibilityLabel(L10n["settings.general.keep_records_for"])
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.maxAgePicker)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.clear_all"],
                            help: L10n["settings.general.clear_all_help"]
                        ) {
                            Button(L10n["settings.clear_btn"]) { showingClearConfirm = true }
                                .buttonStyle(SettingsPillButtonStyle(kind: .danger))
                                .accessibilityRepresentation {
                                    Button(L10n["settings.clear_all"]) { showingClearConfirm = true }
                                        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.clearAllButton)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: generalSectionHeight, alignment: .top)
                }

                semanticSearchSection
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await LocalSemanticSearchEngine.shared.refreshStatus()
        }
    }

    var semanticSearchSection: some View {
        settingsSection(title: L10n["settings.semantic.section"]) {
            settingsRow(
                title: L10n["settings.semantic.feature_title"],
                help: L10n["settings.semantic.feature_help"]
            ) {
                Toggle(L10n["settings.semantic.feature_title"], isOn: $semanticSearchEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsSwitchStyle())
                    .onChange(of: semanticSearchEnabled) { _, enabled in
                        Task {
                            await LocalSemanticSearchEngine.shared.setEnabled(
                                enabled,
                                limit: HistoryRetentionPolicy.current.maxItems
                            )
                        }
                    }
                    .accessibilityRepresentation {
                        Toggle(L10n["settings.semantic.feature_title"], isOn: $semanticSearchEnabled)
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.semanticSearchToggle)
            }

            settingsDivider

            settingsRow(
                title: L10n["settings.semantic.model_title"],
                help: L10n["settings.semantic.model_help"]
            ) {
                Label(semanticModelStatusText, systemImage: semanticModelStatusIcon)
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundStyle(semanticModelStatusColor)
            }

            settingsDivider

            settingsRow(
                title: L10n["settings.semantic.index_title"],
                help: semanticIndexStatusText
            ) {
                VStack(alignment: .trailing, spacing: Local.Settings.semanticStatusSpacing) {
                    ProgressView(value: semanticSearchStatus.progressFraction)
                        .frame(width: Local.Settings.semanticProgressWidth)
                    Text(L10n[
                        "settings.semantic.index_count",
                        semanticSearchStatus.indexedCount,
                        semanticSearchStatus.totalCount
                    ])
                    .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                    .foregroundStyle(SettingsPalette.muted)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.semanticIndexProgress)
            }

            settingsDivider

            semanticRebuildRow
        }
    }

    var semanticRebuildRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n[semanticIndexActionTitleKey])
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(L10n[semanticIndexActionHelpKey])
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(SettingsPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n[semanticIndexActionButtonKey]) {
                Task {
                    if shouldResumeSemanticIndex {
                        await LocalSemanticSearchEngine.shared.backfill(
                            limit: HistoryRetentionPolicy.current.maxItems
                        )
                    } else {
                        await LocalSemanticSearchEngine.shared.rebuild(
                            limit: HistoryRetentionPolicy.current.maxItems
                        )
                    }
                }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
            .disabled(
                !semanticSearchEnabled
                    || semanticSearchStatus.modelAvailability != .available
                    || semanticSearchStatus.isIndexing
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.rebuildSemanticIndexButton)
        }
        .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: UIConstants.Settings.rowMinHeight)
    }

    var shouldResumeSemanticIndex: Bool {
        semanticSearchStatus.indexPhase == .failed
    }

    var semanticIndexActionTitleKey: String {
        shouldResumeSemanticIndex
            ? "settings.semantic.resume_title"
            : "settings.semantic.rebuild_title"
    }

    var semanticIndexActionHelpKey: String {
        shouldResumeSemanticIndex
            ? "settings.semantic.resume_help"
            : "settings.semantic.rebuild_help"
    }

    var semanticIndexActionButtonKey: String {
        shouldResumeSemanticIndex
            ? "settings.semantic.resume_button"
            : "settings.semantic.rebuild_button"
    }

    var semanticModelStatusText: String {
        switch semanticSearchStatus.modelAvailability {
        case .available: return L10n["settings.semantic.model_available"]
        case .deviceNotEligible: return L10n["settings.semantic.model_unsupported"]
        case .appleIntelligenceNotEnabled: return L10n["settings.semantic.model_disabled"]
        case .modelNotReady: return L10n["settings.semantic.model_not_ready"]
        }
    }

    var semanticModelStatusIcon: String {
        semanticSearchStatus.modelAvailability == .available
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    var semanticModelStatusColor: Color {
        semanticSearchStatus.modelAvailability == .available
            ? PastryPalette.successDeep
            : PastryPalette.warmAccent
    }

    var semanticIndexStatusText: String {
        switch semanticSearchStatus.indexPhase {
        case .disabled: return L10n["settings.semantic.index_disabled"]
        case .waiting: return L10n["settings.semantic.index_waiting"]
        case .indexing: return L10n["settings.semantic.index_building"]
        case .ready: return L10n["settings.semantic.index_ready"]
        case .failed: return L10n["settings.semantic.index_failed"]
        }
    }

    var languageBinding: Binding<Language> {
        Binding<Language>(
            get: { selectedLanguage },
            set: { lang in
                selectedLanguage = lang
                switch lang {
                case .system: UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.language)
                default:      UserDefaults.standard.set(lang.rawValue, forKey: UserDefaultsKeys.language)
                }
                NotificationCenter.default.post(name: .pastryLanguageDidChange, object: lang.rawValue)
            }
        )
    }

    var maxItemsBinding: Binding<Int> {
        Binding(
            get: { HistoryRetentionPolicy.sanitizedMaxItems(historyMaxItems) },
            set: { value in
                historyMaxItems = value
                StoreManager.shared.applyHistoryRetentionSettings()
            }
        )
    }

    var maxAgeBinding: Binding<Int> {
        Binding(
            get: { HistoryRetentionPolicy.sanitizedMaxAgeDays(historyMaxAgeDays) },
            set: { value in
                historyMaxAgeDays = value
                StoreManager.shared.applyHistoryRetentionSettings()
            }
        )
    }

    var cardClickModeBinding: Binding<CardClickMode> {
        Binding(
            get: { CardClickMode.resolved(stored: cardClickModeRaw) },
            set: { cardClickModeRaw = $0.rawValue }
        )
    }

    var generalSectionHeight: CGFloat { 330 }
}

private struct CardClickModePicker: View {
    @Binding var selection: CardClickMode

    var body: some View {
        HStack(spacing: Local.Settings.clickModeSpacing) {
            modeButton(.speed, title: L10n["settings.card_click_mode.speed"])
            modeButton(.enhanced, title: L10n["settings.card_click_mode.select_first"])
        }
        .accessibilityElement(children: .contain)
    }

    private func modeButton(_ mode: CardClickMode, title: String) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            Text(title)
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundStyle(isSelected ? PastryPalette.warmInk : PastryPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: UIConstants.Control.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                        .fill(isSelected ? PastryPalette.warmAccent : Color.white.opacity(UIConstants.Settings.secondaryFillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                                .stroke(PastryPalette.ink.opacity(UIConstants.Settings.borderOpacity), lineWidth: UIConstants.Stroke.hairline)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
