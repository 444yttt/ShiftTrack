import Foundation
import SwiftData

/// Deposit timing chosen in this app. This is not a recovered IN/OUT function.
/// `month` calls the existing payday. `week` and `day` are used only after a person picks them.
enum PayCycle: String, CaseIterable, Identifiable {
    case month
    case week
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "月払い"
        case .week: "週払い"
        case .day: "日払い"
        }
    }
}

enum PaySchedule {
    /// The date used to place a shift in a salary month.
    /// A workplace left on month pay returns the same day as `PayMath.payday`.
    static func payday(for shiftDay: Date, workplace: Workplace, calendar: Calendar = .current) -> Date {
        switch workplace.payCycle {
        case .day:
            return calendar.startOfDay(for: shiftDay)
        case .week:
            guard (1...7).contains(workplace.payWeekday) else {
                return PayMath.payday(for: shiftDay, workplace: workplace, calendar: calendar)
            }
            let start = calendar.startOfDay(for: shiftDay)
            let current = calendar.component(.weekday, from: start)
            let delta = (workplace.payWeekday - current + 7) % 7
            return calendar.date(byAdding: .day, value: delta, to: start) ?? start
        case .month:
            return PayMath.payday(for: shiftDay, workplace: workplace, calendar: calendar)
        }
    }

    /// Calendar mark. Daily pay marks a day only when that workplace already has a shift there.
    static func showsMark(on day: Date, workplace: Workplace, hasShiftThatDay: Bool, calendar: Calendar = .current) -> Bool {
        switch workplace.payCycle {
        case .month:
            return calendar.isDate(PayMath.payday(in: day, workplace: workplace, calendar: calendar), inSameDayAs: day)
        case .week:
            guard (1...7).contains(workplace.payWeekday) else {
                return calendar.isDate(PayMath.payday(in: day, workplace: workplace, calendar: calendar), inSameDayAs: day)
            }
            return calendar.component(.weekday, from: calendar.startOfDay(for: day)) == workplace.payWeekday
        case .day:
            return hasShiftThatDay
        }
    }
}

extension Workplace {
    var payCycle: PayCycle {
        get { PayCycle(rawValue: payCycleRaw) ?? .month }
        set { payCycleRaw = newValue.rawValue }
    }
}

enum ShiftRequestStatus {
    static let open = "open"
    static let accepted = "accepted"
    static let declined = "declined"
}

/// A reusable clock and weekday set. Applying it creates shifts. Saving it does not.
@Model
final class ShiftPattern {
    var uuid: UUID
    var name: String
    var workplaceUUID: UUID
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    /// Calendar weekdays 1...7, Sunday first, comma separated.
    var weekdaysRaw: String
    var createdAt: Date

    init(
        name: String,
        workplaceUUID: UUID,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int,
        weekdays: Set<Int>,
        createdAt: Date = .now
    ) {
        self.uuid = UUID()
        self.name = name
        self.workplaceUUID = workplaceUUID
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.breakMinutes = breakMinutes
        self.weekdaysRaw = ShiftPatternPlan.encodeWeekdays(weekdays)
        self.createdAt = createdAt
    }

    var weekdays: Set<Int> {
        get { ShiftPatternPlan.decodeWeekdays(weekdaysRaw) }
        set { weekdaysRaw = ShiftPatternPlan.encodeWeekdays(newValue) }
    }
}

/// Recovered `ShiftPart` (`0x10044075c`). Stored like `AppData.shiftParts`.
/// `breakMinutes` is kept on the part and is not copied by the place path.
/// Weekday repetition stays on `ShiftPattern` and is not this record.
@Model
final class ShiftPart {
    var uuid: UUID
    var name: String
    var workplaceUUID: UUID
    var startMinute: Int
    var endMinute: Int
    var breakMinutes: Int
    var defaultTodosRaw: String
    var hidden: Bool
    var colorHex: String
    var createdAt: Date

    init(
        name: String,
        workplaceUUID: UUID,
        startMinute: Int,
        endMinute: Int,
        breakMinutes: Int = 0,
        defaultTodosRaw: String = "",
        hidden: Bool = false,
        colorHex: String = "C8FF00",
        createdAt: Date = .now
    ) {
        self.uuid = UUID()
        self.name = name
        self.workplaceUUID = workplaceUUID
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.breakMinutes = breakMinutes
        self.defaultTodosRaw = defaultTodosRaw
        self.hidden = hidden
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    var defaultTodos: [ShiftTodoCodec.Item] {
        get { ShiftTodoCodec.decode(defaultTodosRaw) }
        set { defaultTodosRaw = ShiftTodoCodec.encode(newValue) }
    }
}

/// A hoped-for shift. It is not a `WorkShift` and is not passed to pay or the today card.
@Model
final class ShiftRequest {
    var uuid: UUID
    var date: Date
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var note: String
    var workplaceUUID: UUID?
    var statusRaw: String
    var createdAt: Date

    init(
        date: Date,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int,
        note: String = "",
        workplaceUUID: UUID? = nil,
        statusRaw: String = ShiftRequestStatus.open,
        createdAt: Date = .now
    ) {
        self.uuid = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.breakMinutes = breakMinutes
        self.note = note
        self.workplaceUUID = workplaceUUID
        self.statusRaw = statusRaw
        self.createdAt = createdAt
    }

    var isOpen: Bool { statusRaw == ShiftRequestStatus.open }
}

/// Weekday repetition. Independent of the recovered week-offset multiply-by-seven.
enum ShiftPatternPlan {
    static let maximumSpanDays = 366

    struct Occupied: Equatable {
        var day: Date
        var workplaceID: UUID
    }

    struct Proposal: Equatable {
        var day: Date
        var workplaceID: UUID
        var startMinutes: Int
        var endMinutes: Int
        var breakMinutes: Int
    }

    struct Result: Equatable {
        var create: [Proposal]
        var skippedExisting: Int
        /// True when the clock is equal and this workplace is not daily pay, so nothing is proposed.
        var blockedEqualClock: Bool
    }

    static func decodeWeekdays(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
    }

    static func encodeWeekdays(_ days: Set<Int>) -> String {
        days.filter { (1...7).contains($0) }.sorted().map(String.init).joined(separator: ",")
    }

    static func weekdayLabel(_ days: Set<Int>) -> String {
        let names = ["", "日", "月", "火", "水", "木", "金", "土"]
        let labels = days.filter { names.indices.contains($0) }.sorted().map { names[$0] }
        return labels.isEmpty ? "曜日なし" : labels.joined()
    }

    /// Inclusive day count. Nil when the end is before the start, or the span is longer than one year.
    static func spanDays(from start: Date, through end: Date, calendar: Calendar = .current) -> Int? {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard last >= first else { return nil }
        guard let between = calendar.dateComponents([.day], from: first, to: last).day, between >= 0 else { return nil }
        guard between < maximumSpanDays else { return nil }
        return between + 1
    }

    static func proposals(
        workplaceID: UUID,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int,
        from start: Date,
        through end: Date,
        weekdays: Set<Int>,
        occupied: [Occupied],
        allowEqualClock: Bool,
        calendar: Calendar = .current
    ) -> Result {
        let startClock = ShiftDatePolicy.clockMinutes(startMinutes)
        let endClock = ShiftDatePolicy.clockMinutes(endMinutes)
        let breakMinutes = min(24 * 60, max(0, breakMinutes))
        let chosen = Set(weekdays.filter { (1...7).contains($0) })
        guard allowEqualClock || startClock != endClock else {
            return Result(create: [], skippedExisting: 0, blockedEqualClock: true)
        }
        guard let count = spanDays(from: start, through: end, calendar: calendar), !chosen.isEmpty else {
            return Result(create: [], skippedExisting: 0, blockedEqualClock: false)
        }
        let origin = calendar.startOfDay(for: start)
        var create: [Proposal] = []
        var skipped = 0
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: origin) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard chosen.contains(weekday) else { continue }
            let taken = occupied.contains { item in
                item.workplaceID == workplaceID && calendar.isDate(item.day, inSameDayAs: day)
            }
            if taken {
                skipped += 1
                continue
            }
            create.append(Proposal(
                day: day,
                workplaceID: workplaceID,
                startMinutes: startClock,
                endMinutes: endClock,
                breakMinutes: breakMinutes
            ))
        }
        return Result(create: create, skippedExisting: skipped, blockedEqualClock: false)
    }
}
