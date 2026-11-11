import UIKit
import Vision

enum WorkplaceImageRead {
    static func read(data: Data) async -> WorkplaceDraft {
        let recognized = await lines(from: data)
        var hints = DetectedHints()
        if #available(iOS 26.0, *) {
            hints = await documentHints(data)
        }
        var draft = WorkplaceRead.draft(from: recognized.lines, detected: hints)
        if recognized.lines.isEmpty, hints.phones.isEmpty, hints.addresses.isEmpty {
            draft.mapsNotice = WorkplaceDraft.imageUnreadable
        }
        draft.imageJPEG = data
        if let pick = await WorkplaceModel.pick(lines: modelLines(recognized.lines)) {
            draft = WorkplaceRead.merge(draft, pick: pick, modelRan: true)
        }
        return draft
    }

    static func transcript(from data: Data) async -> String {
        await lines(from: data).lines.map(\.text).joined(separator: "\n")
    }

    static func transcript(from image: CGImage) async -> String {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { return "" }
        return await transcript(from: data)
    }

    private static func modelLines(_ lines: [ReadLine]) -> [ReadLine] {
        lines.filter { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if text.contains("。") || text.contains("です") || text.contains("ます") || text.contains("にあります") { return false }
            if text.count > 40 { return false }
            return true
        }
        .prefix(80)
        .map { $0 }
    }

    private static func lines(from data: Data) async -> (lines: [ReadLine], transcript: String) {
        let fallback = (try? await ShiftImageReader.recognizeLines(in: data)) ?? []
        return (fallback, fallback.map(\.text).joined(separator: "\n"))
    }

    @available(iOS 26.0, *)
    private static func documentHints(_ data: Data) async -> DetectedHints {
        let request = RecognizeDocumentsRequest()
        guard let document = try? await request.perform(on: data, orientation: .up).first?.document else {
            return DetectedHints()
        }
        return DocumentHints.read(document)
    }
}

#if canImport(DataDetection)
import DataDetection

@available(iOS 26.0, *)
enum DocumentHints {
    static func read(_ document: DocumentObservation.Container) -> DetectedHints {
        var hints = DetectedHints()
        for item in document.text.detectedData {
            switch item.match.details {
            case .phoneNumber(let phone):
                hints.phones.append(phone.phoneNumber)
            case .postalAddress(let address):
                hints.addresses.append(address.fullAddress)
            case .link(let link):
                hints.urls.append(link.url.absoluteString)
            default:
                break
            }
        }
        return hints
    }
}
#else
@available(iOS 26.0, *)
enum DocumentHints {
    static func read(_ document: DocumentObservation.Container) -> DetectedHints {
        DetectedHints()
    }
}
#endif
