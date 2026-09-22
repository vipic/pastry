import Foundation

enum MultiSmartSelectionMode: Equatable {
    case text
    case image
    case mixed
}

enum MultiSmartActionKind: String, CaseIterable, Identifiable, Sendable {
    case summarize
    case compare
    case mergeRewrite
    case extractCalendar
    case emailDraft
    case custom
    case extractAllText
    case recognizeBarcodes
    case describeImages

    var id: String { rawValue }

    var titleKey: String {
        "smart_action.multi.\(rawValue).title"
    }

    var descriptionKey: String {
        "smart_action.multi.\(rawValue).description"
    }

    var processingKey: String {
        "smart_action.multi.\(rawValue).processing"
    }

    var symbolName: String {
        switch self {
        case .summarize: "text.badge.checkmark"
        case .compare: "rectangle.on.rectangle.angled"
        case .mergeRewrite: "text.append"
        case .extractCalendar: "calendar.badge.plus"
        case .emailDraft: "envelope.badge"
        case .custom: "text.bubble"
        case .extractAllText: "text.viewfinder"
        case .recognizeBarcodes: "barcode.viewfinder"
        case .describeImages: "photo.stack"
        }
    }

    var requiresLanguageModel: Bool {
        switch self {
        case .extractAllText, .recognizeBarcodes:
            false
        case .summarize, .compare, .mergeRewrite, .extractCalendar,
             .emailDraft, .custom, .describeImages:
            true
        }
    }
}

enum MultiSmartActionSelection {
    static let maximumItemCount = 10

    static func mode(for items: [ClipboardItem]) -> MultiSmartSelectionMode? {
        guard (2 ... maximumItemCount).contains(items.count) else { return nil }
        let formats = Set(items.map(\.sourceFormat))
        let textFormats: Set<SourceFormat> = [.text, .rtf, .html]
        guard formats.isSubset(of: textFormats.union([.image])) else { return nil }
        if formats.isSubset(of: textFormats) { return .text }
        if formats == [.image] { return .image }
        return .mixed
    }

    static func actions(
        for mode: MultiSmartSelectionMode,
        supportsImageDescription: Bool
    ) -> [MultiSmartActionKind] {
        switch mode {
        case .text:
            [.summarize, .compare, .mergeRewrite, .extractCalendar, .emailDraft, .custom]
        case .image:
            supportsImageDescription
                ? [.extractAllText, .recognizeBarcodes, .describeImages]
                : [.extractAllText, .recognizeBarcodes]
        case .mixed:
            [.summarize, .extractAllText, .custom]
        }
    }
}

struct MultiSmartActionSource: Sendable {
    let id: UUID
    let capturedAt: Date
    let sourceApplication: String?
    let sourceFormat: SourceFormat
    let previewText: String
    let imageURL: URL?
    let imageFallbackText: String?

    init(item: ClipboardItem) {
        id = item.id
        capturedAt = item.timestamp
        sourceApplication = item.appName
        sourceFormat = item.sourceFormat
        previewText = item.sourceFormat == .image ? "" : item.content
        imageFallbackText = item.textAnnotation
        if item.sourceFormat == .image {
            let path = ImageCacheManager.shared.originalPath(forThumbnail: item.content)
                ?? item.content
            imageURL = URL(fileURLWithPath: path)
        } else {
            imageURL = nil
        }
    }
}

enum MultiSmartActionDraft: Sendable {
    case text(String)
    case calendarEvents([CalendarEventDraft])
    case email(EmailDraft)
}

enum MultiSmartActionError: LocalizedError {
    case noUsableContent
    case noCalendarEvents

    var errorDescription: String? {
        switch self {
        case .noUsableContent:
            L10n["smart_action.multi.error.no_content"]
        case .noCalendarEvents:
            L10n["smart_action.multi.error.no_calendar"]
        }
    }
}

final class MultiSmartActionGenerator: @unchecked Sendable {
    static let shared = MultiSmartActionGenerator()

    private let generator = LocalSmartActionGenerator.shared
    private let totalCharacterLimit = 3_200

    var availability: LocalLanguageModelAvailability {
        generator.availability
    }

    func generate(
        action: MultiSmartActionKind,
        sources: [MultiSmartActionSource],
        customInstruction: String? = nil
    ) async throws -> MultiSmartActionDraft {
        switch action {
        case .extractAllText:
            return .text(try await extractedText(from: sources))
        case .recognizeBarcodes:
            return .text(try await recognizedBarcodes(from: sources))
        case .describeImages:
            return .text(try await imageDescriptions(from: sources))
        case .extractCalendar:
            return .calendarEvents(try await calendarEvents(from: sources))
        case .emailDraft:
            let context = try await combinedContext(from: sources)
            return try await generator.generate(kind: .emailDraft, context: context, instruction: nil)
                .asMultiDraft
        case .summarize, .compare, .mergeRewrite, .custom:
            let context = try await combinedContext(from: sources)
            let prompt = try instruction(for: action, customInstruction: customInstruction)
            return try await generator.generate(kind: .customText, context: context, instruction: prompt)
                .asMultiDraft
        }
    }

    private func instruction(
        for action: MultiSmartActionKind,
        customInstruction: String?
    ) throws -> String {
        switch action {
        case .summarize:
            return "综合所有编号资料，生成一份简洁摘要；保留重要事实、日期、人物和待办，并用 [编号] 标注信息来源。"
        case .compare:
            return "比较所有编号资料的共同点、差异和明显冲突，按主题组织结果，并用 [编号] 标注来源。"
        case .mergeRewrite:
            return "将所有编号资料合并改写成一篇连贯、清晰、简洁的文本；去除重复，但不得改变事实或补充资料中没有的信息。"
        case .custom:
            guard let customInstruction,
                  !customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw SmartActionError.emptyInstruction }
            return customInstruction
        case .extractCalendar, .emailDraft, .extractAllText, .recognizeBarcodes, .describeImages:
            throw SmartActionError.emptyInstruction
        }
    }

    private func combinedContext(from sources: [MultiSmartActionSource]) async throws -> SmartActionContext {
        let sections = try await contentSections(from: sources)
        guard !sections.isEmpty else { throw MultiSmartActionError.noUsableContent }
        let share = max(160, totalCharacterLimit / sections.count)
        let text = sections.map { section in
            let body = escapedMarkup(String(section.text.prefix(share)))
            let app = section.source.sourceApplication?.trimmingCharacters(in: .whitespacesAndNewlines)
            let appAttribute = app.flatMap {
                $0.isEmpty ? nil : " source=\"\(escapedMarkup($0))\""
            } ?? ""
            return "<item index=\"\(section.index)\"\(appAttribute)>\n\(body)\n</item>"
        }.joined(separator: "\n\n")
        let reference = sections.map(\.source.capturedAt).min() ?? Date()
        return SmartActionContext(text: text, capturedAt: reference, sourceApplication: nil)
    }

    private func contentSections(
        from sources: [MultiSmartActionSource]
    ) async throws -> [(index: Int, source: MultiSmartActionSource, text: String)] {
        var sections: [(Int, MultiSmartActionSource, String)] = []
        for (offset, source) in sources.enumerated() {
            try Task.checkCancellation()
            let text: String
            if source.sourceFormat == .image {
                text = try await recognizedText(for: source)
            } else {
                let loaded = await Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.loadContentPrefix(
                        id: source.id,
                        characterLimit: self.totalCharacterLimit
                    )
                }.value
                text = (loaded ?? source.previewText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !text.isEmpty { sections.append((offset + 1, source, text)) }
        }
        return sections
    }

    private func extractedText(from sources: [MultiSmartActionSource]) async throws -> String {
        let sections = try await contentSections(from: sources)
        guard !sections.isEmpty else { throw MultiSmartActionError.noUsableContent }
        return sections.map { section in
            "[\(section.index)] \(sourceLabel(section.source))\n\(section.text)"
        }.joined(separator: "\n\n")
    }

    private func recognizedBarcodes(from sources: [MultiSmartActionSource]) async throws -> String {
        var sections: [String] = []
        for (offset, source) in sources.enumerated() {
            guard let imageURL = source.imageURL else { continue }
            try Task.checkCancellation()
            let barcodes: [RecognizedBarcode]
            do {
                barcodes = try await ImageBarcodeRecognizer.recognizeBarcodes(at: imageURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            guard !barcodes.isEmpty else { continue }
            let body = barcodes.map { "\($0.symbology): \($0.payload)" }.joined(separator: "\n")
            sections.append("[\(offset + 1)] \(sourceLabel(source))\n\(body)")
        }
        guard !sections.isEmpty else { throw ImageAnalysisError.noBarcode }
        return sections.joined(separator: "\n\n")
    }

    private func imageDescriptions(from sources: [MultiSmartActionSource]) async throws -> String {
        guard #available(macOS 27.0, *) else {
            throw ImageAnalysisError.descriptionUnavailable
        }
        var sections: [String] = []
        for (offset, source) in sources.enumerated() {
            guard let imageURL = source.imageURL else { continue }
            try Task.checkCancellation()
            let description: String
            do {
                description = try await ImageDescriptionGenerator.shared.describe(imageURL: imageURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            sections.append("[\(offset + 1)] \(sourceLabel(source))\n\(description)")
        }
        guard !sections.isEmpty else { throw ImageAnalysisError.emptyDescription }
        return sections.joined(separator: "\n\n")
    }

    private func calendarEvents(from sources: [MultiSmartActionSource]) async throws -> [CalendarEventDraft] {
        var events: [CalendarEventDraft] = []
        for source in sources where source.sourceFormat != .image {
            try Task.checkCancellation()
            let loaded = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.loadContentPrefix(id: source.id, characterLimit: 1_600)
            }.value
            let text = (loaded ?? source.previewText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let context = SmartActionContext(
                text: text,
                capturedAt: source.capturedAt,
                sourceApplication: source.sourceApplication
            )
            do {
                let draft = try await generator.generate(kind: .calendarEvent, context: context, instruction: nil)
                if case .calendarEvent(let event) = draft { events.append(event) }
            } catch SmartActionError.missingEventDate {
                continue
            } catch SmartActionError.unsupportedEventDate {
                continue
            }
        }
        guard !events.isEmpty else { throw MultiSmartActionError.noCalendarEvents }
        return events
    }

    private func recognizedText(for source: MultiSmartActionSource) async throws -> String {
        guard let imageURL = source.imageURL else { return "" }
        let recognized: String
        do {
            recognized = try await ImageTextRecognizer.recognizeText(at: imageURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            recognized = ""
        }
        if !recognized.isEmpty { return recognized }
        return source.imageFallbackText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func sourceLabel(_ source: MultiSmartActionSource) -> String {
        let app = source.sourceApplication?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !app.isEmpty { return app }
        return source.sourceFormat == .image
            ? L10n["smart_action.multi.image_source"]
            : L10n["smart_action.multi.text_source"]
    }

    private func escapedMarkup(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension SmartActionDraft {
    var asMultiDraft: MultiSmartActionDraft {
        switch self {
        case .generatedText(let draft): .text(draft.text)
        case .calendarEvent(let draft): .calendarEvents([draft])
        case .email(let draft): .email(draft)
        }
    }
}
