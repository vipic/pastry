import SwiftUI
import AppKit
import OSLog

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let choiceSpacing: CGFloat = 6
        static let controlColumnWidth: CGFloat = 112
        static let interactionRowSpacing: CGFloat = 10
        static let interactionRowVerticalPadding: CGFloat = 12
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

                    }
                    .frame(maxWidth: .infinity, alignment: .top)

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
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                settingsSection(title: L10n["settings.general.section_interaction"]) {
                    interactionSettingsRow(
                        title: L10n["settings.tray_placement"],
                        help: L10n["settings.tray_placement.help"]
                    ) {
                        TrayPlacementPicker(selection: trayPlacementBinding)
                            .accessibilityLabel(L10n["settings.tray_placement"])
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.trayPlacementPicker)
                    }

                    settingsDivider

                    interactionSettingsRow(
                        title: L10n["settings.card_click_mode"],
                        help: L10n["settings.card_click_mode.help"]
                    ) {
                        CardClickModePicker(selection: cardClickModeBinding)
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

            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    var trayPlacementBinding: Binding<TrayPlacement> {
        Binding(
            get: { TrayPlacement.resolved(stored: trayRememberedPlacementRaw) },
            set: { trayRememberedPlacementRaw = $0.rawValue }
        )
    }

    private func interactionSettingsRow<Control: View>(
        title: String,
        help: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: Local.Settings.interactionRowSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(help)
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
        .padding(.vertical, Local.Settings.interactionRowVerticalPadding)
    }
}

private struct TrayPlacementPicker: View {
    @Binding var selection: TrayPlacement

    var body: some View {
        HStack(spacing: Local.Settings.choiceSpacing) {
            ForEach(TrayPlacement.allCases) { placement in
                SettingsChoiceButton(
                    title: label(for: placement),
                    isSelected: selection == placement
                ) {
                    selection = placement
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func label(for placement: TrayPlacement) -> String {
        switch placement {
        case .bottom: L10n["settings.tray_placement.bottom"]
        case .left: L10n["settings.tray_placement.left"]
        case .right: L10n["settings.tray_placement.right"]
        }
    }
}

private struct CardClickModePicker: View {
    @Binding var selection: CardClickMode

    var body: some View {
        HStack(spacing: Local.Settings.choiceSpacing) {
            modeButton(.speed, title: L10n["settings.card_click_mode.speed"])
            modeButton(.enhanced, title: L10n["settings.card_click_mode.select_first"])
        }
        .accessibilityElement(children: .contain)
    }

    private func modeButton(_ mode: CardClickMode, title: String) -> some View {
        SettingsChoiceButton(title: title, isSelected: selection == mode) {
            selection = mode
        }
    }
}

private struct SettingsChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundStyle(isSelected ? .white : PastryPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: UIConstants.Control.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                        .fill(isSelected ? PastryPalette.primaryActionFill : Color.white.opacity(UIConstants.Settings.secondaryFillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? PastryPalette.primaryActionFill
                                        : PastryPalette.ink.opacity(UIConstants.Settings.borderOpacity),
                                    lineWidth: UIConstants.Stroke.hairline
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
