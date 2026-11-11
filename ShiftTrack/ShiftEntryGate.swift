import Foundation

struct LiveSentenceFiller: ShiftSentenceFilling {
    var now: Date
    var calendar: Calendar
    var knownNames: [String]
    var fallbackDate: Date?
    var defaultWorkplace: String

    func fill(_ text: String) async -> TypedShiftEntry.Reading? {
        await SentenceAssist.fill(
            text,
            now: now,
            calendar: calendar,
            knownNames: knownNames,
            fallbackDate: fallbackDate,
            defaultWorkplace: defaultWorkplace
        )
    }
}

protocol ShiftSentenceFilling: Sendable {
    func fill(_ text: String) async -> TypedShiftEntry.Reading?
}

/// Rules run first. A model is asked only when the rules cannot save the sentence.
enum ShiftEntryGate {
    static func resolve(
        text: String,
        now: Date,
        calendar: Calendar,
        knownNames: [String] = [],
        fallbackDate: Date? = nil,
        defaultWorkplace: String = "",
        filler: (any ShiftSentenceFilling)? = nil
    ) async -> TypedShiftEntry.Reading? {
        let ruled = TypedShiftEntry.read(
            text: text,
            now: now,
            calendar: calendar,
            knownNames: knownNames,
            fallbackDate: fallbackDate,
            defaultWorkplace: defaultWorkplace
        )
        if let ruled, ruled.canSave || ruled.repeatsWeekly {
            return ruled
        }
        if let filled = await filler?.fill(text), filled.canSave {
            return filled
        }
        return ruled
    }
}

enum SentenceAssist {
    static func fill(
        _ text: String,
        now: Date,
        calendar: Calendar,
        knownNames: [String],
        fallbackDate: Date?,
        defaultWorkplace: String
    ) async -> TypedShiftEntry.Reading? {
        guard let rewritten = await modelText(text) else { return nil }
        return TypedShiftEntry.read(
            text: rewritten,
            now: now,
            calendar: calendar,
            knownNames: knownNames,
            fallbackDate: fallbackDate,
            defaultWorkplace: defaultWorkplace
        )
    }

    private static func modelText(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await SentenceModel.lines(from: text)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum SentenceModel {
    static func lines(from text: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        guard model.supportsLocale(Locale(identifier: "ja_JP")) else { return nil }
        let session = LanguageModelSession(instructions: """
        日本語のシフト文を、日付と時刻が明示された一行に整える係です。書かれていない勤務先や時刻は足さないでください。
        """)
        let response = try? await session.respond(
            to: text,
            generating: AIShiftBatch.self,
            options: GenerationOptions(sampling: .greedy)
        )
        guard let response else { return nil }
        let lines = response.content.shifts.map { item -> String in
            let breakText = item.breakMinutes > 0 ? " 休憩\(max(0, item.breakMinutes))分" : ""
            return "\(item.date) \(item.workplaceName) \(item.start)-\(item.end)\(breakText)"
        }
        let joined = lines.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
#endif
