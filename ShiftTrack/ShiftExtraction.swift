import Foundation
import SwiftData
import UIKit
import Vision

enum ExtractionSource: String, Codable {
    case appleIntelligence
    case pattern
}

struct ImportCandidate: Identifiable, Codable, Hashable {
    var id: UUID
    var workplaceName: String
    var workplaceID: UUID?
    var createWorkplace: Bool
    var date: Date
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var included: Bool
    var breakFollowsRules: Bool

    init(
        id: UUID,
        workplaceName: String,
        workplaceID: UUID?,
        createWorkplace: Bool,
        date: Date,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int,
        included: Bool,
        breakFollowsRules: Bool = false
    ) {
        self.id = id
        self.workplaceName = workplaceName
        self.workplaceID = workplaceID
        self.createWorkplace = createWorkplace
        self.date = date
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.breakMinutes = breakMinutes
        self.included = included
        self.breakFollowsRules = breakFollowsRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workplaceName = try container.decode(String.self, forKey: .workplaceName)
        workplaceID = try container.decodeIfPresent(UUID.self, forKey: .workplaceID)
        createWorkplace = try container.decode(Bool.self, forKey: .createWorkplace)
        date = try container.decode(Date.self, forKey: .date)
        startMinutes = try container.decode(Int.self, forKey: .startMinutes)
        endMinutes = try container.decode(Int.self, forKey: .endMinutes)
        breakMinutes = try container.decode(Int.self, forKey: .breakMinutes)
        included = try container.decode(Bool.self, forKey: .included)
        breakFollowsRules = try container.decodeIfPresent(Bool.self, forKey: .breakFollowsRules) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workplaceName, forKey: .workplaceName)
        try container.encodeIfPresent(workplaceID, forKey: .workplaceID)
        try container.encode(createWorkplace, forKey: .createWorkplace)
        try container.encode(date, forKey: .date)
        try container.encode(startMinutes, forKey: .startMinutes)
        try container.encode(endMinutes, forKey: .endMinutes)
        try container.encode(breakMinutes, forKey: .breakMinutes)
        try container.encode(included, forKey: .included)
        try container.encode(breakFollowsRules, forKey: .breakFollowsRules)
    }

    private enum CodingKeys: String, CodingKey {
        case id, workplaceName, workplaceID, createWorkplace, date
        case startMinutes, endMinutes, breakMinutes, included, breakFollowsRules
    }
}

struct PendingImport: Codable, Hashable {
    var message: String
    var usedAppleIntelligence: Bool
    var candidates: [ImportCandidate]
}

enum PendingImportStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ShiftTrack", isDirectory: true)
            .appendingPathComponent("pending-import.json")
    }

    static func save(_ pending: PendingImport) {
        let url = fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pending)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    static func load() -> PendingImport? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PendingImport.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func modifiedAt() -> Date? {
        let values = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return values?[.modificationDate] as? Date
    }
}

struct ImportFocus: Equatable {
    var id = UUID()
    var dates: [Date]
}

@MainActor
@Observable
final class ImportRouter {
    static let shared = ImportRouter()
    var isPresented = false
    var startInReview = false
    var pending: PendingImport?
    var stagedCount = 0
    var fallbackDate: Date?
    var defaultWorkplace = ""
    var focusRequest: ImportFocus?
    private var handledStamp: Date?

    func presentChooser(fallbackDate: Date? = nil, defaultWorkplace: String = "") {
        self.fallbackDate = fallbackDate
        self.defaultWorkplace = defaultWorkplace
        startInReview = false
        pending = nil
        isPresented = true
    }

    func showSaved(dates: [Date]) {
        let days = dates.map { Calendar.current.startOfDay(for: $0) }
        guard !days.isEmpty else { return }
        focusRequest = ImportFocus(dates: days)
    }

    func presentReview(_ pending: PendingImport) {
        self.pending = pending
        startInReview = true
        noteHandled()
        isPresented = true
    }

    func considerPending() {
        refreshCount()
        guard !isPresented else { return }
        guard let stamp = PendingImportStore.modifiedAt(), stamp != handledStamp else { return }
        guard let pending = PendingImportStore.load() else { return }
        handledStamp = stamp
        self.pending = pending
        startInReview = true
        isPresented = true
    }

    func noteHandled() {
        handledStamp = PendingImportStore.modifiedAt()
        refreshCount()
    }

    func discard() {
        PendingImportStore.clear()
        pending = nil
        stagedCount = 0
        handledStamp = nil
        isPresented = false
    }

    func refreshCount() {
        stagedCount = PendingImportStore.load()?.candidates.count ?? 0
    }
}

@MainActor
enum WorkplaceLookup {
    static func names() -> [String] {
        let rows = (try? AppModel.container.mainContext.fetch(FetchDescriptor<Workplace>())) ?? []
        return rows.map(\.name)
    }
}

enum IntelligenceAvailability {
    static var statusText: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "対応端末では Apple Intelligence が、読み取った文字を端末内でシフトに整理します。画像も文字もサーバーには送りません。"
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return "Apple Intelligence がオフです。日付と時刻のパターンから候補を作ります。設定でオンにすると、端末内のモデルで整理できます。通信は使いません。"
                case .deviceNotEligible:
                    return "この端末は Apple Intelligence に対応していません。日付と時刻のパターンから候補を作ります。通信は使いません。"
                case .modelNotReady:
                    return "Apple Intelligence のモデルを準備中です。いまは日付と時刻のパターンから候補を作ります。通信は使いません。"
                @unknown default:
                    return "Apple Intelligence が使えないため、日付と時刻のパターンから候補を作ります。通信は使いません。"
                }
            }
        }
        #endif
        return "この環境では日付と時刻のパターンから候補を作ります。画像の文字認識も端末内で行い、通信は使いません。"
    }
}

@MainActor
enum ShiftImageReader {
    static func recognizeText(in data: Data) throws -> String {
        let prepared = resized(data) ?? data
        guard let image = UIImage(data: prepared), let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        return observations
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func resized(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return data }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

enum ShiftExtractionService {
    static func extract(
        imageData: Data,
        knownNames: [String],
        fallbackDate: Date? = nil,
        defaultWorkplace: String = ""
    ) async -> PendingImport {
        let text: String
        do {
            text = try await ShiftImageReader.recognizeText(in: imageData)
        } catch {
            return PendingImport(
                message: "画像の文字を読み取れませんでした。テキストを貼り付けてください。通信は使っていません。",
                usedAppleIntelligence: false,
                candidates: []
            )
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PendingImport(
                message: "画像から文字を見つけられませんでした。明るい写真でもう一度試すか、テキストを貼り付けてください。",
                usedAppleIntelligence: false,
                candidates: []
            )
        }
        return await extract(
            text: text,
            knownNames: knownNames,
            fromImage: true,
            fallbackDate: fallbackDate,
            defaultWorkplace: defaultWorkplace
        )
    }

    static func extract(
        text: String,
        knownNames: [String],
        fromImage: Bool,
        fallbackDate: Date? = nil,
        defaultWorkplace: String = ""
    ) async -> PendingImport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PendingImport(
                message: "テキストが空です。シフト表を貼り付けるか、画像を選んでください。",
                usedAppleIntelligence: false,
                candidates: []
            )
        }

        var modelFailed = false
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let structured = try await AppleIntelligenceExtractor.structure(
                    text: String(trimmed.prefix(6000)),
                    knownNames: knownNames
                )
                if !structured.isEmpty {
                    return makePending(drafts: structured, fromImage: fromImage, usedModel: true, modelFailed: false)
                }
            } catch {
                modelFailed = true
            }
        }
        #endif

        let drafts = ShiftTextParser.parse(
            text: trimmed,
            knownNames: knownNames,
            fallbackDate: fallbackDate,
            defaultWorkplace: defaultWorkplace
        )
        return makePending(drafts: drafts, fromImage: fromImage, usedModel: false, modelFailed: modelFailed)
    }

    private static func makePending(
        drafts: [ShiftTextParser.Draft],
        fromImage: Bool,
        usedModel: Bool,
        modelFailed: Bool
    ) -> PendingImport {
        var message = fromImage ? "画像の文字を端末内で読み取りました。" : ""
        if usedModel {
            message += "Apple Intelligence（端末内）でシフトに整理しました。サーバーには送っていません。"
        } else if modelFailed {
            message += "モデルで整理できなかったため、日付と時刻のパターンから候補を作りました。通信は使っていません。"
        } else {
            message += "日付と時刻のパターンから候補を作りました。通信は使っていません。"
        }
        if drafts.isEmpty {
            message += " シフトを見つけられませんでした。勤務先・日付・開始と終了が分かる形にしてください。例: 11/8 カフェA 10:00-15:00"
        } else {
            message += " 保存前に内容を確認してください。"
        }
        let candidates = drafts.compactMap { draft -> ImportCandidate? in
            guard let date = draft.date() else { return nil }
            let decision = BreakRules.textDecision(
                breakIsExplicit: draft.breakIsExplicit,
                explicitMinutes: draft.breakMinutes,
                payIsDaily: false,
                customBreaks: false,
                rules: [],
                start: draft.startMinutes,
                end: draft.endMinutes
            )
            return ImportCandidate(
                id: draft.id,
                workplaceName: draft.workplaceName,
                workplaceID: nil,
                createWorkplace: true,
                date: date,
                startMinutes: draft.startMinutes,
                endMinutes: draft.endMinutes,
                breakMinutes: decision.minutes,
                included: true,
                breakFollowsRules: decision.followsRules
            )
        }
        return PendingImport(message: message, usedAppleIntelligence: usedModel, candidates: candidates)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct AIShiftCandidate {
    @Guide(description: "勤務先の名前。表に書かれている店名や職場名")
    var workplaceName: String

    @Guide(description: "日付。yyyy-MM-dd")
    var date: String

    @Guide(description: "開始時刻。24時間表記のHH:mm")
    var start: String

    @Guide(description: "終了時刻。24時間表記のHH:mm")
    var end: String

    @Guide(description: "休憩の分数。不明なら0")
    var breakMinutes: Int
}

@available(iOS 26.0, *)
@Generable
struct AIShiftBatch {
    @Guide(description: "入力に実在するシフトだけ。最大40件。無ければ空")
    var shifts: [AIShiftCandidate]
}

@available(iOS 26.0, *)
enum AppleIntelligenceExtractor {
    static func structure(text: String, knownNames: [String]) async throws -> [ShiftTextParser.Draft] {
        let session = LanguageModelSession(instructions: """
        シフト表から勤務を抜き出す係です。書かれている勤務だけを返します。存在しないシフトは作らないでください。日付はyyyy-MM-dd、時刻は24時間のHH:mmです。
        """)
        let today = Formatters.longDay(.now)
        let names = knownNames.isEmpty ? "なし" : knownNames.joined(separator: "、")
        let prompt = """
        今日は\(today)です。年が書かれていない日付はこの年にしてください。
        既知の勤務先: \(names)
        次の文字からシフトを抽出してください。

        \(text)
        """
        let response = try await session.respond(to: prompt, generating: AIShiftBatch.self)
        let lines = response.content.shifts.map { item -> String in
            let breakText = item.breakMinutes > 0 ? " 休憩 \(max(0, item.breakMinutes))分" : ""
            return "\(item.date) \(item.workplaceName) \(item.start)-\(item.end)\(breakText)"
        }.joined(separator: "\n")
        let namesForMatch = knownNames + response.content.shifts.map(\.workplaceName)
        return ShiftTextParser.parse(text: lines, knownNames: namesForMatch)
    }
}
#endif
