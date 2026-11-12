import Foundation

/// Overlap before save. The function does not read SwiftData or the device time zone.
/// Pass `ShiftOverlap.tokyo`. Intervals are half-open minute instants `[start, end)`.
/// Touching endpoints do not overlap. A gap equal to the travel setting is clear.
/// Time overlap is kept even when the workplaces match. A short gap is kept only
/// when the workplaces differ. One other shift is never both.
enum ShiftOverlap {
    enum Kind: Equatable, Sendable {
        case time
        case travel(minutes: Int)
    }

    struct Span: Equatable, Sendable {
        var id: String
        var workplace: UUID
        var name: String
        var start: Date
        var end: Date
        var cancelled: Bool = false
        var startMinutes: Int
        var endMinutes: Int
    }

    struct Hit: Equatable, Identifiable, Sendable {
        var otherID: String
        var kind: Kind
        var name: String
        var start: Date
        var startMinutes: Int
        var endMinutes: Int

        var id: String {
            switch kind {
            case .time:
                return otherID + ":time"
            case .travel(let minutes):
                return otherID + ":travel:\(minutes)"
            }
        }
    }

    static var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    /// Drops seconds so the comparison is whole minutes in `calendar`.
    static func aligned(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// `start == end` is an empty interval. An earlier end is the next day.
    static func span(
        id: String,
        name: String,
        workplace: UUID,
        day: Date,
        start: Int,
        end: Int,
        calendar: Calendar,
        cancelled: Bool = false
    ) -> Span {
        let startMinutes = ShiftDatePolicy.clockMinutes(start)
        let endMinutes = ShiftDatePolicy.clockMinutes(end)
        let base = calendar.startOfDay(for: day)
        let startDate = calendar.date(byAdding: .minute, value: startMinutes, to: base) ?? base
        var endDate = calendar.date(byAdding: .minute, value: endMinutes, to: base) ?? startDate
        if endMinutes < startMinutes {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return Span(
            id: id,
            workplace: workplace,
            name: name,
            start: aligned(startDate, calendar: calendar),
            end: aligned(endDate, calendar: calendar),
            cancelled: cancelled,
            startMinutes: startMinutes,
            endMinutes: endMinutes
        )
    }

    static func conflicts(
        of proposed: Span,
        among others: [Span],
        travelMinutes: Int,
        calendar: Calendar
    ) -> [Hit] {
        let proposed = aligned(proposed, calendar: calendar)
        let travel = max(0, travelMinutes)
        let windowStart = proposed.start.addingTimeInterval(TimeInterval(-travel * 60))
        let windowEnd = proposed.end.addingTimeInterval(TimeInterval(travel * 60))
        return others
            .map { aligned($0, calendar: calendar) }
            .filter { other in
                other.id != proposed.id && !other.cancelled && intersects(windowStart, windowEnd, other.start, other.end)
            }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.id < rhs.id
            }
            .compactMap { other in
                guard let kind = kind(proposed, other, travelMinutes: travel) else { return nil }
                return Hit(
                    otherID: other.id,
                    kind: kind,
                    name: other.name,
                    start: other.start,
                    startMinutes: other.startMinutes,
                    endMinutes: other.endMinutes
                )
            }
    }

    /// New shifts are compared with saved shifts and with each other.
    /// A pair is reported once.
    static func conflicts(
        batch: [Span],
        existing: [Span],
        travelMinutes: Int,
        calendar: Calendar
    ) -> [Hit] {
        var seen = Set<String>()
        var found: [Hit] = []
        for (index, proposed) in batch.enumerated() {
            let peers = batch.enumerated().filter { $0.offset != index }.map(\.element)
            let hits = conflicts(of: proposed, among: existing + peers, travelMinutes: travelMinutes, calendar: calendar)
            for hit in hits {
                let key = pairKey(proposed.id, hit.otherID, hit.kind)
                if seen.contains(key) { continue }
                seen.insert(key)
                found.append(hit)
            }
        }
        return found.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.otherID < rhs.otherID
        }
    }

    static func usesSheet(_ hits: [Hit]) -> Bool {
        hits.count >= 2 || Set(hits.map(kindKey)).count > 1
    }

    static func row(_ hit: Hit) -> String {
        let clocks = "\(Formatters.clock(hit.startMinutes))〜\(Formatters.clock(hit.endMinutes))"
        switch hit.kind {
        case .time:
            return "\(hit.name)（\(clocks)）と時間がかぶります。"
        case .travel(let minutes):
            return "\(hit.name)（\(clocks)）との間が\(minutes)分です。移動にかかる時間より短くなります。"
        }
    }

    static func confirmMessage(_ hits: [Hit]) -> String {
        hits.map(row).joined(separator: "\n") + "\n「編集に戻る」を選ぶと、保存せずに時間を直せます。"
    }

    /// Minutes shown in 「分しかありません」. The comparison itself uses seconds.
    static func shownTravelMinutes(_ gap: TimeInterval) -> Int {
        Int((gap / 60).rounded(.towardZero))
    }

    /// The next few days a repeating template can compare before it is saved.
    static func upcoming(weekdays: Set<Int>, from: Date, calendar: Calendar = tokyo) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: from)
        for _ in 0..<14 {
            if weekdays.contains(calendar.component(.weekday, from: day)) {
                days.append(day)
            }
            if days.count == 7 { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private static func aligned(_ span: Span, calendar: Calendar) -> Span {
        var copy = span
        copy.start = aligned(span.start, calendar: calendar)
        copy.end = aligned(span.end, calendar: calendar)
        return copy
    }

    private static func intersects(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Bool {
        guard start < end, otherStart < otherEnd else { return false }
        return start < otherEnd && otherStart < end
    }

    private static func kind(_ proposed: Span, _ other: Span, travelMinutes: Int) -> Kind? {
        if intersects(proposed.start, proposed.end, other.start, other.end) {
            return .time
        }
        guard proposed.workplace != other.workplace, travelMinutes > 0 else { return nil }
        let gap = separation(proposed, other)
        guard gap < TimeInterval(travelMinutes * 60) else { return nil }
        return .travel(minutes: max(0, shownTravelMinutes(gap)))
    }

    private static func separation(_ a: Span, _ b: Span) -> TimeInterval {
        if a.end <= b.start { return b.start.timeIntervalSince(a.end) }
        if b.end <= a.start { return a.start.timeIntervalSince(b.end) }
        return 0
    }

    private static func kindKey(_ hit: Hit) -> String {
        switch hit.kind {
        case .time: return "time"
        case .travel: return "travel"
        }
    }

    private static func pairKey(_ a: String, _ b: String, _ kind: Kind) -> String {
        let pair = [a, b].sorted().joined(separator: "|")
        return pair + "|" + kindKey(Hit(otherID: "", kind: kind, name: "", start: .distantPast, startMinutes: 0, endMinutes: 0))
    }
}
