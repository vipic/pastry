import SwiftUI
import AppKit

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Settings {
        static let releaseNotesFillOpacity: Double = 0.34
        static let statusActionWidth: CGFloat = 118
        static let versionHeroMinHeight: CGFloat = 72
    }
}

// MARK: - Version Tab

extension SettingsSceneView {
    // MARK: - 更新 Tab

    var versionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsPaneHeader(
                    title: L10n["settings.tab.version"],
                    subtitle: L10n["settings.version.subtitle"]
                )

                versionStatusCard

                versionReleaseNotesCard

                Spacer()
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { autoCheckVersionIfNeeded() }
    }

    var versionStatusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            versionBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(versionStatusTitle)
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(versionStatusSubtitle)
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineLimit(2)
            }

            Spacer()

            versionPrimaryAction
        }
        .padding(UIConstants.Settings.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: Local.Settings.versionHeroMinHeight, alignment: .leading)
        .settingsCardChrome(cornerRadius: UIConstants.Radius.panel, fill: versionStatusTint)
    }

    var versionBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                .fill(versionBadgeFill)
            Image(systemName: versionBadgeSymbol)
                .font(.system(size: UIConstants.TypeSize.title2, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: UIConstants.Badge.statusSize, height: UIConstants.Badge.statusSize)
    }

    @ViewBuilder
    var versionPrimaryAction: some View {
        switch versionUpdateState {
        case .checking:
            Button {
            } label: {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                    .scaleEffect(0.72)
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .disabled(true)
            .opacity(UIConstants.Settings.secondaryFillOpacity)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .downloading(let progress):
            VStack(alignment: .trailing, spacing: 6) {
                progressBar(progress)
                    .frame(width: Local.Settings.statusActionWidth)
                Text("\(Int(min(max(progress, 0), 1) * 100))%")
                    .font(.system(size: UIConstants.TypeSize.label, weight: .medium))
                    .foregroundStyle(SettingsPalette.muted)
                    .monospacedDigit()
            }
        case .installing:
            ProgressView()
                .tint(PastryPalette.warmAccent)
                .controlSize(.small)
        case .updateAvailable(let result):
            Button(L10n["update.update_btn"]) {
                Task { await installVersionUpdate(result) }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
        default:
            Button(L10n["settings.version.check_again"]) {
                Task { await checkVersionFromSettings(force: true, allowDevBuild: true, minimumCheckingDuration: 0.45) }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .disabled(isVersionCheckInFlight)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    var versionReleaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(releaseNotesTitle)
                .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                .foregroundStyle(SettingsPalette.ink)

            if releaseNotesItems.isEmpty {
                Text(L10n["settings.version.no_release_notes"])
                    .font(.system(size: UIConstants.TypeSize.callout))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(releaseNotesItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            settingsDivider
                                .padding(.horizontal, -14)
                        }
                        releaseNoteRow(item, isLatest: index == 0)
                    }
                }
            }
        }
        .padding(UIConstants.Settings.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                .fill(.white.opacity(Local.Settings.releaseNotesFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                        .stroke(SettingsPalette.ink.opacity(UIConstants.Settings.hairlineOpacity), lineWidth: UIConstants.Stroke.hairline)
                )
        )
    }

    var versionStatusTitle: String {
        switch versionUpdateState {
        case .checking:
            return L10n["update.checking"]
        case .updateAvailable:
            return L10n["update.update_available"]
        case .downloading:
            return L10n["update.downloading"]
        case .installing:
            return L10n["update.installing_msg"]
        case .error:
            return L10n["update.check_failed"]
        case .upToDate:
            return L10n["settings.version.up_to_date"]
        }
    }

    func releaseNoteRow(_ note: UpdateChecker.ReleaseNote, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("v\(note.version)")
                    .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
                    .foregroundStyle(SettingsPalette.ink)
                if isLatest, case .updateAvailable = versionUpdateState {
                    Text(L10n["settings.version.available_badge"])
                        .font(.system(size: UIConstants.TypeSize.caption, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(PastryPalette.warmAccent)
                        )
                }
                Spacer()
            }

            Text(releaseNoteBody(note))
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundStyle(SettingsPalette.muted)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    var versionStatusSubtitle: String {
        switch versionUpdateState {
        case .updateAvailable(let result):
            return "\(L10n["update.current"]) v\(UpdateChecker.displayVersion(result.currentVersion)) -> \(L10n["update.latest"]) v\(UpdateChecker.displayVersion(result.latestVersion))"
        case .downloading, .installing:
            if let current = versionCurrentVersion, let latest = versionLatestVersion {
                return "\(L10n["update.current"]) v\(UpdateChecker.displayVersion(current)) -> \(L10n["update.latest"]) v\(UpdateChecker.displayVersion(latest))"
            }
            return String(format: L10n["settings.version.current_build"], "v\(AppVersion.displayCurrent)", AppVersion.displayBuild)
        case .error(let message):
            return message
        default:
            return String(format: L10n["settings.version.current_build"], "v\(AppVersion.displayCurrent)", AppVersion.displayBuild)
        }
    }

    var releaseNotesTitle: String {
        if case .updateAvailable = versionUpdateState {
            return L10n["update.whats_new"]
        }
        return L10n["settings.version.recent_changes"]
    }

    var releaseNotesItems: [UpdateChecker.ReleaseNote] {
        let history = versionReleaseHistory.filter {
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !history.isEmpty {
            return Array(history.prefix(3))
        }

        let notes = versionReleaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else { return [] }
        let version = versionLatestVersion ?? AppVersion.displayCurrent
        return [
            UpdateChecker.ReleaseNote(
                version: UpdateChecker.displayVersion(version),
                body: notes,
                publishedAt: "",
                htmlURL: ""
            )
        ]
    }

    func releaseNoteBody(_ note: UpdateChecker.ReleaseNote) -> String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? L10n["settings.version.no_release_notes"] : body
    }

    var versionBadgeSymbol: String {
        switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            return "arrow.down"
        case .error:
            return "exclamationmark"
        default:
            return "checkmark"
        }
    }

    var versionStatusTint: Color {
        switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            return PastryPalette.warmAccent.opacity(UIConstants.Settings.hairlineOpacity)
        case .error:
            return PastryPalette.danger.opacity(UIConstants.Settings.washOpacity)
        default:
            return .white.opacity(UIConstants.Settings.secondaryFillOpacity)
        }
    }

    var versionBadgeFill: Color {
        switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            return PastryPalette.warmAccent
        case .error:
            return PastryPalette.danger
        default:
            return PastryPalette.successDeep
        }
    }

    func progressBar(_ progress: Double) -> some View {
        let clamped = min(max(progress, 0), 1)
        let visible = max(clamped, 0.02)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: UIConstants.Radius.sm)
                    .fill(SettingsPalette.ink.opacity(UIConstants.Settings.hairlineOpacity))
                    .frame(height: UIConstants.Control.progressTrackHeight)
                RoundedRectangle(cornerRadius: UIConstants.Radius.sm)
                    .fill(PastryPalette.warmAccent)
                    .frame(width: geo.size.width * CGFloat(visible), height: UIConstants.Control.progressTrackHeight)
            }
        }
        .frame(height: UIConstants.Control.progressTrackHeight)
    }

    func loadVersionCache() {
        guard versionReleaseNotes == nil else { return }
        versionReleaseHistory = UpdateChecker.shared.cachedReleaseHistory()
        versionReleaseNotes = versionReleaseHistory.first?.body ?? UpdateChecker.shared.cachedReleaseNotes()
        let lastCheck = UserDefaults.standard.object(forKey: "PastryLastUpdateCheck") as? Date
        versionUpdateState = .upToDate(
            version: AppVersion.displayCurrent,
            build: AppVersion.displayBuild,
            lastCheckDate: lastCheck,
            lastReleaseNotes: versionReleaseNotes
        )
    }

    func autoCheckVersionIfNeeded() {
        loadVersionCache()
        guard !didAutoCheckVersionInCurrentWindow else { return }
        didAutoCheckVersionInCurrentWindow = true
        Task { await checkVersionFromSettings(force: false, allowDevBuild: false, minimumCheckingDuration: 0) }
    }

    @MainActor
    func checkVersionFromSettings(
        force: Bool = true,
        allowDevBuild: Bool = true,
        minimumCheckingDuration: TimeInterval = 0.45
    ) async {
        guard !isVersionCheckInFlight else { return }
        isVersionCheckInFlight = true
        let startedAt = Date()
        withAnimation(.easeOut(duration: UIConstants.Motion.fast)) {
            versionUpdateState = .checking
        }
        if let result = await UpdateChecker.shared.checkForUpdate(force: force, allowDevBuild: allowDevBuild) {
            await waitForMinimumCheckingDuration(startedAt: startedAt, minimumDuration: minimumCheckingDuration)
            versionReleaseNotes = result.releaseNotes
            versionReleaseHistory = result.releaseHistory
            versionCurrentVersion = result.currentVersion
            versionLatestVersion = result.latestVersion
            withAnimation(.easeOut(duration: UIConstants.Motion.fast)) {
                versionUpdateState = .updateAvailable(result: result)
            }
        } else {
            await waitForMinimumCheckingDuration(startedAt: startedAt, minimumDuration: minimumCheckingDuration)
            let cachedHistory = UpdateChecker.shared.cachedReleaseHistory()
            let cachedNotes = cachedHistory.first?.body ?? UpdateChecker.shared.cachedReleaseNotes()
            versionReleaseHistory = cachedHistory
            versionReleaseNotes = cachedNotes
            versionCurrentVersion = nil
            versionLatestVersion = nil
            let lastCheck = UserDefaults.standard.object(forKey: "PastryLastUpdateCheck") as? Date
            versionUpdateState = .upToDate(
                version: AppVersion.displayCurrent,
                build: AppVersion.displayBuild,
                lastCheckDate: lastCheck,
                lastReleaseNotes: cachedNotes
            )
        }
        isVersionCheckInFlight = false
    }

    func waitForMinimumCheckingDuration(startedAt: Date, minimumDuration: TimeInterval) async {
        let remaining = minimumDuration - Date().timeIntervalSince(startedAt)
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    @MainActor
    func installVersionUpdate(_ result: UpdateChecker.UpdateResult) async {
        versionReleaseNotes = result.releaseNotes
        versionReleaseHistory = result.releaseHistory
        versionCurrentVersion = result.currentVersion
        versionLatestVersion = result.latestVersion
        versionUpdateState = .downloading(progress: 0)

        do {
            let tempURL = try await UpdateChecker.shared.downloadBinary(
                from: result.downloadURL,
                expectedSize: result.downloadSize,
                onProgress: { progress in
                    Task { @MainActor in
                        versionUpdateState = .downloading(progress: progress)
                    }
                }
            )
            versionUpdateState = .installing
            try UpdateChecker.shared.applyUpdate(dmgAt: tempURL, expectedVersion: result.latestVersion)
        } catch {
            versionUpdateState = .error(error.localizedDescription)
        }
    }
}
