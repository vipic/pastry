import AppKit
import SwiftUI

struct MultiSmartActionPanelView: View {
    private enum Local {
        static let sourcePreviewHeight: CGFloat = 112
        static let sourceImageMaximumHeight: CGFloat = 96
        static let compactActionMinimumHeight: CGFloat = 36
    }

    private enum Stage: Equatable {
        case choosing
        case customInstruction
        case processing
        case reviewing
    }

    let items: [ClipboardItem]
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .choosing
    @State private var selectedAction: MultiSmartActionKind?
    @State private var draft: MultiSmartActionDraft?
    @State private var customInstruction = ""
    @State private var errorMessage: String?
    @State private var processingTask: Task<Void, Never>?
    @State private var savedCalendarIndices: Set<Int> = []
    @State private var selectedSourceIndex = 0
    @State private var originalTextByID: [UUID: String] = [:]
    @State private var loadedTextIDs: Set<UUID> = []

    private let generator = MultiSmartActionGenerator.shared

    private var sources: [MultiSmartActionSource] {
        items.map(MultiSmartActionSource.init)
    }

    private var mode: MultiSmartSelectionMode {
        MultiSmartActionSelection.mode(for: items) ?? .mixed
    }

    private var textCount: Int {
        items.count { $0.sourceFormat != .image }
    }

    private var imageCount: Int {
        items.count { $0.sourceFormat == .image }
    }

    var body: some View {
        VStack(spacing: 0) {
            SmartActionPanelHeader(subtitleKey: "smart_action.multi.subtitle")

            VStack(alignment: .leading, spacing: SmartActionPanelLayout.contentSpacing) {
                selectionPreview

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: SmartActionPanelLayout.contentSpacing) {
                        stageContent
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, SmartActionPanelLayout.bodyPadding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            actionTray
        }
        .frame(minWidth: 600, minHeight: 540)
        .background(PastryPalette.cream)
        .foregroundStyle(PastryPalette.ink)
        .environment(\.colorScheme, .light)
        .onExitCommand(perform: onClose)
        .onDisappear { processingTask?.cancel() }
        .task(id: selectedSourceID) {
            await loadSelectedOriginalText()
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: UIConstants.Motion.medium),
            value: stage
        )
    }

    private var selectionPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    L10n["smart_action.multi.selection_count", items.count],
                    systemImage: "square.stack.3d.up"
                )
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundStyle(PastryPalette.muted)
                Spacer()
                Text(selectionBreakdown)
                    .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                    .foregroundStyle(PastryPalette.muted)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 20)
                    .settingsCardChrome(
                        cornerRadius: UIConstants.Radius.control,
                        fill: PastryPalette.cardFillSoft
                    )
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        let isSelected = selectedSourceIndex == offset
                        Button {
                            selectedSourceIndex = offset
                        } label: {
                            Label(
                                "\(offset + 1)",
                                systemImage: item.sourceFormat == .image ? "photo" : "doc.text"
                            )
                            .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                            .foregroundStyle(isSelected ? .white : PastryPalette.ink)
                            .padding(.horizontal, 7)
                            .frame(minHeight: 24)
                            .settingsCardChrome(
                                cornerRadius: UIConstants.Radius.control,
                                fill: isSelected
                                    ? PastryPalette.primaryActionFill
                                    : PastryPalette.cardFillSoft
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            L10n["smart_action.multi.source_number", offset + 1]
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            sourceDetailPreview
        }
        .padding(12)
        .settingsCardChrome(fill: PastryPalette.cardFill)
    }

    @ViewBuilder
    private var sourceDetailPreview: some View {
        if items.indices.contains(selectedSourceIndex) {
            let item = items[selectedSourceIndex]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n["smart_action.multi.original_content", selectedSourceIndex + 1])
                        .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                        .foregroundStyle(PastryPalette.ink)
                    Spacer()
                    if let appName = item.appName, !appName.isEmpty {
                        Text(appName)
                            .font(.system(size: UIConstants.TypeSize.caption))
                            .foregroundStyle(PastryPalette.muted)
                    }
                    Text(Self.sourceDateFormatter.string(from: item.timestamp))
                        .font(.system(size: UIConstants.TypeSize.caption))
                        .foregroundStyle(PastryPalette.muted)
                }

                if item.sourceFormat == .image {
                    imageSourcePreview(item)
                } else {
                    textSourcePreview(item)
                }
            }
            .padding(10)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.button,
                fill: PastryPalette.cardFillSoft,
                clip: true
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.SmartAction.multiSourcePreview)
        }
    }

    private func textSourcePreview(_ item: ClipboardItem) -> some View {
        Group {
            if loadedTextIDs.contains(item.id) {
                ScrollView(.vertical) {
                    Text(originalTextByID[item.id] ?? item.content)
                        .font(.system(size: UIConstants.TypeSize.body))
                        .foregroundStyle(PastryPalette.ink)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(PastryPalette.warmAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(L10n["smart_action.multi.loading_source"])
            }
        }
        .frame(height: Local.sourcePreviewHeight)
        .clipped()
    }

    private func imageSourcePreview(_ item: ClipboardItem) -> some View {
        let imagePath = ImageCacheManager.shared.originalPath(forThumbnail: item.content)
            ?? item.content
        return Group {
            if let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: Local.sourceImageMaximumHeight)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: SmartActionPanelLayout.imagePlaceholderSymbolSize))
                        .foregroundStyle(PastryPalette.muted)
                    if let annotation = item.textAnnotation, !annotation.isEmpty {
                        Text(annotation)
                            .font(.system(size: UIConstants.TypeSize.caption))
                            .foregroundStyle(PastryPalette.muted)
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Local.sourcePreviewHeight)
        .clipped()
    }

    private var selectedSourceID: UUID? {
        guard items.indices.contains(selectedSourceIndex) else { return nil }
        return items[selectedSourceIndex].id
    }

    private func loadSelectedOriginalText() async {
        guard items.indices.contains(selectedSourceIndex) else { return }
        let item = items[selectedSourceIndex]
        guard item.sourceFormat != .image,
              !loadedTextIDs.contains(item.id)
        else { return }
        let id = item.id
        let fallback = item.content
        let loaded = await Task.detached(priority: .userInitiated) {
            DatabaseManager.shared.loadFullContent(id: id) ?? fallback
        }.value
        guard !Task.isCancelled else { return }
        originalTextByID[id] = loaded
        loadedTextIDs.insert(id)
    }

    private static let sourceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var selectionBreakdown: String {
        switch mode {
        case .text:
            L10n["smart_action.multi.text_count", textCount]
        case .image:
            L10n["smart_action.multi.image_count", imageCount]
        case .mixed:
            L10n["smart_action.multi.mixed_count", textCount, imageCount]
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .choosing:
            Text(L10n["smart_action.multi.choose"])
                .font(.system(size: UIConstants.TypeSize.label))
                .foregroundStyle(PastryPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .customInstruction:
            customInstructionEditor
        case .processing:
            processingView
        case .reviewing:
            reviewView
        }
    }

    @ViewBuilder
    private var actionTray: some View {
        if stage == .choosing {
            expandedActionTray
        } else {
            compactActionTray
        }
    }

    private var expandedActionTray: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(availableActions) { action in
                Button {
                    choose(action)
                } label: {
                    SmartActionChoiceLabel(
                        titleKey: action.titleKey,
                        descriptionKey: action.descriptionKey,
                        symbolName: action.symbolName
                    )
                }
                .buttonStyle(SmartActionTileButtonStyle())
                .disabled(isDisabled(action))
                .accessibilityIdentifier("smartAction.multi.\(action.rawValue)")
            }
        }
        .padding(.horizontal, SmartActionPanelLayout.bodyPadding)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }

    private var compactActionTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(availableActions) { action in
                    let isSelected = selectedAction == action
                    Button {
                        choose(action)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: action.symbolName)
                                .font(.system(
                                    size: UIConstants.TypeSize.callout,
                                    weight: .semibold
                                ))
                            Text(L10n[action.titleKey])
                                .font(.system(
                                    size: UIConstants.TypeSize.label,
                                    weight: .semibold
                                ))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .white : PastryPalette.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: Local.compactActionMinimumHeight)
                        .settingsCardChrome(
                            cornerRadius: UIConstants.Radius.button,
                            fill: isSelected
                                ? PastryPalette.primaryActionFill
                                : PastryPalette.cardFillSoft
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled(action))
                    .accessibilityIdentifier("smartAction.multi.\(action.rawValue)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, SmartActionPanelLayout.bodyPadding)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PastryPalette.hairline)
                .frame(height: UIConstants.Stroke.hairline)
        }
    }

    private var availableActions: [MultiSmartActionKind] {
        MultiSmartActionSelection.actions(
            for: mode,
            supportsImageDescription: supportsImageDescription
        )
    }

    private var supportsImageDescription: Bool {
        if #available(macOS 27.0, *) {
            return ImageDescriptionGenerator.shared.isAvailable
        }
        return false
    }

    private func isDisabled(_ action: MultiSmartActionKind) -> Bool {
        if action == .describeImages { return !supportsImageDescription }
        return action.requiresLanguageModel && generator.availability != .available
    }

    private var customInstructionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(L10n["smart_action.multi.custom.title"])
            TextField(
                L10n["smart_action.multi.custom.prompt"],
                text: $customInstruction,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: UIConstants.TypeSize.body))
            .lineLimit(3 ... 6)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .settingsCardChrome(
                cornerRadius: UIConstants.Radius.button,
                fill: PastryPalette.cardFillSoft,
                clip: true
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.SmartAction.multiCustomInstruction)
            .onKeyPress(.return, phases: .down) { keyPress in
                guard !keyPress.modifiers.contains(.shift) else { return .ignored }
                submitCustomInstruction()
                return .handled
            }

            footer {
                Button(L10n["smart_action.cancel"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.execute"]) { submitCustomInstruction() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .panelSectionChrome()
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(PastryPalette.warmAccent)
            if let selectedAction {
                Text(L10n[selectedAction.processingKey])
                    .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
            }
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
            case .text:
                textReview
            case .calendarEvents:
                calendarEventsReview
            case .email:
                emailReview
            }
        }
    }

    private var textReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeading
            TextField("", text: textResultBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: UIConstants.TypeSize.body))
                .lineLimit(5 ... 18)
                .padding(10)
                .settingsCardChrome(
                    cornerRadius: UIConstants.Radius.button,
                    fill: PastryPalette.cardFillSoft,
                    clip: true
                )
                .accessibilityIdentifier(AccessibilityIdentifiers.SmartAction.multiResult)
            footer {
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.copy"]) { copyTextResult() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(textResultBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .panelSectionChrome()
    }

    private var calendarEventsReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeading
            if case .calendarEvents(let events) = draft {
                ForEach(events.indices, id: \.self) { index in
                    calendarEventEditor(index: index)
                }
            }
            footer {
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
            }
        }
        .panelSectionChrome()
    }

    private func calendarEventEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n["smart_action.multi.calendar_candidate", index + 1])
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundStyle(PastryPalette.muted)
            TextField(
                L10n["smart_action.field.title"],
                text: calendarBinding(index: index, keyPath: \.title, default: "")
            )
            .textFieldStyle(.plain)
            Toggle(
                L10n["smart_action.field.all_day"],
                isOn: calendarBinding(index: index, keyPath: \.isAllDay, default: false)
            )
            .toggleStyle(SettingsSwitchStyle())
            HStack(spacing: 10) {
                DatePicker(
                    L10n["smart_action.field.start"],
                    selection: calendarBinding(index: index, keyPath: \.startDate, default: Date()),
                    displayedComponents: calendarIsAllDay(index: index)
                        ? [.date]
                        : [.date, .hourAndMinute]
                )
                DatePicker(
                    L10n["smart_action.field.end"],
                    selection: calendarBinding(index: index, keyPath: \.endDate, default: Date()),
                    displayedComponents: calendarIsAllDay(index: index)
                        ? [.date]
                        : [.date, .hourAndMinute]
                )
            }
            TextField(
                L10n["smart_action.field.location"],
                text: calendarBinding(index: index, keyPath: \.location, default: "")
            )
            .textFieldStyle(.plain)
            TextField(
                L10n["smart_action.field.notes"],
                text: calendarBinding(index: index, keyPath: \.notes, default: ""),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(2 ... 5)
            footer {
                Button(
                    L10n[savedCalendarIndices.contains(index)
                        ? "smart_action.multi.calendar_added"
                        : "smart_action.add_calendar"]
                ) {
                    saveCalendarEvent(index: index)
                }
                .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                .disabled(savedCalendarIndices.contains(index) || !calendarDraftIsValid(index: index))
            }
        }
        .padding(10)
        .settingsCardChrome(
            cornerRadius: UIConstants.Radius.button,
            fill: PastryPalette.cardFillSoft,
            clip: true
        )
    }

    private var emailReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeading
            TextField(
                L10n["smart_action.field.recipients_placeholder"],
                text: emailRecipientsBinding
            )
            .textFieldStyle(.roundedBorder)
            TextField(L10n["smart_action.field.subject"], text: emailSubjectBinding)
                .textFieldStyle(.roundedBorder)
            TextField(L10n["smart_action.field.body"], text: emailBodyBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(5 ... 14)
                .padding(10)
                .settingsCardChrome(
                    cornerRadius: UIConstants.Radius.button,
                    fill: PastryPalette.cardFillSoft,
                    clip: true
                )
            footer {
                Button(L10n["smart_action.back"]) { returnToChooser() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.copy"]) { copyEmailBody() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                Button(L10n["smart_action.open_mail"]) { openEmailDraft() }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(
                        emailSubjectBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || emailBodyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .panelSectionChrome()
    }

    private var reviewHeading: some View {
        sectionHeading(
            selectedAction.map { L10n[$0.titleKey] } ?? L10n["smart_action.review"]
        )
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: UIConstants.TypeSize.title, weight: .semibold))
            .foregroundStyle(PastryPalette.ink)
    }

    private func footer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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
    }

    private func choose(_ action: MultiSmartActionKind) {
        errorMessage = nil
        selectedAction = action
        if action == .custom {
            stage = .customInstruction
        } else {
            generate(action)
        }
    }

    private func submitCustomInstruction() {
        let instruction = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        generate(.custom, instruction: instruction)
    }

    private func generate(_ action: MultiSmartActionKind, instruction: String? = nil) {
        processingTask?.cancel()
        selectedAction = action
        draft = nil
        savedCalendarIndices = []
        errorMessage = nil
        stage = .processing
        let generationSources = sources
        processingTask = Task {
            do {
                let generated = try await generator.generate(
                    action: action,
                    sources: generationSources,
                    customInstruction: instruction
                )
                try Task.checkCancellation()
                draft = generated
                stage = .reviewing
                DeveloperDiagnostics.record("smart_action.multi.\(action.rawValue)")
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                stage = action == .custom ? .customInstruction : .choosing
            }
        }
    }

    private func returnToChooser() {
        processingTask?.cancel()
        processingTask = nil
        selectedAction = nil
        draft = nil
        savedCalendarIndices = []
        errorMessage = nil
        stage = .choosing
    }

    private func copyTextResult() {
        let text = textResultBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        PasteboardWriter.writePlainText(text)
        ClipboardMonitor.shared.playCopyFeedbackForCurrentChange()
        DeveloperDiagnostics.record("smart_action.multi.copy_text")
    }

    private func copyEmailBody() {
        let text = emailBodyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        PasteboardWriter.writePlainText(text)
        ClipboardMonitor.shared.playCopyFeedbackForCurrentChange()
        DeveloperDiagnostics.record("smart_action.multi.copy_email")
    }

    private func saveCalendarEvent(index: Int) {
        guard case .calendarEvents(let events) = draft, events.indices.contains(index) else { return }
        errorMessage = nil
        Task {
            do {
                try await CalendarEventWriter.shared.save(events[index])
                savedCalendarIndices.insert(index)
                DeveloperDiagnostics.record("smart_action.multi.calendar.saved")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openEmailDraft() {
        guard case .email(let email) = draft else { return }
        do {
            try EmailDraftOpener.open(email)
            DeveloperDiagnostics.record("smart_action.multi.email.opened")
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var textResultBinding: Binding<String> {
        Binding(
            get: {
                guard case .text(let text) = draft else { return "" }
                return text
            },
            set: { draft = .text($0) }
        )
    }

    private func calendarBinding<Value>(
        index: Int,
        keyPath: WritableKeyPath<CalendarEventDraft, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard case .calendarEvents(let events) = draft,
                      events.indices.contains(index)
                else { return defaultValue }
                return events[index][keyPath: keyPath]
            },
            set: { newValue in
                guard case .calendarEvents(var events) = draft,
                      events.indices.contains(index)
                else { return }
                events[index][keyPath: keyPath] = newValue
                draft = .calendarEvents(events)
                savedCalendarIndices.remove(index)
            }
        )
    }

    private func calendarDraftIsValid(index: Int) -> Bool {
        guard case .calendarEvents(let events) = draft,
              events.indices.contains(index)
        else { return false }
        let event = events[index]
        return !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && event.endDate >= event.startDate
    }

    private func calendarIsAllDay(index: Int) -> Bool {
        guard case .calendarEvents(let events) = draft,
              events.indices.contains(index)
        else { return false }
        return events[index].isAllDay
    }

    private var emailRecipientsBinding: Binding<String> {
        Binding(
            get: {
                guard case .email(let email) = draft else { return "" }
                return email.recipients.joined(separator: ", ")
            },
            set: { newValue in
                guard case .email(var email) = draft else { return }
                email.recipients = newValue
                    .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                draft = .email(email)
            }
        )
    }

    private var emailSubjectBinding: Binding<String> { emailBinding(\.subject) }
    private var emailBodyBinding: Binding<String> { emailBinding(\.body) }

    private func emailBinding(_ keyPath: WritableKeyPath<EmailDraft, String>) -> Binding<String> {
        Binding(
            get: {
                guard case .email(let email) = draft else { return "" }
                return email[keyPath: keyPath]
            },
            set: { newValue in
                guard case .email(var email) = draft else { return }
                email[keyPath: keyPath] = newValue
                draft = .email(email)
            }
        )
    }
}
