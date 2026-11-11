import Foundation

/// One typed shift sentence, read by rules. Foundation Models is not called.
/// An incomplete reading stays incomplete. Image import stays in `ShiftExtraction`.
enum TypedShiftEntry {
    struct Reading: Equatable {
        var year: Int
        var month: Int
        var day: Int
        var startMinutes: Int
        var endMinutes: Int
        var breakMinutes: Int
        var breakWasWritten: Bool
        var workplaceText: String
        var weekdays: [Int]
        var repeatsWeekly: Bool
        var alternativeNoted: Bool
        var canSave: Bool

        func draft() -> ShiftTextParser.Draft? {
            guard canSave else { return nil }
            return ShiftTextParser.Draft(
                workplaceName: workplaceText,
                year: year,
                month: month,
                day: day,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                breakMinutes: breakMinutes,
                breakIsExplicit: breakWasWritten
            )
        }
    }

    static func read(
        text: String,
        now: Date,
        calendar: Calendar,
        knownNames: [String] = [],
        fallbackDate: Date? = nil,
        defaultWorkplace: String = ""
    ) -> Reading? {
        let calendar = gregorian(calendar)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(where: \.isNewline) { return nil }
        if trimmed.contains("来週") || trimmed.contains("朝") || trimmed.contains("夕方") { return nil }

        var body = ascii(trimmed).replacingOccurrences(of: "曜日", with: "")
        let writtenBreak = firstInt(#"休憩\s*(\d+)\s*分?"#, in: body)
        body = replacing(#"休憩\s*\d+\s*分?"#, in: body, with: " ")
        guard let time = timeRange(in: body) else { return nil }
        body = (body as NSString).replacingCharacters(in: time.span, with: " ")

        let weekly = weeklyDays(in: body)
        if !weekly.days.isEmpty {
            body = body.replacingOccurrences(of: "毎週", with: " ")
            if let range = body.range(of: weekly.marks) {
                body.removeSubrange(range)
            }
        }
        let singleDay = weekly.days.isEmpty ? singleWeekday(in: body) : nil
        if let singleDay {
            body = body.replacingOccurrences(of: singleDay.mark, with: " ")
        }

        let resolved = resolveDay(
            in: body,
            now: now,
            calendar: calendar,
            weekday: singleDay?.number,
            fallback: fallbackDate
        )
        let workplace = workplaceText(
            in: body,
            knownNames: knownNames.map(ascii),
            defaultWorkplace: ascii(defaultWorkplace)
        )
        let duration = spanMinutes(start: time.start, end: time.end)
        let canSave = resolved.valid && weekly.days.isEmpty && duration > 0 && duration <= 16 * 60 && !workplace.isEmpty
        return Reading(
            year: resolved.year,
            month: resolved.month,
            day: resolved.day,
            startMinutes: time.start,
            endMinutes: time.end,
            breakMinutes: min(8 * 60, max(0, writtenBreak ?? 0)),
            breakWasWritten: writtenBreak != nil,
            workplaceText: workplace,
            weekdays: weekly.days,
            repeatsWeekly: !weekly.days.isEmpty,
            alternativeNoted: time.alternative,
            canSave: canSave
        )
    }

    static func weeklyLine(_ reading: Reading) -> String {
        let names = reading.weekdays.map(weekdayName).joined(separator: "・")
        return "毎週の繰り返しは、まだシフトにしません。\(names) \(Formatters.clock(reading.startMinutes))–\(Formatters.clock(reading.endMinutes)) と読みました。保存はしません。"
    }

    static func alternativeLine() -> String {
        "短い読みを使いました。もう一方の時刻は、追加する前に確認できます。"
    }

    private struct TimeHit {
        var start: Int
        var end: Int
        var alternative: Bool
        var span: NSRange
    }

    private struct WeekHit {
        var days: [Int]
        var marks: String
    }

    private struct DayHit {
        var year: Int
        var month: Int
        var day: Int
        var valid: Bool
    }

    private static let weekdayMap = ["日": 1, "月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7]

    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var next = Calendar(identifier: .gregorian)
        next.timeZone = calendar.timeZone
        next.locale = Locale(identifier: "en_US_POSIX")
        return next
    }

    /// Full-width ASCII only. Katakana is left as written.
    private static func ascii(_ text: String) -> String {
        var result = ""
        for character in text {
            let scalars = character.unicodeScalars
            if scalars.count == 1, let value = scalars.first?.value, (0xFF01...0xFF5E).contains(value) {
                result.append(Character(UnicodeScalar(value - 0xFF01 + 0x21)!))
            } else if character == "〜" || character == "～" || character == "–" || character == "—" || character == "−" {
                result.append("-")
            } else {
                result.append(character)
            }
        }
        return result.replacingOccurrences(of: "から", with: "-")
    }

    private static func timeRange(in text: String) -> TimeHit? {
        let detailed = #"(翌)?(\d{1,2})(時半|時(\d{1,2})分?|:(\d{2}))\s*-\s*(翌)?(\d{1,2})(時半|時(\d{1,2})分?|:(\d{2}))"#
        if let match = firstMatch(detailed, in: text) {
            let ns = text as NSString
            guard let start = piece(match, next: 1, hour: 2, kind: 3, minute: 4, colon: 5, ns: ns),
                  let end = piece(match, next: 6, hour: 7, kind: 8, minute: 9, colon: 10, ns: ns),
                  let resolved = clocks(start: start, end: end, bareHours: false) else { return nil }
            return TimeHit(start: resolved.start, end: resolved.end, alternative: resolved.alternative, span: match.range)
        }
        let bare = #"(\d{1,2})\s*-\s*(\d{1,2})(?!\d)"#
        guard let match = firstMatch(bare, in: text) else { return nil }
        let ns = text as NSString
        guard let startHour = intGroup(match, 1, ns), let endHour = intGroup(match, 2, ns),
              let resolved = clocks(
                start: (hour: startHour, minute: 0, nextDay: false),
                end: (hour: endHour, minute: 0, nextDay: false),
                bareHours: true
              ) else { return nil }
        return TimeHit(start: resolved.start, end: resolved.end, alternative: resolved.alternative, span: match.range)
    }

    private static func piece(
        _ match: NSTextCheckingResult,
        next: Int,
        hour: Int,
        kind: Int,
        minute: Int,
        colon: Int,
        ns: NSString
    ) -> (hour: Int, minute: Int, nextDay: Bool)? {
        guard let hourValue = intGroup(match, hour, ns), (0...23).contains(hourValue) else { return nil }
        let kindText = rangeText(match, kind, ns)
        let minuteValue: Int
        if kindText == "時半" {
            minuteValue = 30
        } else if let written = intGroup(match, minute, ns) ?? intGroup(match, colon, ns), (0...59).contains(written) {
            minuteValue = written
        } else {
            minuteValue = 0
        }
        return (hourValue, minuteValue, match.range(at: next).location != NSNotFound)
    }

    private static func clocks(
        start: (hour: Int, minute: Int, nextDay: Bool),
        end: (hour: Int, minute: Int, nextDay: Bool),
        bareHours: Bool
    ) -> (start: Int, end: Int, alternative: Bool)? {
        guard (0...23).contains(start.hour), (0...23).contains(end.hour),
              (0...59).contains(start.minute), (0...59).contains(end.minute) else { return nil }
        let startMinutes = start.hour * 60 + start.minute
        let writtenEnd = end.hour * 60 + end.minute
        if end.nextDay {
            return (startMinutes, writtenEnd, false)
        }
        if bareHours, end.hour < start.hour, end.hour + 12 <= 23, (end.hour + 12) * 60 > startMinutes {
            let bumped = (end.hour + 12) * 60
            let short = bumped - startMinutes
            let overnight = (24 * 60 - startMinutes) + writtenEnd
            if short > 0, short <= 16 * 60, short < overnight {
                return (startMinutes, bumped, true)
            }
        }
        return (startMinutes, writtenEnd, false)
    }

    private static func spanMinutes(start: Int, end: Int) -> Int {
        if end > start { return end - start }
        if end == start { return 0 }
        return (24 * 60 - start) + end
    }

    private static func weeklyDays(in text: String) -> WeekHit {
        guard let range = text.range(of: "毎週") else { return WeekHit(days: [], marks: "") }
        var days: [Int] = []
        var marks = ""
        for character in text[range.upperBound...] {
            let token = String(character)
            if token == " " || token == "、" || token == "・" {
                if !marks.isEmpty { break }
                continue
            }
            guard let number = weekdayMap[token] else { break }
            marks.append(character)
            if !days.contains(number) { days.append(number) }
        }
        return WeekHit(days: days, marks: marks)
    }

    private static func singleWeekday(in text: String) -> (number: Int, mark: String)? {
        let tokens = text.split { $0.isWhitespace || "、・".contains($0) }.map(String.init)
        let hits = tokens.filter { $0.count == 1 && weekdayMap[$0] != nil }
        guard hits.count == 1, let number = weekdayMap[hits[0]] else { return nil }
        return (number, hits[0])
    }

    private static func resolveDay(
        in text: String,
        now: Date,
        calendar: Calendar,
        weekday: Int?,
        fallback: Date?
    ) -> DayHit {
        let today = LocalDay.from(now, calendar: calendar)
        if text.contains("明日") {
            return hit(today.adding(days: 1, calendar: calendar), valid: true)
        }
        if text.contains("今日") {
            return hit(today, valid: true)
        }
        if let numeric = numericDay(in: text, today: today, calendar: calendar) {
            return numeric
        }
        if let weekday {
            return nextWeekday(weekday, from: today, calendar: calendar)
        }
        if let fallback {
            return hit(LocalDay.from(fallback, calendar: calendar), valid: true)
        }
        return DayHit(year: today.year, month: today.month, day: today.day, valid: false)
    }

    private static func numericDay(in text: String, today: LocalDay, calendar: Calendar) -> DayHit? {
        let ns = text as NSString
        if let match = firstMatch(#"(\d{1,2})\s*/\s*(\d{1,2})|(\d{1,2})月\s*(\d{1,2})日?"#, in: text) {
            let month = intGroup(match, 1, ns) ?? intGroup(match, 3, ns)
            let day = intGroup(match, 2, ns) ?? intGroup(match, 4, ns)
            guard let month, let day else { return nil }
            return exact(year: today.year, month: month, day: day, today: today, calendar: calendar, rollYear: true)
        }
        if let match = firstMatch(#"(?<!\d)(\d{1,2})日"#, in: text), let day = intGroup(match, 1, ns) {
            var probe = exact(year: today.year, month: today.month, day: day, today: today, calendar: calendar, rollYear: false)
            if probe.valid, LocalDay(year: probe.year, month: probe.month, day: probe.day) < today {
                let nextMonth = today.month == 12 ? 1 : today.month + 1
                let year = today.month == 12 ? today.year + 1 : today.year
                probe = exact(year: year, month: nextMonth, day: day, today: today, calendar: calendar, rollYear: false)
            }
            return probe
        }
        return nil
    }

    private static func exact(
        year: Int,
        month: Int,
        day: Int,
        today: LocalDay,
        calendar: Calendar,
        rollYear: Bool
    ) -> DayHit {
        guard let checked = checkedDay(year: year, month: month, day: day, calendar: calendar) else {
            return DayHit(year: year, month: month, day: day, valid: false)
        }
        var resolved = checked
        if rollYear, resolved < today {
            guard let next = checkedDay(year: year + 1, month: month, day: day, calendar: calendar) else {
                return DayHit(year: year, month: month, day: day, valid: false)
            }
            resolved = next
        }
        guard let start = today.date(in: calendar), let target = resolved.date(in: calendar) else {
            return DayHit(year: resolved.year, month: resolved.month, day: resolved.day, valid: false)
        }
        let distance = calendar.dateComponents([.day], from: start, to: target).day ?? 999
        return DayHit(year: resolved.year, month: resolved.month, day: resolved.day, valid: abs(distance) <= 366)
    }

    private static func checkedDay(year: Int, month: Int, day: Int, calendar: Calendar) -> LocalDay? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let back = LocalDay.from(date, calendar: calendar)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return back
    }

    private static func nextWeekday(_ weekday: Int, from today: LocalDay, calendar: Calendar) -> DayHit {
        guard let start = today.date(in: calendar) else {
            return DayHit(year: today.year, month: today.month, day: today.day, valid: false)
        }
        let current = calendar.component(.weekday, from: start)
        let delta = (weekday - current + 7) % 7
        return hit(today.adding(days: delta == 0 ? 7 : delta, calendar: calendar), valid: true)
    }

    private static func hit(_ day: LocalDay, valid: Bool) -> DayHit {
        DayHit(year: day.year, month: day.month, day: day.day, valid: valid)
    }

    private static func workplaceText(in text: String, knownNames: [String], defaultWorkplace: String) -> String {
        let hits = knownNames.filter { !$0.isEmpty && text.contains($0) }
        let kept = hits.filter { short in
            !hits.contains { other in other != short && other.contains(short) }
        }
        if kept.count == 1 { return kept[0] }
        if kept.count > 1 { return "" }
        let cleaned = replacing(#"\d{1,2}\s*/\s*\d{1,2}|\d{1,2}月\s*\d{1,2}日?|(?<!\d)\d{1,2}日"#, in: text, with: " ")
            .replacingOccurrences(of: "明日", with: " ")
            .replacingOccurrences(of: "今日", with: " ")
            .replacingOccurrences(of: "毎週", with: " ")
        let words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init).filter { part in
            part.count > 1 && !part.allSatisfy(\.isNumber) && weekdayMap[part] == nil
        }
        if !words.isEmpty { return words.joined(separator: " ") }
        return defaultWorkplace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func weekdayName(_ weekday: Int) -> String {
        ["", "日", "月", "火", "水", "木", "金", "土"][weekday]
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func rangeText(_ match: NSTextCheckingResult, _ index: Int, _ ns: NSString) -> String {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return ns.substring(with: range)
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let match = firstMatch(pattern, in: text) else { return nil }
        return intGroup(match, 1, text as NSString)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, _ ns: NSString) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return Int(ns.substring(with: range))
    }
}
