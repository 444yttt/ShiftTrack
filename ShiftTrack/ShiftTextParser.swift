import Foundation

enum ShiftTextParser {
    struct Draft: Identifiable, Hashable {
        var id = UUID()
        var workplaceName: String
        var year: Int
        var month: Int
        var day: Int
        var startMinutes: Int
        var endMinutes: Int
        var breakMinutes: Int
        var breakIsExplicit: Bool = false

        func date(calendar: Calendar = .current) -> Date? {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            guard let date = calendar.date(from: comps) else { return nil }
            let back = calendar.dateComponents([.year, .month, .day], from: date)
            guard back.year == year, back.month == month, back.day == day else { return nil }
            return calendar.startOfDay(for: date)
        }
    }

    static func parse(
        text: String,
        now: Date = .now,
        knownNames: [String] = [],
        calendar: Calendar = .current,
        fallbackDate: Date? = nil,
        defaultWorkplace: String = ""
    ) -> [Draft] {
        let source = TextNormalizer.fold(text)
        let known = knownNames.map { TextNormalizer.fold($0) }.filter { !$0.isEmpty }
        var yearContext = calendar.component(.year, from: now)
        var monthContext = calendar.component(.month, from: now)
        var stickyName = ""
        var stickyDate: (Int, Int, Int)?
        var found: [Draft] = []

        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let compact = line.replacingOccurrences(of: " ", with: "")
            if let header = headerMatch(compact), firstMatch(rangePattern, in: line) == nil {
                if let year = header.year { yearContext = year }
                monthContext = header.month
                continue
            }

            let dates = findDates(in: line, year: yearContext, month: monthContext)
            let times = timeMatches(in: line)
            if let first = dates.first {
                stickyDate = (first.year, first.month, first.day)
                yearContext = first.year
                monthContext = first.month
            }
            if times.isEmpty {
                let name = cleanupName(line, spans: dates.map(\.span))
                if !name.isEmpty, !looksLikeNote(name) { stickyName = name }
                continue
            }

            var usableDates = dates.isEmpty ? (stickyDate.map { [$0] } ?? []) : dates.map { ($0.year, $0.month, $0.day) }
            if usableDates.isEmpty, let fallback = fallbackParts(fallbackDate, calendar: calendar) {
                usableDates = [fallback]
            }
            guard !usableDates.isEmpty else { continue }
            let matchedBreak = breakMatch(in: line)
            let breakMinutes = min(8 * 60, max(0, matchedBreak ?? 0))
            var name = pickName(line: line, known: known, dates: dates.map(\.span), times: times.map(\.span), sticky: stickyName)
            if looksLikeNote(name) {
                name = looksLikeNote(stickyName) ? "" : stickyName
            }
            if name.isEmpty {
                name = defaultWorkplace.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !name.isEmpty else { continue }

            for (index, time) in times.enumerated() {
                let date = usableDates[min(index, usableDates.count - 1)]
                guard (1...12).contains(date.1), (1...31).contains(date.2) else { continue }
                guard (0..<(24 * 60)).contains(time.start), (0..<(24 * 60)).contains(time.end) else { continue }
                var comps = DateComponents()
                comps.year = date.0
                comps.month = date.1
                comps.day = date.2
                guard let resolved = calendar.date(from: comps) else { continue }
                let back = calendar.dateComponents([.year, .month, .day], from: resolved)
                guard back.day == date.2 else { continue }
                found.append(Draft(
                    workplaceName: name,
                    year: date.0,
                    month: date.1,
                    day: date.2,
                    startMinutes: time.start,
                    endMinutes: time.end,
                    breakMinutes: breakMinutes,
                    breakIsExplicit: matchedBreak != nil
                ))
            }
        }

        var seen = Set<String>()
        var unique: [Draft] = []
        for draft in found {
            let key = "\(draft.workplaceName)|\(draft.year)-\(draft.month)-\(draft.day)|\(draft.startMinutes)-\(draft.endMinutes)"
            if seen.insert(key).inserted {
                unique.append(draft)
            }
        }
        return Array(unique.prefix(40))
    }

    private static func fallbackParts(_ date: Date?, calendar: Calendar) -> (Int, Int, Int)? {
        guard let date else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return (year, month, day)
    }

    private struct DateHit {
        var year: Int
        var month: Int
        var day: Int
        var span: NSRange
    }

    private struct TimeHit {
        var start: Int
        var end: Int
        var span: NSRange
    }

    private static let timePattern = #"(?:(\d{1,2}):(\d{2})|(\d{1,2})時(?:(\d{1,2})分)?)"#
    private static let rangePattern = timePattern + #"\s*-\s*"# + timePattern
    private static let fullDatePattern = #"(\d{4})[./年\-]\s*(\d{1,2})[./月\-]\s*(\d{1,2})日?"#
    private static let monthDayPattern = #"(\d{1,2})[./月\-]\s*(\d{1,2})日?"#
    private static let dayOnlyPattern = #"(?<!\d)(\d{1,2})日"#
    private static let headerPattern = #"(?:(\d{4})年)?\s*(\d{1,2})月$"#
    private static let breakPattern = #"休憩\s*(\d+)\s*分"#
    private static let weekdays = CharacterSet(charactersIn: "日月火水木金土曜祝")

    private static func headerMatch(_ compact: String) -> (year: Int?, month: Int)? {
        guard let match = firstMatch(headerPattern, in: compact) else { return nil }
        let ns = compact as NSString
        guard match.range.location == 0, match.range.length == ns.length else { return nil }
        let year = intGroup(match, 1, ns)
        guard let month = intGroup(match, 2, ns), (1...12).contains(month) else { return nil }
        return (year, month)
    }

    private static func findDates(in line: String, year: Int, month: Int) -> [DateHit] {
        let ns = line as NSString
        var spans: [NSRange] = []
        var found: [DateHit] = []
        for match in matches(fullDatePattern, in: line) {
            guard let y = intGroup(match, 1, ns), let m = intGroup(match, 2, ns), let d = intGroup(match, 3, ns) else { continue }
            spans.append(match.range)
            found.append(DateHit(year: y, month: m, day: d, span: match.range))
        }
        for match in matches(monthDayPattern, in: line) {
            if overlaps(match.range, spans) { continue }
            guard let m = intGroup(match, 1, ns), let d = intGroup(match, 2, ns), (1...12).contains(m), (1...31).contains(d) else { continue }
            spans.append(match.range)
            found.append(DateHit(year: year, month: m, day: d, span: match.range))
        }
        for match in matches(dayOnlyPattern, in: line) {
            if overlaps(match.range, spans) { continue }
            guard let d = intGroup(match, 1, ns), (1...31).contains(d) else { continue }
            spans.append(match.range)
            found.append(DateHit(year: year, month: month, day: d, span: match.range))
        }
        return found
    }

    private static func timeMatches(in line: String) -> [TimeHit] {
        let ns = line as NSString
        return matches(rangePattern, in: line).compactMap { match in
            guard let start = clock(match, base: 1, ns), let end = clock(match, base: 5, ns) else { return nil }
            return TimeHit(start: start, end: end, span: match.range)
        }
    }

    private static func breakMatch(in line: String) -> Int? {
        guard let match = firstMatch(breakPattern, in: line) else { return nil }
        return intGroup(match, 1, line as NSString)
    }

    private static func pickName(line: String, known: [String], dates: [NSRange], times: [NSRange], sticky: String) -> String {
        let hits = known.filter { line.contains($0) }
        if let best = hits.max(by: { $0.count < $1.count }) {
            return best
        }
        let cleaned = cleanupName(line, spans: dates + times)
        return cleaned.isEmpty ? sticky : cleaned
    }

    private static func cleanupName(_ line: String, spans: [NSRange]) -> String {
        var text = line
        let ranges = spans.compactMap { Range($0, in: text) }.sorted { $0.lowerBound > $1.lowerBound }
        for range in ranges {
            let count = text.distance(from: range.lowerBound, to: range.upperBound)
            text.replaceSubrange(range, with: String(repeating: " ", count: count))
        }
        let cleaned = text
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "・", with: " ")
            .replacingOccurrences(of: "、", with: " ")
            .replacingOccurrences(of: "。", with: " ")
        let parts = cleaned.split(whereSeparator: \.isWhitespace).map(String.init).filter { part in
            guard part.count > 1 else { return false }
            if part.allSatisfy(\.isNumber) { return false }
            if part.unicodeScalars.allSatisfy({ weekdays.contains($0) }) { return false }
            return true
        }
        return parts.joined(separator: " ")
    }

    private static func looksLikeNote(_ name: String) -> Bool {
        let stripped = name
            .replacingOccurrences(of: "休憩", with: "")
            .replacingOccurrences(of: "分", with: "")
            .replacingOccurrences(of: " ", with: "")
        return !name.isEmpty && (stripped.isEmpty || stripped.allSatisfy(\.isNumber))
    }

    private static func clock(_ match: NSTextCheckingResult, base: Int, _ ns: NSString) -> Int? {
        if let hour = intGroup(match, base, ns), let minute = intGroup(match, base + 1, ns) {
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        if let hour = intGroup(match, base + 2, ns) {
            let minute = intGroup(match, base + 3, ns) ?? 0
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        return nil
    }

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, _ ns: NSString) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return Int(ns.substring(with: range))
    }

    private static func overlaps(_ range: NSRange, _ spans: [NSRange]) -> Bool {
        spans.contains { span in
            let end = range.location + range.length
            let spanEnd = span.location + span.length
            return !(end <= span.location || range.location >= spanEnd)
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return expression.firstMatch(in: text, range: range)
    }
}
