import SwiftUI

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let headerSubtitleMaxWidth: CGFloat = 460
    }
}

extension SettingsSceneView {
    var appleIntelligenceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                appleIntelligenceHeader

                appleIntelligenceSection
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await LocalSemanticSearchEngine.shared.refreshStatus()
            disableAppleIntelligenceWhenModelUnavailable()
        }
        .onChange(of: semanticSearchStatus.modelAvailability) { _, availability in
            if availability != .available {
                disableAppleIntelligenceWhenModelUnavailable()
            }
        }
    }

    var appleIntelligenceHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(L10n["settings.tab.apple_intelligence"])
                        .font(.system(size: UIConstants.TypeSize.display, weight: .bold))
                        .foregroundStyle(SettingsPalette.ink)

                    semanticModelStatusBadge
                }

                Text(L10n["settings.apple_intelligence.subtitle"])
                    .font(.system(size: UIConstants.TypeSize.body))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineSpacing(1)
                    .frame(
                        maxWidth: Local.Settings.headerSubtitleMaxWidth,
                        alignment: .leading
                    )
            }

            Spacer()
        }
        .padding(.bottom, 6)
    }

    var semanticModelStatusBadge: some View {
        Label(semanticModelStatusText, systemImage: semanticModelStatusIcon)
            .font(.system(size: UIConstants.TypeSize.body, weight: .bold))
            .foregroundStyle(semanticModelStatusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.control,
                fill: semanticModelStatusColor.opacity(UIConstants.Settings.washOpacity)
            )
    }

    var appleIntelligenceSection: some View {
        settingsSection(title: L10n["settings.apple_intelligence.section"]) {
            settingsRow(
                title: L10n["settings.apple_intelligence.feature_title"],
                help: appleIntelligenceFeatureHelp
            ) {
                Toggle(L10n["settings.apple_intelligence.feature_title"], isOn: $appleIntelligenceEnabled)
                    .labelsHidden()
                    .toggleStyle(SettingsSwitchStyle())
                    .disabled(semanticSearchStatus.modelAvailability != .available)
                    .onChange(of: appleIntelligenceEnabled) { _, enabled in
                        guard !enabled || semanticSearchStatus.modelAvailability == .available else {
                            appleIntelligenceEnabled = false
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
                        Toggle(L10n["settings.apple_intelligence.feature_title"], isOn: $appleIntelligenceEnabled)
                            .disabled(semanticSearchStatus.modelAvailability != .available)
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.appleIntelligenceToggle)
            }

            if showsSemanticIndexStatus {
                settingsDivider
                semanticIndexStatusRow
            }

            settingsDivider
            semanticRebuildRow
        }
    }

    var showsSemanticIndexStatus: Bool {
        appleIntelligenceEnabled && semanticSearchStatus.indexPhase != .disabled
    }

    var semanticIndexStatusRow: some View {
        settingsRow(
            title: L10n["settings.semantic.index_title"],
            help: semanticIndexStatusText
        ) {
            HStack(spacing: 8) {
                if semanticSearchStatus.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                }
                Label(semanticIndexStatusText, systemImage: semanticIndexStatusIcon)
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundStyle(SettingsPalette.muted)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.semanticIndexProgress)
        }
    }

    var appleIntelligenceFeatureHelp: String {
        semanticSearchStatus.modelAvailability == .available
            ? L10n["settings.apple_intelligence.feature_help"]
            : semanticModelStatusText
    }

    func disableAppleIntelligenceWhenModelUnavailable() {
        guard semanticSearchStatus.modelAvailability != .available,
              appleIntelligenceEnabled else { return }
        appleIntelligenceEnabled = false
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
                !appleIntelligenceEnabled
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
        case .disabled, .waiting: return L10n["settings.semantic.index_waiting"]
        case .indexing: return L10n["settings.semantic.index_building"]
        case .ready: return L10n["settings.semantic.index_ready"]
        case .failed: return L10n["settings.semantic.index_failed"]
        }
    }

    var semanticIndexStatusIcon: String {
        switch semanticSearchStatus.indexPhase {
        case .disabled: "pause.circle"
        case .waiting: "clock"
        case .indexing: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
