import SwiftUI
import AppKit
import OSLog

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let controlColumnWidth: CGFloat = 112
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
                        value: formattedHistoryMaxItems,
                        label: L10n["settings.general.metric_max_items"]
                    )
                    metricCard(
                        value: HistoryRetentionPolicy.maxAgeMetricLabel(HistoryRetentionPolicy.sanitizedMaxAgeDays(historyMaxAgeDays)),
                        label: L10n["settings.general.metric_retention_window"]
                    )
                    metricCard(
                        value: "v\(AppVersion.displayCurrent)",
                        label: L10n["settings.general.metric_current_version"]
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
                            help: L10n["settings.general.launch_help"]
                        ) {
                            Toggle(L10n["settings.launch_at_login"], isOn: $launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .onChange(of: launchAtLogin) { _, enabled in
                                    do {
                                        try LaunchAtLoginManager.shared.setEnabled(enabled)
                                    } catch {
                                        Logger(subsystem: "com.nekutai.pastry", category: "settings")
                                            .error("开机启动切换失败: \(error.localizedDescription)")
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
                            Toggle(L10n["settings.card_click_mode"], isOn: speedClickEnabledBinding)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityRepresentation {
                                    Toggle(L10n["settings.card_click_mode"], isOn: speedClickEnabledBinding)
                                }
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
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var formattedHistoryMaxItems: String {
        let value = HistoryRetentionPolicy.sanitizedMaxItems(historyMaxItems)
        return value.formatted(.number.grouping(.automatic))
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

    /// 开关打开 = 极速（单击粘贴）；关闭 = 当前增强（单击选中 / 再点已选粘贴）
    var speedClickEnabled: Bool {
        CardClickMode.resolved(stored: cardClickModeRaw) == .speed
    }

    var speedClickEnabledBinding: Binding<Bool> {
        Binding(
            get: { CardClickMode.resolved(stored: cardClickModeRaw) == .speed },
            set: { cardClickModeRaw = ($0 ? CardClickMode.speed : CardClickMode.enhanced).rawValue }
        )
    }

    var generalSectionHeight: CGFloat { 330 }
}
