import SwiftUI
import AppKit

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let aboutHeroMinHeight: CGFloat = 96
    }
}

// MARK: - About Tab

extension SettingsSceneView {
    // MARK: - 关于 Tab

    var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsPaneHeader(
                    title: L10n["settings.tab.about"],
                    subtitle: L10n["settings.about.subtitle"]
                )

                aboutIdentitySection

                HStack(alignment: .top, spacing: 12) {
                    settingsSection(title: L10n["settings.about.section_product"]) {
                        settingsRow(
                            title: L10n["settings.about.created_by"],
                            help: "Vipic"
                        ) {
                            EmptyView()
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.about.copyright"],
                            help: L10n["about.copyright"]
                        ) {
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    settingsSection(title: L10n["settings.about.section_resources"]) {
                        settingsRow(
                            title: L10n["settings.about.source_code"],
                            help: L10n["settings.about.source_code_help"]
                        ) {
                            Button(L10n["settings.about.open"]) {
                                openExternalURL("https://github.com/vipic/pastry")
                            }
                            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                            .accessibilityRepresentation {
                                Button("\(L10n["settings.about.open"]) \(L10n["settings.about.source_code"])") {
                                    openExternalURL("https://github.com/vipic/pastry")
                                }
                            }
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.about.license"],
                            help: L10n["settings.about.license_help"]
                        ) {
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var aboutIdentitySection: some View {
        HStack(alignment: .center, spacing: 16) {
            AppIconImageView(size: 64)
                .shadow(color: .black.opacity(UIConstants.Shadow.Icon.softOpacity), radius: UIConstants.Shadow.Icon.softRadius, x: 0, y: UIConstants.Shadow.Icon.softY)

            VStack(alignment: .leading, spacing: 5) {
                Text(appDisplayName)
                    .font(.system(size: UIConstants.TypeSize.headline, weight: .bold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(L10n["about.description"])
                    .font(.system(size: UIConstants.TypeSize.callout))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(UIConstants.Settings.cardPadding)
        .frame(maxWidth: .infinity, minHeight: Local.Settings.aboutHeroMinHeight, alignment: .leading)
        .settingsCardChrome(cornerRadius: UIConstants.Radius.panel)
    }

    var appDisplayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Pastry"
    }

    func openExternalURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
