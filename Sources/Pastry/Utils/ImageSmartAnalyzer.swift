import Foundation
import FoundationModels
import Vision

enum ImageAnalysisError: LocalizedError, Equatable {
    case unreadableImage
    case noText
    case noBarcode
    case descriptionUnavailable
    case emptyDescription

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            L10n["smart_action.image.error.unreadable"]
        case .noText:
            L10n["smart_action.image.error.no_text"]
        case .noBarcode:
            L10n["smart_action.image.error.no_barcode"]
        case .descriptionUnavailable:
            L10n["smart_action.image.error.description_unavailable"]
        case .emptyDescription:
            L10n["smart_action.image.error.empty_description"]
        }
    }
}
enum ImageTextRecognizer {
    static func recognizeText(at imageURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw ImageAnalysisError.unreadableImage
            }

            try Task.checkCancellation()
            return request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n") ?? ""
        }.value
    }
}

struct RecognizedBarcode: Equatable, Sendable {
    let payload: String
    let symbology: String
}

enum ImageBarcodeRecognizer {
    static func recognizeBarcodes(at imageURL: URL) async throws -> [RecognizedBarcode] {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw ImageAnalysisError.unreadableImage
            }

            try Task.checkCancellation()
            var seen = Set<String>()
            return request.results?.compactMap { observation in
                guard let payload = observation.payloadStringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !payload.isEmpty,
                    seen.insert(payload).inserted
                else { return nil }
                return RecognizedBarcode(
                    payload: payload,
                    symbology: observation.symbology.rawValue
                )
            } ?? []
        }.value
    }
}

@available(macOS 27.0, *)
final class ImageDescriptionGenerator: @unchecked Sendable {
    static let shared = ImageDescriptionGenerator()

    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        model.availability == .available && model.capabilities.contains(.vision)
    }

    func describe(imageURL: URL) async throws -> String {
        guard isAvailable else { throw ImageAnalysisError.descriptionUnavailable }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            客观描述图片中可见的主体、场景、动作和重要细节。不要猜测无法从图片确认的身份、地点或意图。直接返回简洁的中文描述。
            """
        )
        let response = try await session.respond {
            "描述这张图片。"
            Attachment(imageURL: imageURL)
        }
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ImageAnalysisError.emptyDescription }
        return text
    }
}
