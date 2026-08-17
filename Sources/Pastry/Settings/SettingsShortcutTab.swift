import SwiftUI
import AppKit
import Carbon

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let captureShadowOpacity: Double = 0.08
        static let captureShadowRadius: CGFloat = 8
        static let captureShadowY: CGFloat = 3
        static let keycapHighlightOpacity: Double = 0.70
        static let keycapShadowOpacity: Double = 0.12
        static let keycapShadowY: CGFloat = 2
        static let shortcutCaptureMinHeight: CGFloat = 108
    }
}

// MARK: - Shortcut Tab

extension SettingsSceneView {
    // MARK: - 快捷键 Tab

    var shortcutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsPaneHeader(
                    title: L10n["settings.tab.shortcut"],
                    subtitle: L10n["settings.shortcut.subtitle"]
                )

                shortcutHero

                settingsSection(title: L10n["shortcut.section_title"]) {
                    shortcutSettingsRows
                }

                Spacer()
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var shortcutSettingsRows: some View {
        settingsRow(
            title: L10n["shortcut.overlay_shortcut"],
            help: L10n["shortcut.applies_immediately"]
        ) {
            Button {
                shortcutPreviewKeyCode = nil
                shortcutPreviewModifiers = 0
                isRecordingShortcut = true
            } label: {
                Text(isRecordingShortcut ? L10n["hotkey.recording"] : L10n["shortcut.record_button"])
                    .frame(minWidth: 54)
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .disabled(isRecordingShortcut)
            .opacity(isRecordingShortcut ? UIConstants.Settings.secondaryFillOpacity : 1)
        }

        ShortcutCaptureView(
            isRecording: $isRecordingShortcut,
            keyCode: $hotkeyKeyCode,
            modifiers: $hotkeyModifiers,
            onPreview: { keyCode, modifiers in
                shortcutPreviewKeyCode = keyCode
                shortcutPreviewModifiers = modifiers
            },
            onChange: {
                GlobalHotkeyManager.shared.reregister()
            },
            onStartRecording: {
                GlobalHotkeyManager.shared.unregister()
            },
            onCancelRecording: {
                shortcutPreviewKeyCode = nil
                shortcutPreviewModifiers = 0
                // 录制开始时会临时注销；取消后即使配置没变也要恢复。
                GlobalHotkeyManager.shared.reregister(force: true)
            }
        )
        .frame(width: 0, height: 0)
        .opacity(0.01)
        .accessibilityHidden(true)

        settingsDivider

        settingsRow(
            title: L10n["shortcut.clear_shortcut"],
            help: L10n["shortcut.clear_hint"]
        ) {
            Button(L10n["shortcut.clear_button"]) {
                clearShortcut()
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
        }
    }

    var shortcutHero: some View {
        HStack {
            Spacer()
            HStack(spacing: 12) {
                ForEach(Array(shortcutHeroSegments.enumerated()), id: \.offset) { _, segment in
                    shortcutKeycap(segment)
                }
            }
            .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
            .frame(height: UIConstants.Settings.rowMinHeight)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                    .fill(Color.white.opacity(UIConstants.Settings.pressedOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                            .stroke(SettingsPalette.ink.opacity(UIConstants.Settings.borderOpacity), lineWidth: UIConstants.Stroke.hairline)
                    )
                    .shadow(color: .black.opacity(Local.Settings.captureShadowOpacity), radius: Local.Settings.captureShadowRadius, x: 0, y: Local.Settings.captureShadowY)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: Local.Settings.shortcutCaptureMinHeight)
        .settingsCardChrome(cornerRadius: UIConstants.Radius.panel, fill: SettingsPalette.cardFillSoft)
    }

    func shortcutKeycap(_ segment: String) -> some View {
        Text(segment)
            .font(.system(size: UIConstants.TypeSize.title, weight: .bold, design: .rounded))
            .foregroundStyle(SettingsPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, segment.count > 1 ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    // Physical keycap: top-lit face + raised edge, not flat chip chrome.
                    .fill(
                        LinearGradient(
                            colors: [
                                .white,
                                PastryPalette.cream
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                            .stroke(SettingsPalette.ink.opacity(UIConstants.Settings.borderOpacity), lineWidth: UIConstants.Stroke.hairline)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                            .stroke(.white.opacity(Local.Settings.keycapHighlightOpacity), lineWidth: UIConstants.Stroke.hairline)
                            .padding(1)
                    )
                    .shadow(color: SettingsPalette.ink.opacity(Local.Settings.keycapShadowOpacity), radius: 0, x: 0, y: Local.Settings.keycapShadowY)
            )
    }

    var shortcutHeroSegments: [String] {
        if isRecordingShortcut {
            let preview = shortcutDisplayPreviewSegments(
                keyCode: shortcutPreviewKeyCode,
                modifiers: shortcutPreviewModifiers
            )
            return preview.isEmpty ? ["…"] : preview
        }
        guard hotkeyKeyCode >= 0 else {
            return ["--"]
        }
        return shortcutDisplaySegments(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    func clearShortcut() {
        hotkeyKeyCode = -1
        hotkeyModifiers = 0
        isRecordingShortcut = false
        shortcutPreviewKeyCode = nil
        shortcutPreviewModifiers = 0
        GlobalHotkeyManager.shared.reregister()
    }
}
