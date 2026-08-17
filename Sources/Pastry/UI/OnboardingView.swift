import AppKit
import SwiftUI

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum Onboarding {
        static let bodySlotHeight: CGFloat = 144
        static let cardPadding: CGFloat = 18
        static let chromeOuterPadding: CGFloat = 24
        static let contentHorizontalPadding: CGFloat = 36
        static let contentSpacing: CGFloat = 20
        static let copyPromptShakeDuration: Double = 0.62
        static let copyPromptShakeOscillations: CGFloat = 2
        static let featureRowMaxWidth: CGFloat = 540
        static let headingMaxWidth: CGFloat = 500
        static let headingSlotHeight: CGFloat = 136
        static let heroSymbolFrameHeight: CGFloat = 44
        static let heroSymbolSize: CGFloat = 36
        static let iconSize: CGFloat = 34
        static let insetSpacing: CGFloat = 14
        static let microSpacing: CGFloat = 3
        static let permissionCardMinHeight: CGFloat = 78
        static let permissionCardWidth: CGFloat = 480
        static let permissionIconWidth: CGFloat = 32
        static let progressActiveWidth: CGFloat = 22
        static let progressDotSize: CGFloat = 7
        static let progressInactiveOpacity: Double = 0.13
        static let sampleCardWidth: CGFloat = 430
        static let sampleCodeBlockDisabledOpacity: Double = 0.46
        static let sectionSpacing: CGFloat = 12
        static let shakeDistance: CGFloat = 4
        static let shortcutFeedbackHeight: CGFloat = 24
        static let shortcutHeight: CGFloat = 58
        static let shortcutInset: CGFloat = 22
        static let stackSpacing: CGFloat = 10
        static let tightSpacing: CGFloat = 8
    }
}

struct OnboardingView: View {
    @ObservedObject private var store = StoreManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep = .welcome
    @State private var activationSource: OnboardingActivationSource?
    @State private var copyDetection: OnboardingCopyDetection
    @State private var accessibilityTrusted = false
    @State private var sampleCopyButtonHovered = false
    @State private var sampleTextCopied = false
    @State private var copyPromptAttempts: CGFloat = 0

    let onStepChange: (OnboardingStep) -> Void
    let onFinish: (_ openOverlay: Bool) -> Void

    init(
        onStepChange: @escaping (OnboardingStep) -> Void = { _ in },
        onFinish: @escaping (_ openOverlay: Bool) -> Void
    ) {
        self.onStepChange = onStepChange
        self.onFinish = onFinish
        _copyDetection = State(
            initialValue: OnboardingCopyDetection(
                baselineItemIDs: Set(StoreManager.shared.items.map(\.id))
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                switch step {
                case .welcome:
                    welcomeStep
                case .shortcut:
                    shortcutStep
                case .copy:
                    copyStep
                case .permission:
                    permissionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.medium), value: step)

            footer
                .opacity(hidesFooterNavigation ? 0 : 1)
                .allowsHitTesting(!hidesFooterNavigation)
                .accessibilityHidden(hidesFooterNavigation)
        }
        .frame(width: UIConstants.Onboarding.windowWidth)
        .ignoresSafeArea(.container, edges: .top)
        .background(PastryPalette.cream)
        .foregroundStyle(PastryPalette.ink)
        .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.root)
        .onReceive(NotificationCenter.default.publisher(for: .onboardingActivationDetected)) { notification in
            guard step == .shortcut,
                  let source = notification.object as? OnboardingActivationSource
            else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.paste)) {
                activationSource = source
            }
        }
        .onReceive(store.$items) { items in
            guard step == .copy else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.paste)) {
                _ = copyDetection.observe(
                    items: items.map { OnboardingCopyItem(id: $0.id, content: $0.content) },
                    sampleText: L10n["onboarding.copy.sample_text"]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onChange(of: step) { _, newStep in
            onStepChange(newStep)
            if newStep == .permission {
                refreshAccessibilityStatus()
            }
        }
        .onAppear {
            onStepChange(step)
            refreshAccessibilityStatus()
        }
    }

    private var header: some View {
        HStack(spacing: Local.Onboarding.sectionSpacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(
                    width: Local.Onboarding.iconSize,
                    height: Local.Onboarding.iconSize
                )

            Text("Pastry")
                .font(.system(size: UIConstants.TypeSize.title2, weight: .bold))

            Spacer()

            HStack(spacing: Local.Onboarding.progressDotSize) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule(style: .continuous)
                        .fill(
                            item == step
                                ? PastryPalette.warmAccent
                                : PastryPalette.ink.opacity(Local.Onboarding.progressInactiveOpacity)
                        )
                        .frame(
                            width: item == step
                                ? Local.Onboarding.progressActiveWidth
                                : Local.Onboarding.progressDotSize,
                            height: Local.Onboarding.progressDotSize
                        )
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.fast), value: step)

            Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                .font(.system(size: UIConstants.TypeSize.label, weight: .medium, design: .monospaced))
                .foregroundStyle(PastryPalette.muted)
                .frame(width: Local.Onboarding.iconSize, alignment: .trailing)
        }
        .padding(.horizontal, Local.Onboarding.chromeOuterPadding)
        .padding(.vertical, Local.Onboarding.chromeOuterPadding)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }

    private var footer: some View {
        HStack(spacing: Local.Onboarding.stackSpacing) {
            Button(L10n["onboarding.later"]) {
                OnboardingPreferences.markCompleted()
                onFinish(false)
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
            .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.laterButton)

            Spacer()

            if let previous = step.previous {
                Button(L10n["onboarding.back"]) {
                    withAnimation(reduceMotion ? nil : .default) { step = previous }
                }
                .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.backButton)
            }

            Button(primaryButtonTitle) {
                if step == .permission {
                    OnboardingPreferences.markCompleted()
                    onFinish(true)
                } else if step.shouldPromptForCopy(copyComplete: copyDetection.isComplete) {
                    promptForSampleCopy()
                } else {
                    advance()
                }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.primaryButton)
        }
        .padding(.horizontal, Local.Onboarding.chromeOuterPadding)
        .padding(.vertical, Local.Onboarding.chromeOuterPadding)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }

    private var hidesFooterNavigation: Bool {
        step == .copy && !copyDetection.isComplete
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return L10n["onboarding.continue"]
        case .shortcut:
            return L10n["onboarding.continue"]
        case .copy:
            return L10n["onboarding.continue"]
        case .permission:
            return L10n["onboarding.finish_open"]
        }
    }

    private var welcomeStep: some View {
        stepLayout(
            icon: "doc.on.clipboard.fill",
            title: L10n["onboarding.welcome.title"],
            subtitle: L10n["onboarding.welcome.subtitle"]
        ) {
            HStack(spacing: Local.Onboarding.sectionSpacing) {
                welcomeFeature(
                    icon: "lock.shield.fill",
                    title: L10n["onboarding.welcome.local_title"],
                    subtitle: L10n["onboarding.welcome.local_subtitle"]
                )
                welcomeFeature(
                    icon: "eye.slash.fill",
                    title: L10n["onboarding.welcome.excluded_title"],
                    subtitle: L10n["onboarding.welcome.excluded_subtitle"]
                )
                welcomeFeature(
                    icon: "menubar.rectangle",
                    title: L10n["onboarding.welcome.menubar_title"],
                    subtitle: L10n["onboarding.welcome.menubar_subtitle"]
                )
            }
            .frame(maxWidth: Local.Onboarding.featureRowMaxWidth)
        }
    }

    private var shortcutStep: some View {
        let feedback = OnboardingActivationFeedback(source: activationSource)
        return stepLayout(
            icon: activationSource == nil ? "command" : "checkmark.circle.fill",
            title: L10n[feedback.titleKey],
            subtitle: L10n[feedback.subtitleKey]
        ) {
            VStack(spacing: Local.Onboarding.shortcutInset) {
                Text(GlobalHotkeyManager.shared.currentShortcutDisplay)
                    .font(.system(size: UIConstants.TypeSize.display, weight: .bold, design: .rounded))
                    .foregroundStyle(feedback.highlightsShortcut ? PastryPalette.successDeep : PastryPalette.ink)
                    .padding(.horizontal, Local.Onboarding.shortcutInset)
                    .frame(height: Local.Onboarding.shortcutHeight)
                    .settingsCardChrome(cornerRadius: UIConstants.Radius.panel)

                Group {
                    if activationSource == nil {
                        Label(
                            L10n["onboarding.shortcut.menubar_hint"],
                            systemImage: "menubar.rectangle"
                        )
                            .font(.system(size: UIConstants.TypeSize.callout))
                            .foregroundStyle(PastryPalette.muted)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: Local.Onboarding.shortcutFeedbackHeight)
                .contentTransition(.opacity)
            }
        }
    }

    private var copyStep: some View {
        let sampleWasUsed = sampleTextCopied || copyDetection.outcome == .sampleText
        let usedOtherContent = copyDetection.outcome == .otherContent
        let actionFeedback = OnboardingCopyActionFeedback(isComplete: sampleWasUsed)
        return ZStack(alignment: .bottomTrailing) {
            stepLayout(
                icon: copyDetection.isComplete ? "checkmark.circle.fill" : "doc.on.doc",
                title: copyDetection.isComplete
                    ? L10n["onboarding.copy.detected_title"]
                    : L10n["onboarding.copy.title"],
                subtitle: copyDetection.isComplete
                    ? L10n["onboarding.copy.detected_subtitle"]
                    : L10n["onboarding.copy.subtitle"]
            ) {
                VStack(spacing: Local.Onboarding.contentSpacing) {
                    HStack(spacing: Local.Onboarding.insetSpacing) {
                        Text(L10n["onboarding.copy.sample_text"])
                            .font(.system(size: UIConstants.TypeSize.body, weight: .medium, design: .monospaced))
                            .foregroundStyle(usedOtherContent ? PastryPalette.muted : PastryPalette.ink)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer()

                        Button(action: copySampleText) {
                            animatedSymbol(
                                actionFeedback.iconName,
                                size: UIConstants.TypeSize.title,
                                color: sampleWasUsed
                                    ? PastryPalette.successDeep
                                    : (usedOtherContent ? PastryPalette.muted : PastryPalette.warmAccent)
                            )
                                .frame(
                                    width: Local.Onboarding.iconSize,
                                    height: Local.Onboarding.iconSize
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .settingsCardChrome(
                            cornerRadius: UIConstants.Radius.control,
                            fill: sampleCopyButtonHovered && !usedOtherContent
                                ? PastryPalette.cardFill
                                : PastryPalette.cardFillSoft
                        )
                        .disabled(usedOtherContent)
                        .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.instant), value: sampleCopyButtonHovered)
                        .onHover { sampleCopyButtonHovered = $0 }
                        .help(L10n[actionFeedback.labelKey])
                        .accessibilityLabel(L10n[actionFeedback.labelKey])
                        .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.copySampleButton)
                    }
                    .padding(Local.Onboarding.contentSpacing)
                    .frame(width: Local.Onboarding.sampleCardWidth)
                    .settingsCardChrome(cornerRadius: UIConstants.Radius.panel, fill: PastryPalette.cardFillSoft)
                    .opacity(usedOtherContent ? Local.Onboarding.sampleCodeBlockDisabledOpacity : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.fast), value: copyDetection.outcome)
                    .modifier(
                        OnboardingShakeEffect(
                            progress: copyPromptAttempts,
                            distance: Local.Onboarding.shakeDistance,
                            oscillations: Local.Onboarding.copyPromptShakeOscillations
                        )
                    )

                    Text(L10n["onboarding.copy.anywhere_hint"])
                        .font(.system(size: UIConstants.TypeSize.callout))
                        .foregroundStyle(PastryPalette.muted)
                }
            }

            if !copyDetection.isComplete {
                Button(L10n["onboarding.skip_step"]) {
                    advance()
                }
                .buttonStyle(.plain)
                .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
                .foregroundStyle(PastryPalette.muted)
                .padding(.trailing, Local.Onboarding.chromeOuterPadding)
                .padding(.bottom, Local.Onboarding.shakeDistance)
                .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.skipStepButton)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionStep: some View {
        stepLayout(
            icon: accessibilityTrusted ? "checkmark.circle.fill" : "hand.raised.fill",
            title: L10n["onboarding.permission.title"],
            subtitle: L10n["onboarding.permission.subtitle"]
        ) {
            VStack(spacing: Local.Onboarding.contentSpacing) {
                let model = AccessibilityPermissionRowModel.resolve(isTrusted: accessibilityTrusted)
                HStack(spacing: Local.Onboarding.insetSpacing) {
                    Image(systemName: model.iconName)
                        .font(.system(size: UIConstants.TypeSize.title2, weight: .bold))
                        .foregroundStyle(model.iconColor)
                        .frame(width: Local.Onboarding.permissionIconWidth)

                    VStack(alignment: .leading, spacing: Local.Onboarding.microSpacing) {
                        Text(model.title)
                            .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                        Text(model.subtitle)
                            .font(.system(size: UIConstants.TypeSize.label))
                            .foregroundStyle(PastryPalette.muted)
                    }

                    Spacer()

                    if !accessibilityTrusted {
                        Button(L10n["settings.accessibility_grant_btn"]) {
                            AccessibilityPermissionChecker.openSystemSettings()
                        }
                        .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                        .accessibilityIdentifier(AccessibilityIdentifiers.Onboarding.permissionButton)
                    }
                }
                .padding(Local.Onboarding.cardPadding)
                .frame(width: Local.Onboarding.permissionCardWidth)
                .frame(minHeight: Local.Onboarding.permissionCardMinHeight)
                .settingsCardChrome(cornerRadius: UIConstants.Radius.panel)

                Text(L10n["onboarding.permission.optional_hint"])
                    .font(.system(size: UIConstants.TypeSize.callout))
                    .foregroundStyle(PastryPalette.muted)
            }
        }
    }

    private func stepLayout<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Local.Onboarding.contentSpacing) {
            stepHeading(icon: icon, title: title, subtitle: subtitle)
                .frame(height: Local.Onboarding.headingSlotHeight, alignment: .top)
                .clipped()

            content()
                .frame(maxWidth: .infinity)
                .frame(height: Local.Onboarding.bodySlotHeight, alignment: .center)
                .clipped()
        }
        .padding(.horizontal, Local.Onboarding.contentHorizontalPadding)
    }

    private func stepHeading(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: Local.Onboarding.stackSpacing) {
            animatedSymbol(
                icon,
                size: Local.Onboarding.heroSymbolSize,
                color: PastryPalette.warmAccent
            )
            .frame(height: Local.Onboarding.heroSymbolFrameHeight)

            Text(title)
                .font(.system(size: UIConstants.TypeSize.display, weight: .bold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundStyle(PastryPalette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(Local.Onboarding.microSpacing)
                .frame(maxWidth: Local.Onboarding.headingMaxWidth)
        }
    }
    
    /// 图标切换时沿符号笔画轨迹擦除/绘制（与快捷键反馈一致的 Draw Off / Draw On）
    private func animatedSymbol(_ name: String, size: CGFloat, color: Color) -> some View {
        ZStack {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .transition(
                    AsymmetricTransition(
                        insertion: .symbolEffect(.drawOn),
                        removal: .symbolEffect(.drawOff)
                    )
                )
                .id(name)
        }
    }

    private func welcomeFeature(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Local.Onboarding.tightSpacing) {
            Image(systemName: icon)
                .font(.system(size: UIConstants.TypeSize.headline, weight: .semibold))
                .foregroundStyle(PastryPalette.warmAccent)
            Text(title)
                .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: Local.Onboarding.heroSymbolSize, alignment: .topLeading)
            Text(subtitle)
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundStyle(PastryPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Local.Onboarding.insetSpacing)
        .frame(
            maxWidth: .infinity,
            minHeight: Local.Onboarding.bodySlotHeight,
            maxHeight: Local.Onboarding.bodySlotHeight,
            alignment: .topLeading
        )
        .clipped()
        .settingsCardChrome(cornerRadius: UIConstants.Radius.panel)
    }

    private func advance() {
        guard let next = step.next else { return }
        withAnimation(reduceMotion ? nil : .default) { step = next }
    }

    private func promptForSampleCopy() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Local.Onboarding.copyPromptShakeDuration)) {
            copyPromptAttempts += 1
        }
    }

    private func copySampleText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(L10n["onboarding.copy.sample_text"], forType: .string)
        withAnimation(reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.paste)) {
            sampleTextCopied = true
        }
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermissionChecker.shared.isTrusted()
    }
}

private struct OnboardingShakeEffect: GeometryEffect {
    var progress: CGFloat
    let distance: CGFloat
    let oscillations: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(progress * .pi * 2 * oscillations) * distance
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
