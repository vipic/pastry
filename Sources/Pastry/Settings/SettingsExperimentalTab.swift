import SwiftUI

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let semanticProgressWidth: CGFloat = 180
        static let semanticStatusSpacing: CGFloat = 6
    }
}

extension SettingsSceneView {
    var experimentalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsPaneHeader(
                    title: L10n["settings.tab.experimental"],
                    subtitle: L10n["settings.experimental.subtitle"]
                )

                semanticSearchSection
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await LocalSemanticSearchEngine.shared.refreshStatus()
            disableSemanticSearchWhenModelUnavailable()
        }
        .onChange(of: semanticSearchStatus.modelAvailability) { _, availability in
            if availability != .available {
                disableSemanticSearchWhenModelUnavailable()
            }
        }
    }

    var semanticSearchSection: some View {
        settingsSection(title: L10n["settings.semantic.section"]) {
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
                title: L10n["settings.semantic.feature_title"],
                help: semanticFeatureHelp
            ) {
                Toggle(L10n["settings.semantic.feature_title"], isOn: $semanticSearchEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsSwitchStyle())
                    .disabled(semanticSearchStatus.modelAvailability != .available)
                    .onChange(of: semanticSearchEnabled) { _, enabled in
                        guard !enabled || semanticSearchStatus.modelAvailability == .available else {
                            semanticSearchEnabled = false
                            return
                        }
                        Task {
                            await LocalSemanticSearchEngine.shared.setEnabled(
                                enabled,
                                limit: HistoryRetentionPolicy.current.maxItems
                            )
                        }
                    }
                    .accessibilityRepresentation {
                        Toggle(L10n["settings.semantic.feature_title"], isOn: $semanticSearchEnabled)
                            .disabled(semanticSearchStatus.modelAvailability != .available)
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.semanticSearchToggle)
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

    var semanticFeatureHelp: String {
        semanticSearchStatus.modelAvailability == .available
            ? L10n["settings.semantic.feature_help"]
            : semanticModelStatusText
    }

    func disableSemanticSearchWhenModelUnavailable() {
        guard semanticSearchStatus.modelAvailability != .available,
              semanticSearchEnabled else { return }
        semanticSearchEnabled = false
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
}
