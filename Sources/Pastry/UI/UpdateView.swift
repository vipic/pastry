import SwiftUI

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Control {
        static let bulletSize: CGFloat = 6
        static let statusDotSize: CGFloat = 8
    }
    enum Update {
        static let bottomPadding: CGFloat = 28
        static let horizontalPadding: CGFloat = 40
        static let iconTopPadding: CGFloat = 30
        static let sectionPadding: CGFloat = 14
        static let statusIconSize: CGFloat = 18
        static let windowWidth: CGFloat = 420
    }
}

// MARK: - 更新状态

enum UpdateState {
    case upToDate(version: String, build: String, lastCheckDate: Date?, lastReleaseNotes: String?)
    case updateAvailable(result: UpdateChecker.UpdateResult)
    case checking
    case downloading(progress: Double)   // 0.0 ~ 1.0
    case installing
    case error(String)
}

// MARK: - 更新窗口视图（Up-to-date / Update Available 两态共用）

struct UpdateView: View {
    @AppStorage(UserDefaultsKeys.language) private var language = ""
    let state: UpdateState
    let releaseNotes: String?
    let currentVersion: String?
    let latestVersion: String?
    var onUpdate: (() -> Void)?
    var onCancel: (() -> Void)?

    private let updateAccent = PastryPalette.warmAccent

    var body: some View {
        VStack(spacing: 0) {
            // App 图标
            AppIconImageView(size: 72)
                .padding(.top, Local.Update.iconTopPadding)
                .padding(.bottom, Local.Update.sectionPadding)

            // 标题行（状态文字 + 指示器）
            headingRow
                .padding(.bottom, 4)

            // 版本信息
            versionRow
                .padding(.bottom, 8)

            // 上次检查时间（仅 upToDate 显示）
            if case .upToDate(_, _, let lastCheck, _) = state, let date = lastCheck {
                lastCheckedRow(date)
                    .padding(.bottom, 16)
            } else {
                Color.clear.frame(height: 0)
                    .padding(.bottom, 16)
            }

            // 更新日志
            if let notes = releaseNotes, !notes.isEmpty {
                changelogSection(notes)
                    .padding(.bottom, 24)
            }

            // 按钮区
            buttonRow
        }
        .padding(.horizontal, Local.Update.horizontalPadding)
        .padding(.bottom, Local.Update.bottomPadding)
        .frame(width: Local.Update.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .id(language)
    }

    // MARK: - 标题行

    @ViewBuilder
    private var headingRow: some View {
        HStack(spacing: 8) {
            switch state {
            case .upToDate:
                Text(L10n["update.up_to_date"])
                    .font(.system(size: UIConstants.TypeSize.title2, weight: .semibold))
                ZStack {
                    Circle()
                        .fill(PastryPalette.success)
                        .frame(width: Local.Update.statusIconSize, height: Local.Update.statusIconSize)
                    Image(systemName: "checkmark")
                        .font(.system(size: UIConstants.TypeSize.caption, weight: .bold))
                        .foregroundColor(.white)
                }

            case .updateAvailable, .downloading, .installing:
                Text(L10n["update.update_available"])
                    .font(.system(size: UIConstants.TypeSize.title2, weight: .semibold))
                Circle()
                    .fill(updateAccent)
                    .frame(width: Local.Control.statusDotSize, height: Local.Control.statusDotSize)

            case .checking:
                Text(L10n["update.checking"])
                    .font(.system(size: UIConstants.TypeSize.title2, weight: .semibold))
                ProgressView()
                    .tint(updateAccent)
                    .scaleEffect(0.7)
                    .frame(width: Local.Update.statusIconSize, height: Local.Update.statusIconSize)

            case .error:
                Text(L10n["update.check_failed"])
                    .font(.system(size: UIConstants.TypeSize.title2, weight: .semibold))
            }
        }
    }

    // MARK: - 上次检查时间

    private func lastCheckedRow(_ date: Date) -> some View {
        let formatter = RelativeDateTimeFormatter()
        let lang = L10n.currentLanguageIdentifier
        formatter.locale = lang.hasPrefix("zh") ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")
        let delta = Date().timeIntervalSince(date)
        let relative: String
        if abs(delta) < 3 {
            relative = L10n["update.just_now"]
        } else {
            relative = formatter.localizedString(for: date, relativeTo: Date())
        }

        return Text(String(format: L10n["update.last_checked"], relative))
            .font(.system(size: UIConstants.TypeSize.callout))
            .foregroundColor(.secondary)
    }

    // MARK: - 版本行

    @ViewBuilder
    private var versionRow: some View {
        switch state {
        case .upToDate(let version, let build, _, _):
            Text("\(L10n["update.current"]) v\(UpdateChecker.displayVersion(version)) · Build \(build)")
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundColor(.secondary)

        case .updateAvailable(let result):
            HStack(spacing: 6) {
                Text("\(L10n["update.current"]) v\(UpdateChecker.displayVersion(result.currentVersion))")
                    .foregroundColor(.secondary)
                Text("→")
                    .foregroundColor(.secondary.opacity(UIConstants.OnLight.textTertiary))
                Text("\(L10n["update.latest"]) v\(UpdateChecker.displayVersion(result.latestVersion))")
                    .fontWeight(.medium)
            }
            .font(.system(size: UIConstants.TypeSize.body))

        case .checking:
            EmptyView()

        case .downloading:
            // 保留版本箭头（由 currentVersion/latestVersion 提供）
            if let cur = currentVersion, let lat = latestVersion {
                HStack(spacing: 6) {
                    Text("\(L10n["update.current"]) v\(UpdateChecker.displayVersion(cur))").foregroundColor(.secondary)
                    Text("→").foregroundColor(.secondary.opacity(UIConstants.OnLight.textTertiary))
                    Text("\(L10n["update.latest"]) v\(UpdateChecker.displayVersion(lat))").fontWeight(.medium)
                }
                .font(.system(size: UIConstants.TypeSize.body))
            } else {
                EmptyView()
            }

        case .installing:
            Text(L10n["update.installing_msg"])
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundColor(.secondary)

        case .error(let message):
            Text(message)
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 更新日志

    private func changelogSection(_ notes: String) -> some View {
        let items = parseChangelog(notes)

        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n["update.whats_new"])
                        .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(updateAccent)
                                    .frame(width: Local.Control.bulletSize, height: Local.Control.bulletSize)
                                    .padding(.top, 5)
                                Text(item)
                                    .font(.system(size: UIConstants.TypeSize.body))
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Local.Update.sectionPadding)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.card)
                        .fill(Color.primary.opacity(UIConstants.OnLight.fillSoft))
                )
            }
        }
    }

    // MARK: - 按钮行

    @ViewBuilder
    private var buttonRow: some View {
        switch state {
        case .upToDate:
            HStack {
                Spacer()
                Button(L10n["update.ok"]) { onCancel?() }
                    .buttonStyle(SecondaryButtonStyle())
            }

        case .updateAvailable:
            HStack(spacing: 10) {
                Spacer()
                Button(L10n["update.cancel"]) { onCancel?() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L10n["update.update_btn"]) { onUpdate?() }
                    .buttonStyle(PastryPrimaryButtonStyle())
            }

        case .downloading:
            VStack(spacing: 10) {
                progressBar
                Text(L10n["update.downloading"])
                    .font(.system(size: UIConstants.TypeSize.callout))
                    .foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Button(L10n["update.cancel"]) { onCancel?() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

        case .installing:
            EmptyView()

        case .checking:
            EmptyView()

        case .error:
            HStack {
                Spacer()
                Button(L10n["update.ok"]) { onCancel?() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: - 解析更新日志

    /// 将 GitHub Release body 解析为要点列表
    private func parseChangelog(_ body: String) -> [String] {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("*") }
            .map { line -> String in
                var s = line
                // 去掉前缀 "- " / "* "
                if let idx = s.firstIndex(where: { $0 != "-" && $0 != "*" && $0 != " " }) {
                    s = String(s[idx...])
                }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        // 至少 1 条就显示
        return lines.count >= 1 ? lines : []
    }

    // MARK: - 进度条

    private var progressBar: some View {
        VStack(spacing: 6) {
            if case .downloading(let progress) = state {
                let clampedProgress = min(max(progress, 0), 1)
                let visibleProgress = max(clampedProgress, 0.02)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: UIConstants.Radius.sm)
                            .fill(Color.primary.opacity(UIConstants.OnLight.fillSoft))
                            .frame(height: UIConstants.Control.progressTrackHeight)
                        RoundedRectangle(cornerRadius: UIConstants.Radius.sm)
                            .fill(updateAccent)
                            .frame(width: geo.size.width * CGFloat(visibleProgress), height: UIConstants.Control.progressTrackHeight)
                    }
                }
                .frame(height: UIConstants.Control.progressTrackHeight)

                Text("\(Int(clampedProgress * 100))%")
                    .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 按钮样式

struct PastryPrimaryButtonStyle: ButtonStyle {
    var fontSize: CGFloat = UIConstants.TypeSize.body
    var fontWeight: Font.Weight = .medium
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 8
    var cornerRadius: CGFloat = UIConstants.Radius.button
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: fontWeight))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(PastryPalette.warmAccent)
            .foregroundColor(PastryPalette.warmInk)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.instant), value: configuration.isPressed)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: UIConstants.TypeSize.body, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(UIConstants.OnLight.fillSoft))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.button))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button)
                    .stroke(Color.primary.opacity(UIConstants.OnLight.stroke), lineWidth: UIConstants.Stroke.hairline)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: UIConstants.Motion.instant), value: configuration.isPressed)
    }
}
