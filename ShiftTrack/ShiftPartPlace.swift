import Foundation
import SwiftData

/// Todos copied by `0x1001c75ec`. The place path writes a new id and `done = 0`.
/// Other fields were not named. The title is what the person typed on the part.
enum ShiftTodoCodec {
    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var done: Bool
    }

    static func encode(_ items: [Item]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ raw: String) -> [Item] {
        guard let data = raw.data(using: .utf8), !raw.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }
}

/// Place a `ShiftPart` on chosen days.
///
/// Nothing is inserted while any chosen day clashes with a different shift.
/// A clash is the same rule used before saving a shift: overlapping hours,
/// another shift at this workplace on that calendar day, or a gap shorter
/// than the travel setting. A day that already has this pattern skips that
/// pattern and still checks the other shifts. Seconds are 0, and the end
/// rolls to the next day when the start minute is at or after the end
/// minute. The pattern's to-dos are copied as new, not done.
///
/// Break: each pattern carries its own (fixed minutes, the workplace's rules,
/// or rules of its own); `ShiftPartCommit` resolves it with `PatternBreak`
/// and hands it to `outcome`. Callers that pass nothing get 0 minutes.
enum ShiftPartPlace {

    /// Line shown after a tap on a pattern.
    static func placedNote(count: Int) -> String {
        count == 0
            ? "0件置きました。同じパターンが入っている日には足しません。"
            : "\(count)件置きました。"
    }
    static let saveFailedText = "保存できませんでした。少し待ってから、もう一度試してください。"

    struct Existing: Equatable {
        var id: String = UUID().uuidString
        var day: Date
        var partID: UUID?
        var workplaceID: UUID?
        var name: String = ""
        var startMinutes: Int = 0
        var endMinutes: Int = 0
    }

    struct Draft: Equatable {
        var day: Date
        var workplaceID: UUID
        var partID: UUID
        var startMinutes: Int
        var endMinutes: Int
        var breakMinutes: Int
        var breakFollowsRules: Bool
        var endAddsOneDay: Bool
        var startDate: Date
        var endDate: Date
        var todos: [ShiftTodoCodec.Item]
    }

    struct Pending: Equatable, Identifiable {
        var id: UUID
        var partID: UUID
        var days: [Date]
        var clashes: [String]
    }

    enum Outcome: Equatable {
        case placed([Draft])
        case pending(Pending)
        case missingWorkplace
    }

    struct ResolvedClock: Equatable {
        var hour: Int
        var minute: Int
        var minutes: Int
        var date: Date
    }

    static func clock(_ minute: Int) -> (hour: Int, minute: Int, minutes: Int) {
        let parts = InOutRecovered.clockFromPatternMinute(minute)
        return (parts.hour, parts.minute, parts.hour * 60 + parts.minute)
    }

    static func resolvedDates(
        day: Date,
        startMinute: Int,
        endMinute: Int,
        calendar: Calendar
    ) -> (start: ResolvedClock, end: ResolvedClock, endAddsOneDay: Bool)? {
        let startClock = clock(startMinute)
        let endClock = clock(endMinute)
        let startDay = calendar.startOfDay(for: day)
        guard let startDate = setting(
            hour: startClock.hour,
            minute: startClock.minute,
            on: startDay,
            calendar: calendar
        ) else { return nil }
        let adds = InOutRecovered.patternEndAddsOneDay(startMinute: startMinute, endMinute: endMinute)
        let endDay = adds
            ? (InOutRecovered.addingDays(1, to: startDay, calendar: calendar) ?? startDay)
            : startDay
        guard let endDate = setting(
            hour: endClock.hour,
            minute: endClock.minute,
            on: endDay,
            calendar: calendar
        ) else { return nil }
        return (
            ResolvedClock(hour: startClock.hour, minute: startClock.minute, minutes: startClock.minutes, date: startDate),
            ResolvedClock(hour: endClock.hour, minute: endClock.minute, minutes: endClock.minutes, date: endDate),
            adds
        )
    }

    static func outcome(
        partID: UUID,
        workplaceID: UUID?,
        startMinute: Int,
        endMinute: Int,
        todos: [ShiftTodoCodec.Item],
        days: [Date],
        existing: [Existing],
        breakMinutes: Int = 0,
        breakFollowsRules: Bool = false,
        travelMinutes: Int = 0,
        calendar: Calendar = .current
    ) -> Outcome {
        let days = uniqueDays(days, calendar: calendar)
        let clashes = workplaceID.map { place in
            clashLines(
                partID: partID,
                workplaceID: place,
                startMinute: startMinute,
                endMinute: endMinute,
                days: days,
                existing: existing,
                travelMinutes: travelMinutes,
                calendar: calendar
            )
        } ?? []
        if !clashes.isEmpty {
            return .pending(Pending(id: UUID(), partID: partID, days: days, clashes: clashes))
        }
        guard let workplaceID else { return .missingWorkplace }
        var drafts: [Draft] = []
        for day in days {
            if existing.contains(where: { calendar.isDate($0.day, inSameDayAs: day) && $0.partID == partID }) {
                continue
            }
            guard let resolved = resolvedDates(
                day: day,
                startMinute: startMinute,
                endMinute: endMinute,
                calendar: calendar
            ) else { continue }
            drafts.append(Draft(
                day: calendar.startOfDay(for: day),
                workplaceID: workplaceID,
                partID: partID,
                startMinutes: resolved.start.minutes,
                endMinutes: resolved.end.minutes,
                breakMinutes: breakMinutes,
                breakFollowsRules: breakFollowsRules,
                endAddsOneDay: resolved.endAddsOneDay,
                startDate: resolved.start.date,
                endDate: resolved.end.date,
                todos: todos.map { ShiftTodoCodec.Item(id: UUID(), title: $0.title, done: false) }
            ))
        }
        return .placed(drafts)
    }

    /// One line per other shift that clashes. A shift of this same pattern is
    /// skipped, and the other shifts on that day are still compared.
    static func clashLines(
        partID: UUID,
        workplaceID: UUID,
        startMinute: Int,
        endMinute: Int,
        days: [Date],
        existing: [Existing],
        travelMinutes: Int,
        calendar: Calendar
    ) -> [String] {
        var lines: [String] = []
        for day in days {
            let others = existing.filter { row in
                calendar.isDate(row.day, inSameDayAs: day) && row.partID != partID && row.workplaceID != nil
            }
            guard !others.isEmpty else { continue }
            let proposed = ShiftOverlap.span(
                id: "part",
                name: "",
                workplace: workplaceID,
                day: day,
                start: startMinute,
                end: endMinute,
                calendar: calendar
            )
            let spans = others.map { row in
                ShiftOverlap.span(
                    id: row.id,
                    name: row.name.isEmpty ? "別のシフト" : row.name,
                    workplace: row.workplaceID ?? workplaceID,
                    day: row.day,
                    start: row.startMinutes,
                    end: row.endMinutes,
                    calendar: calendar
                )
            }
            let hits = ShiftOverlap.conflicts(
                of: proposed,
                among: spans,
                travelMinutes: travelMinutes,
                calendar: calendar
            )
            for hit in hits {
                lines.append(Formatters.longDay(day, calendar: calendar) + " " + ShiftOverlap.row(hit))
            }
        }
        return lines
    }

    static func uniqueDays(_ days: [Date], calendar: Calendar) -> [Date] {
        var seen: [Date] = []
        for day in days {
            let start = calendar.startOfDay(for: day)
            if seen.contains(where: { calendar.isDate($0, inSameDayAs: start) }) { continue }
            seen.append(start)
        }
        return seen
    }

    private static func setting(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

@MainActor
enum ShiftPartCommit {
    struct Result {
        var outcome: ShiftPartPlace.Outcome
        var failure: String?
        /// The rows this call added, so the caller can offer 「取り消す」.
        var inserted: [WorkShift] = []
    }

    /// Removes shifts a pattern tap just added.
    static func undo(_ shifts: [WorkShift], context: ModelContext) {
        for shift in shifts {
            context.delete(shift)
        }
        try? context.save()
    }

    static func apply(
        part: ShiftPart,
        days: [Date],
        shifts: [WorkShift],
        workplaces: [Workplace],
        context: ModelContext,
        calendar: Calendar = .current
    ) -> Result {
        let workplaceID = workplaces.contains(where: { $0.uuid == part.workplaceUUID }) ? part.workplaceUUID : nil
        let resolvedBreak = PatternBreak.resolve(
            modeRaw: part.breakModeRaw,
            fixedMinutes: part.breakMinutes,
            customRulesRaw: part.breakRulesRaw,
            startMinutes: ShiftPartPlace.clock(part.startMinute).minutes,
            endMinutes: ShiftPartPlace.clock(part.endMinute).minutes,
            workplace: workplaces.first(where: { $0.uuid == part.workplaceUUID })
        )
        let outcome = ShiftPartPlace.outcome(
            partID: part.uuid,
            workplaceID: workplaceID,
            startMinute: part.startMinute,
            endMinute: part.endMinute,
            todos: part.defaultTodos,
            days: days,
            existing: shifts.map { shift in
                ShiftPartPlace.Existing(
                    day: shift.date,
                    partID: shift.partID,
                    workplaceID: shift.workplace?.uuid,
                    name: shift.workplace?.name ?? "",
                    startMinutes: shift.startMinutes,
                    endMinutes: shift.endMinutes
                )
            },
            breakMinutes: resolvedBreak.minutes,
            breakFollowsRules: resolvedBreak.followsRules,
            travelMinutes: storedTravelMinutes(),
            calendar: calendar
        )
        guard case .placed(let drafts) = outcome else {
            return Result(outcome: outcome, failure: nil)
        }
        guard let workplace = workplaces.first(where: { $0.uuid == part.workplaceUUID }) else {
            return Result(outcome: .missingWorkplace, failure: nil)
        }
        var inserted: [WorkShift] = []
        for draft in drafts {
            let shift = WorkShift(
                date: draft.day,
                startMinutes: draft.startMinutes,
                endMinutes: draft.endMinutes,
                breakMinutes: draft.breakMinutes,
                breakFollowsRules: draft.breakFollowsRules,
                partID: draft.partID,
                patternEndOnNextDay: draft.endAddsOneDay,
                todosRaw: ShiftTodoCodec.encode(draft.todos),
                workplace: workplace
            )
            context.insert(shift)
            inserted.append(shift)
        }
        guard !inserted.isEmpty else {
            return Result(outcome: outcome, failure: nil)
        }
        do {
            try context.save()
        } catch {
            for shift in inserted {
                context.delete(shift)
            }
            return Result(outcome: outcome, failure: ShiftPartPlace.saveFailedText)
        }
        return Result(outcome: outcome, failure: nil, inserted: inserted)
    }

    /// The travel gap used before a shift is saved. Unset means the same 30 minutes.
    private static func storedTravelMinutes() -> Int {
        let key = "settings.travelMinutes"
        guard UserDefaults.standard.object(forKey: key) != nil else { return 30 }
        return max(0, UserDefaults.standard.integer(forKey: key))
    }
}
