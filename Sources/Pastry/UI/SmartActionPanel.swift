import AppKit
import EventKit
import SwiftUI

private enum SmartActionPanelLayout {
    static let width: CGFloat = 660
    static let height: CGFloat = 580
    static let bodyPadding: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let headerTopPadding: CGFloat = 12
    static let actionIconSize: CGFloat = 32
    static let imagePlaceholderSymbolSize: CGFloat = 36
    static let fieldLabelWidth: CGFloat = 78
    static let modelInputLimit = 8_000
}

private struct SmartActionTileButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.panel,
                fill: configuration.isPressed
                    ? PastryPalette.cardFill
                    : PastryPalette.cardFillSoft
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(isEnabled ? 1 : 0.46)
            .animation(
                reduceMotion ? nil : .easeOut(duration: UIConstants.Motion.instant),
                value: configuration.isPressed
            )
    }
}

private struct SmartActionPanelHeader: View {
    let subtitleKey: String

    var body: some View {
        HStack(spacing: 10) {
            AppIconImageView(size: 30)
                .shadow(
                    color: .black.opacity(UIConstants.Shadow.Icon.softOpacity),
                    radius: UIConstants.Shadow.Icon.softRadius,
                    x: 0,
                    y: UIConstants.Shadow.Icon.softY
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n["smart_action.title"])
                        .font(.system(size: UIConstants.TypeSize.title2, weight: .bold))
                    Image(systemName: "sparkles")
                        .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
                        .foregroundStyle(PastryPalette.warmAccent)
                }
                Text(L10n[subtitleKey])
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(PastryPalette.muted)
            }

            Spacer()
        }
        .padding(.horizontal, SmartActionPanelLayout.bodyPadding)
        .padding(.top, SmartActionPanelLayout.headerTopPadding)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }
}

private struct SmartActionChoiceLabel: View {
    let titleKey: String
    let descriptionKey: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
                .foregroundStyle(PastryPalette.warmInk)
                .frame(
                    width: SmartActionPanelLayout.actionIconSize,
                    height: SmartActionPanelLayout.actionIconSize
                )
                .background(
                    PastryPalette.warmAccent,
                    in: RoundedRectangle(
                        cornerRadius: UIConstants.Radius.button,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n[titleKey])
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(PastryPalette.ink)
                Text(L10n[descriptionKey])
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(PastryPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: UIConstants.TypeSize.caption, weight: .bold))
                .foregroundStyle(PastryPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
final class SmartActionPanelManager: NSObject, NSWindowDelegate {
    static let shared = SmartActionPanelManager()

    private var window: NSWindow?
    private var savedActivationPolicy: NSApplication.ActivationPolicy?

    func show(for item: ClipboardItem) {
        guard [.text, .rtf, .html, .image].contains(item.sourceFormat) else { return }
        OverlayPanelManager.shared.hide()

        if item.sourceFormat == .image {
            let imagePath = ImageCacheManager.shared.originalPath(forThumbnail: item.content)
                ?? item.content
            let previewImage = NSImage(contentsOfFile: item.content)
            present(NSHostingView(
                rootView: SmartActionImagePanelView(
                    imageURL: URL(fileURLWithPath: imagePath),
                    previewImage: previewImage,
                    fallbackText: item.textAnnotation,
                    capturedAt: item.timestamp,
                    sourceApplication: item.appName
                ) { [weak self] in
                    self?.window?.close()
                }
            ))
            return
        }

        let text = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let context = SmartActionContext(
            text: text,
            capturedAt: item.timestamp,
            sourceApplication: item.appName
        )
        present(makeContentView(context: context, itemID: item.id))
    }

    private func present(_ contentView: NSView) {
        if let window {
            window.contentView = contentView
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DeveloperDiagnostics.record(DiagnosticsEvent.smartActionOpen)
            return
        }

        savedActivationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SmartActionPanelLayout.width,
                height: SmartActionPanelLayout.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n["smart_action.title"]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 540)
        window.contentView = contentView
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DeveloperDiagnostics.record(DiagnosticsEvent.smartActionOpen)
    }

    private func makeContentView(context: SmartActionContext, itemID: UUID) -> NSView {
        NSHostingView(
            rootView: SmartActionPanelView(context: context, itemID: itemID) { [weak self] in
                self?.window?.close()
            }
        )
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if let savedActivationPolicy {
            NSApp.setActivationPolicy(savedActivationPolicy)
        }
        savedActivationPolicy = nil
    }
}

private struct SmartActionImagePanelView: View {
    private enum Stage {
        case choosing
        case processing
        case reviewing
    }

    private enum Action: String, Identifiable {
        case extractText
        case translateText
        case recognizeBarcode
        case describeImage

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .extractText: "smart_action.extract_text"
            case .translateText: "smart_action.translate"
            case .recognizeBarcode: "smart_action.barcode"
            case .describeImage: "smart_action.describe_image"
            }
        }

        var descriptionKey: String {
            switch self {
            case .extractText: "smart_action.extract_text.description"
            case .translateText: "smart_action.translate.description"
            case .recognizeBarcode: "smart_action.barcode.description"
            case .describeImage: "smart_action.describe_image.description"
            }
        }

        var symbolName: String {
            switch self {
            case .extractText: "text.viewfinder"
            case .translateText: "character.book.closed"
            case .recognizeBarcode: "barcode.viewfinder"
            case .describeImage: "photo.badge.magnifyingglass"
            }
        }
    }

    let imageURL: URL
    let previewImage: NSImage?
    let fallbackText: String?
    let capturedAt: Date
    let sourceApplication: String?
    let onClose: () -> Void

    @State private var stage: Stage = .choosing
    @State private var selectedAction: Action?
    @State private var resultText = ""
    @State private var errorMessage: String?
    @State private var processingTask: Task<Void, Never>?

    private let generator = LocalSmartActionGenerator.shared

    var body: some View {
        VStack(spacing: 0) {
            SmartActionPanelHeader(subtitleKey: "smart_action.image_subtitle")

            ScrollView {
                VStack(alignment: .leading, spacing: SmartActionPanelLayout.contentSpacing) {
                    sourceImagePreview
                    stageContent
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(.horizontal, SmartActionPanelLayout.bodyPadding)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(PastryPalette.cream)
        .foregroundStyle(PastryPalette.ink)
        .environment(\.colorScheme, .light)
        .onExitCommand(perform: onClose)
        .onDisappear { processingTask?.cancel() }
    }

    private var sourceImagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L10n["smart_action.source_image"], systemImage: "photo")
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundStyle(PastryPalette.muted)
                Spacer()
                if let sourceApplication, !sourceApplication.isEmpty {
                    Text(sourceApplication)
                        .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                        .foregroundStyle(PastryPalette.muted)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 20)
                        .settingsCardChrome(
                            cornerRadius: UIConstants.Radius.control,
                            fill: PastryPalette.cardFillSoft
                        )
                }
            }

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 190)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: SmartActionPanelLayout.imagePlaceholderSymbolSize))
                    .foregroundStyle(PastryPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(12)
        .settingsCardChrome(fill: PastryPalette.cardFill)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .choosing:
            actionChooser
        case .processing:
            processingView
        case .reviewing:
            resultReview
        }
    }

    private var actionChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(
                title: L10n["smart_action.choose_image_action"],
                subtitle: nil
            )

            VStack(spacing: 8) {
                ForEach(availableActions) { action in
                    Button {
                        perform(action)
                    } label: {
                        SmartActionChoiceLabel(
                            titleKey: action.titleKey,
                            descriptionKey: action.descriptionKey,
                            symbolName: action.symbolName
                        )
                    }
                    .buttonStyle(SmartActionTileButtonStyle())
                    .disabled(isDisabled(action))
                }
            }
        }
    }

    private var availableActions: [Action] {
        var actions: [Action] = [.extractText, .translateText, .recognizeBarcode]
        if #available(macOS 27.0, *) {
            actions.append(.describeImage)
        }
        return actions
    }

    private func isDisabled(_ action: Action) -> Bool {
        switch action {
        case .translateText:
            generator.availability != .available
        case .describeImage:
            if #available(macOS 27.0, *) {
                !ImageDescriptionGenerator.shared.isAvailable
            } else {
                true
            }
        case .extractText, .recognizeBarcode:
            false
        }
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(PastryPalette.warmAccent)
            Text(L10n["smart_action.image.processing"])
                .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
            if let selectedAction {
                Text(L10n[selectedAction.titleKey])
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(PastryPalette.muted)
            }
            Button(L10n["smart_action.cancel"]) { returnToChooser() }
                .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .panelSectionChrome()
    }

    private var resultReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                title: selectedAction.map { L10n[$0.titleKey] } ?? L10n["smart_action.review"],
                subtitle: L10n["smart_action.image.complete_result"]
            )
            TextField("", text: $resultText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundStyle(PastryPalette.ink)
                .lineLimit(3...)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .settingsCardChrome(
                    cornerRadius: UIConstants.Radius.button,
                    fill: PastryPalette.cardFillSoft,
                    clip: true
                )

            HStack(spacing: 10) {
                Spacer()
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.copy_result"]) { copyResult() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .panelSectionChrome()
    }

    private func sectionHeading(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(PastryPalette.muted)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
            .foregroundStyle(PastryPalette.danger)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.button,
                fill: PastryPalette.danger.opacity(UIConstants.Settings.washOpacity)
            )
    }

    private func perform(_ action: Action) {
        processingTask?.cancel()
        selectedAction = action
        errorMessage = nil
        stage = .processing
        processingTask = Task {
            do {
                let result = switch action {
                case .extractText:
                    try await recognizedText()
                case .translateText:
                    try await translatedText()
                case .recognizeBarcode:
                    try await recognizedBarcodes()
                case .describeImage:
                    try await imageDescription()
                }
                try Task.checkCancellation()
                resultText = result
                stage = .reviewing
                DeveloperDiagnostics.record("smart_action.image.\(action.rawValue)")
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                stage = .choosing
            }
        }
    }

    private func recognizedText() async throws -> String {
        let recognized = try await ImageTextRecognizer.recognizeText(at: imageURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallbackText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = recognized.isEmpty ? fallback : recognized
        guard !text.isEmpty else { throw ImageAnalysisError.noText }
        return text
    }

    private func translatedText() async throws -> String {
        let text = try await recognizedText()
        let context = SmartActionContext(
            text: text,
            capturedAt: capturedAt,
            sourceApplication: sourceApplication
        )
        guard case .generatedText(let draft) = try await generator.generate(
            kind: .translate,
            context: context,
            instruction: nil
        ) else { throw SmartActionError.emptyResult }
        return draft.text
    }

    private func recognizedBarcodes() async throws -> String {
        let barcodes = try await ImageBarcodeRecognizer.recognizeBarcodes(at: imageURL)
        guard !barcodes.isEmpty else { throw ImageAnalysisError.noBarcode }
        return barcodes
            .map { "\($0.symbology): \($0.payload)" }
            .joined(separator: "\n\n")
    }

    private func imageDescription() async throws -> String {
        if #available(macOS 27.0, *) {
            return try await ImageDescriptionGenerator.shared.describe(imageURL: imageURL)
        }
        throw ImageAnalysisError.descriptionUnavailable
    }

    private func returnToChooser() {
        processingTask?.cancel()
        processingTask = nil
        selectedAction = nil
        resultText = ""
        errorMessage = nil
        stage = .choosing
    }

    private func copyResult() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        PasteboardWriter.writePlainText(text)
        ClipboardMonitor.shared.playCopyFeedbackForCurrentChange()
        DeveloperDiagnostics.record("smart_action.image.copy_result")
    }
}

private struct SmartActionPanelView: View {
    private enum Stage {
        case choosing
        case customInstruction
        case generating
        case reviewing
    }

    let context: SmartActionContext
    let itemID: UUID
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .choosing
    @State private var selectedKind: SmartActionKind?
    @State private var draft: SmartActionDraft?
    @State private var customInstruction = ""
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var isExecuting = false

    private let generator = LocalSmartActionGenerator.shared

    var body: some View {
        VStack(spacing: 0) {
            SmartActionPanelHeader(subtitleKey: "smart_action.subtitle")

            VStack(alignment: .leading, spacing: SmartActionPanelLayout.contentSpacing) {
                sourcePreview
                stageContent
                if let errorMessage {
                    errorBanner(errorMessage)
                }
            }
            .padding(.horizontal, SmartActionPanelLayout.bodyPadding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(PastryPalette.cream)
        .foregroundStyle(PastryPalette.ink)
        .environment(\.colorScheme, .light)
        .onExitCommand(perform: onClose)
        .onDisappear { generationTask?.cancel() }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.medium),
            value: stage
        )
    }


    private var sourcePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L10n["smart_action.source"], systemImage: "doc.text")
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundStyle(PastryPalette.muted)
                Spacer()
                if let sourceApplication = context.sourceApplication, !sourceApplication.isEmpty {
                    Text(sourceApplication)
                        .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                        .foregroundStyle(PastryPalette.muted)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 20)
                        .settingsCardChrome(
                            cornerRadius: UIConstants.Radius.control,
                            fill: PastryPalette.cardFillSoft
                        )
                }
            }

            Text(context.text)
                .font(.system(size: UIConstants.TypeSize.body))
                .foregroundStyle(PastryPalette.ink)
                .lineSpacing(2)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .settingsCardChrome(fill: PastryPalette.cardFill)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .choosing:
            actionChooser
                .transition(.opacity)
        case .customInstruction:
            customInstructionEditor
                .transition(.opacity)
        case .generating:
            generatingView
                .transition(.opacity)
        case .reviewing:
            reviewView
                .transition(.opacity)
        }
    }

    private var actionChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(
                title: L10n["smart_action.choose"],
                subtitle: generator.availability == .available ? nil : availabilityMessage
            )

            VStack(spacing: 8) {
                ForEach(availableActionKinds) { kind in
                    Button {
                        choose(kind)
                    } label: {
                        SmartActionChoiceLabel(
                            titleKey: kind.titleKey,
                            descriptionKey: kind.descriptionKey,
                            symbolName: kind.symbolName
                        )
                    }
                    .buttonStyle(SmartActionTileButtonStyle())
                    .disabled(generator.availability != .available)
                    .accessibilityIdentifier("smartAction.kind.\(kind.rawValue)")
                }
            }
        }
    }

    private var availableActionKinds: [SmartActionKind] {
        [.summarize, .rewrite, .customText, .calendarEvent, .emailDraft]
    }

    private var customInstructionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(
                title: L10n["smart_action.custom"],
                subtitle: L10n["smart_action.custom.prompt"]
            )
            TextField(
                L10n["smart_action.custom.prompt"],
                text: $customInstruction,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: UIConstants.TypeSize.body))
            .foregroundStyle(PastryPalette.ink)
            .lineLimit(3 ... 6)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.button,
                fill: PastryPalette.cardFillSoft,
                clip: true
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.SmartAction.customInstruction)
            actionFooter {
                Button(L10n["smart_action.cancel"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.generate"]) {
                    generate(.customText, instruction: customInstruction)
                }
                .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                .disabled(customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .panelSectionChrome()
    }

    private var generatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(PastryPalette.warmAccent)
            Text(L10n["smart_action.generating"])
                .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
                .foregroundStyle(PastryPalette.ink)
            Text(L10n["smart_action.review_hint"])
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundStyle(PastryPalette.muted)
            Button(L10n["smart_action.cancel"]) { returnToChooser() }
                .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .panelSectionChrome()
    }

    @ViewBuilder
    private var reviewView: some View {
        if let draft {
            switch draft {
            case .generatedText:
                generatedTextReview
            case .calendarEvent:
                calendarReview
            case .email:
                emailReview
            }
        }
    }

    private var generatedTextReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeading
            styledGrowingTextField(text: generatedTextBinding)
            .accessibilityIdentifier(AccessibilityIdentifiers.SmartAction.generatedText)
            actionFooter {
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.copy_result"]) { copyGeneratedText() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(
                        generatedTextBinding.wrappedValue
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
            }
        }
        .panelSectionChrome()
    }

    private var calendarReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeading
            VStack(spacing: 0) {
                fieldRow("smart_action.field.title") {
                    TextField(L10n["smart_action.field.title"], text: calendarTitleBinding)
                        .textFieldStyle(.plain)
                }
                settingsDivider
                fieldRow("smart_action.field.all_day") {
                    Toggle("", isOn: calendarAllDayBinding)
                        .labelsHidden()
                        .toggleStyle(SettingsSwitchStyle())
                }
                settingsDivider
                fieldRow("smart_action.field.start") {
                    DatePicker(
                        "",
                        selection: calendarStartBinding,
                        displayedComponents: calendarAllDayBinding.wrappedValue
                            ? [.date]
                            : [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(PastryPalette.warmAccent)
                }
                settingsDivider
                fieldRow("smart_action.field.end") {
                    DatePicker(
                        "",
                        selection: calendarEndBinding,
                        in: calendarStartBinding.wrappedValue...,
                        displayedComponents: calendarAllDayBinding.wrappedValue
                            ? [.date]
                            : [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(PastryPalette.warmAccent)
                }
                settingsDivider
                fieldRow("smart_action.field.location") {
                    TextField(L10n["smart_action.field.location"], text: calendarLocationBinding)
                        .textFieldStyle(.plain)
                }
            }
            .settingsCardChrome(fill: PastryPalette.cardFillSoft, clip: true)

            editorSection(title: L10n["smart_action.field.notes"]) {
                styledGrowingTextField(text: calendarNotesBinding)
            }

            if calendarUsedRelativeDate {
                Label(
                    L10n["smart_action.relative_date", Self.shortDate.string(from: calendarCapturedAt)],
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundStyle(PastryPalette.muted)
            }

            actionFooter {
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.add_calendar"]) { saveCalendarEvent() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(isExecuting || !calendarDraftIsValid)
            }
        }
        .panelSectionChrome()
    }

    private var emailReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeading
            VStack(spacing: 0) {
                fieldRow("smart_action.field.recipients") {
                    TextField(
                        L10n["smart_action.field.recipients_placeholder"],
                        text: emailRecipientsBinding
                    )
                    .textFieldStyle(.plain)
                }
                settingsDivider
                fieldRow("smart_action.field.subject") {
                    TextField(L10n["smart_action.field.subject"], text: emailSubjectBinding)
                        .textFieldStyle(.plain)
                }
            }
            .settingsCardChrome(fill: PastryPalette.cardFillSoft, clip: true)

            editorSection(title: L10n["smart_action.field.body"]) {
                styledGrowingTextField(text: emailBodyBinding)
            }

            actionFooter {
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.copy_result"]) { copyEmailBody() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.open_mail"]) { openEmailDraft() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(
                        emailSubjectBinding.wrappedValue
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                            || emailBodyBinding.wrappedValue
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
            }
        }
        .panelSectionChrome()
    }

    private var reviewHeading: some View {
        sectionHeading(
            title: selectedKind.map { L10n[$0.titleKey] } ?? L10n["smart_action.review"],
            subtitle: L10n["smart_action.review_hint"]
        )
    }

    private func sectionHeading(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
                .foregroundStyle(PastryPalette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(PastryPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldRow<Content: View>(
        _ key: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(L10n[key])
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundStyle(PastryPalette.muted)
                .frame(width: SmartActionPanelLayout.fieldLabelWidth, alignment: .trailing)
            content()
                .foregroundStyle(PastryPalette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, UIConstants.Settings.rowHorizontalPadding)
        .frame(minHeight: UIConstants.Settings.rowMinHeight)
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(PastryPalette.hairline)
            .frame(height: UIConstants.Stroke.hairline)
            .padding(.leading, SmartActionPanelLayout.fieldLabelWidth + 26)
    }

    private func editorSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundStyle(PastryPalette.muted)
            content()
        }
    }

    private func styledGrowingTextField(
        text: Binding<String>,
        minimumLines: Int = 2,
        maximumLines: Int = 10
    ) -> some View {
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: UIConstants.TypeSize.body))
            .foregroundStyle(PastryPalette.ink)
            .lineLimit(minimumLines ... maximumLines)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.button,
                fill: PastryPalette.cardFillSoft,
                clip: true
            )
    }

    private func actionFooter<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Spacer()
            content()
        }
        .padding(.top, 2)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
            .foregroundStyle(PastryPalette.danger)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.button,
                fill: PastryPalette.danger.opacity(UIConstants.Settings.washOpacity)
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.SmartAction.error)
    }

    private func choose(_ kind: SmartActionKind) {
        errorMessage = nil
        selectedKind = kind
        switch kind {
        case .customText:
            stage = .customInstruction
        default:
            generate(kind)
        }
    }

    private func generate(_ kind: SmartActionKind, instruction: String? = nil) {
        generationTask?.cancel()
        selectedKind = kind
        errorMessage = nil
        stage = .generating
        generationTask = Task {
            do {
                let sourceText = await Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.loadContentPrefix(
                        id: itemID,
                        characterLimit: SmartActionPanelLayout.modelInputLimit
                    )
                }.value ?? context.text
                try Task.checkCancellation()
                let generationContext = SmartActionContext(
                    text: sourceText,
                    capturedAt: context.capturedAt,
                    sourceApplication: context.sourceApplication,
                    locale: Locale(identifier: context.localeIdentifier),
                    timeZone: context.timeZone
                )
                let generated = try await generator.generate(
                    kind: kind,
                    context: generationContext,
                    instruction: instruction
                )
                try Task.checkCancellation()
                draft = generated
                stage = .reviewing
                DeveloperDiagnostics.record("smart_action.generate.\(kind.rawValue)")
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                stage = kind == .customText ? .customInstruction : .choosing
            }
        }
    }

    private func returnToChooser() {
        generationTask?.cancel()
        generationTask = nil
        draft = nil
        selectedKind = nil
        errorMessage = nil
        isExecuting = false
        stage = .choosing
    }


    private func copyGeneratedText() {
        let text = generatedTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        PasteboardWriter.writePlainText(text)
        ClipboardMonitor.shared.playCopyFeedbackForCurrentChange()
        DeveloperDiagnostics.record("smart_action.copy_text")
    }

    private func copyEmailBody() {
        let body = emailBodyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        PasteboardWriter.writePlainText(body)
        ClipboardMonitor.shared.playCopyFeedbackForCurrentChange()
        DeveloperDiagnostics.record("smart_action.copy_email")
    }

    private func saveCalendarEvent() {
        guard case .calendarEvent(let calendarDraft) = draft else { return }
        isExecuting = true
        errorMessage = nil
        Task {
            do {
                try await CalendarEventWriter.shared.save(calendarDraft)
                DeveloperDiagnostics.record("smart_action.calendar.saved")
                onClose()
            } catch {
                errorMessage = error.localizedDescription
                isExecuting = false
            }
        }
    }

    private func openEmailDraft() {
        guard case .email(let emailDraft) = draft else { return }
        do {
            try EmailDraftOpener.open(emailDraft)
            DeveloperDiagnostics.record("smart_action.email.opened")
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var availabilityMessage: String {
        SmartActionError.modelUnavailable(generator.availability).localizedDescription
    }

    private var generatedTextBinding: Binding<String> {
        Binding(
            get: {
                guard case .generatedText(let value) = draft else { return "" }
                return value.text
            },
            set: { draft = .generatedText(GeneratedTextDraft(text: $0)) }
        )
    }

    private var calendarTitleBinding: Binding<String> { calendarBinding(\.title, default: "") }
    private var calendarStartBinding: Binding<Date> { calendarBinding(\.startDate, default: Date()) }
    private var calendarEndBinding: Binding<Date> { calendarBinding(\.endDate, default: Date()) }
    private var calendarAllDayBinding: Binding<Bool> { calendarBinding(\.isAllDay, default: false) }
    private var calendarLocationBinding: Binding<String> { calendarBinding(\.location, default: "") }
    private var calendarNotesBinding: Binding<String> { calendarBinding(\.notes, default: "") }

    private func calendarBinding<Value>(
        _ keyPath: WritableKeyPath<CalendarEventDraft, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard case .calendarEvent(let value) = draft else { return defaultValue }
                return value[keyPath: keyPath]
            },
            set: { newValue in
                guard case .calendarEvent(var value) = draft else { return }
                value[keyPath: keyPath] = newValue
                draft = .calendarEvent(value)
            }
        )
    }

    private var calendarCapturedAt: Date {
        guard case .calendarEvent(let value) = draft else { return context.capturedAt }
        return value.capturedAt
    }

    private var calendarUsedRelativeDate: Bool {
        guard case .calendarEvent(let value) = draft else { return false }
        return value.usedRelativeDate
    }

    private var calendarDraftIsValid: Bool {
        !calendarTitleBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && calendarEndBinding.wrappedValue >= calendarStartBinding.wrappedValue
    }

    private var emailRecipientsBinding: Binding<String> {
        Binding(
            get: {
                guard case .email(let value) = draft else { return "" }
                return value.recipients.joined(separator: ", ")
            },
            set: { newValue in
                guard case .email(var value) = draft else { return }
                value.recipients = Self.splitRecipients(newValue)
                draft = .email(value)
            }
        )
    }

    private var emailSubjectBinding: Binding<String> { emailBinding(\.subject) }
    private var emailBodyBinding: Binding<String> { emailBinding(\.body) }

    private func emailBinding(_ keyPath: WritableKeyPath<EmailDraft, String>) -> Binding<String> {
        Binding(
            get: {
                guard case .email(let value) = draft else { return "" }
                return value[keyPath: keyPath]
            },
            set: { newValue in
                guard case .email(var value) = draft else { return }
                value[keyPath: keyPath] = newValue
                draft = .email(value)
            }
        )
    }

    private static func splitRecipients(_ value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension View {
    func panelSectionChrome() -> some View {
        padding(12)
            .settingsCardChrome(fill: PastryPalette.cardFill)
    }
}

@MainActor
private final class CalendarEventWriter {
    static let shared = CalendarEventWriter()

    private let eventStore = EKEventStore()

    func save(_ draft: CalendarEventDraft) async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        let granted: Bool
        if status == .notDetermined {
            granted = try await eventStore.requestWriteOnlyAccessToEvents()
        } else {
            granted = status == .writeOnly || status == .fullAccess
        }
        guard granted else { throw CalendarEventWriterError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarEventWriterError.noDefaultCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.isAllDay = draft.isAllDay
        if draft.isAllDay {
            let systemCalendar = Calendar.autoupdatingCurrent
            event.startDate = systemCalendar.startOfDay(for: draft.startDate)
            let inclusiveEnd = max(draft.startDate, draft.endDate)
            event.endDate = systemCalendar.date(
                byAdding: .day,
                value: 1,
                to: systemCalendar.startOfDay(for: inclusiveEnd)
            )
        } else {
            guard draft.endDate > draft.startDate else {
                throw CalendarEventWriterError.invalidDateRange
            }
            event.startDate = draft.startDate
            event.endDate = draft.endDate
        }
        event.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
}

private enum CalendarEventWriterError: LocalizedError {
    case accessDenied
    case noDefaultCalendar
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .accessDenied: L10n["smart_action.error.calendar_denied"]
        case .noDefaultCalendar: L10n["smart_action.error.no_calendar"]
        case .invalidDateRange: L10n["smart_action.error.invalid_range"]
        }
    }
}

@MainActor
private enum EmailDraftOpener {
    static func open(_ draft: EmailDraft) throws {
        guard let service = NSSharingService(named: .composeEmail) else {
            throw EmailDraftOpenerError.unavailable
        }
        service.recipients = draft.recipients
        service.subject = draft.subject
        let items: [Any] = [draft.body]
        guard service.canPerform(withItems: items) else {
            throw EmailDraftOpenerError.unavailable
        }
        service.perform(withItems: items)
    }
}

private enum EmailDraftOpenerError: LocalizedError {
    case unavailable

    var errorDescription: String? { L10n["smart_action.error.mail_unavailable"] }
}
