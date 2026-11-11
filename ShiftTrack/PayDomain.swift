import Foundation

/// Calendar day stored as `yyyymmdd`. Midnight `Date`s shift across time zones.
struct LocalDay: Equatable, Hashable, Comparable, Codable {
    var year: Int
    var month: Int
    var day: Int

    var key: Int { year * 10_000 + month * 100 + day }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.key < rhs.key }

    static func from(_ date: Date, calendar: Calendar) -> LocalDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    func adding(days: Int, calendar: Calendar) -> LocalDay {
        guard let start = date(in: calendar),
              let next = calendar.date(byAdding: .day, value: days, to: start) else { return self }
        return LocalDay.from(next, calendar: calendar)
    }
}

/// 1 yen = 600_000 units, so `wage × minutes ÷ 60 × rate` stays integral until one rounding.
struct ExactYen: Equatable {
    var units: Int64
    static let scale: Int64 = 600_000

    static func wage(yenPerHour: Int, minutes: Int, rateBasisPoints: Int) -> ExactYen {
        let value = Int64(yenPerHour) * Int64(minutes) * Int64(rateBasisPoints) * scale / 60 / 10_000
        return ExactYen(units: value)
    }

    /// Half away from zero. The only rounding in the wage step.
    func roundedYen() -> Int {
        let sign: Int64 = units < 0 ? -1 : 1
        let absolute = units.magnitude
        let scale = UInt64(Self.scale)
        let quotient = absolute / scale
        let remainder = absolute % scale
        let rounded = remainder * 2 >= scale ? quotient + 1 : quotient
        return Int(sign) * Int(rounded)
    }
}

protocol HolidayProviding {
    func isClosed(_ day: LocalDay) -> Bool
}

/// Bank counters are closed 12/31–1/3. Other holidays are injected later.
struct BankClosures: HolidayProviding {
    func isClosed(_ day: LocalDay) -> Bool {
        (day.month == 12 && day.day == 31) || (day.month == 1 && (1...3).contains(day.day))
    }
}

enum PaydayDirection: String, Equatable {
    case earlier
    case later
    case unchanged
}

struct PaydayPlan: Equatable {
    var closing: LocalDay
    var payday: LocalDay
    var direction: PaydayDirection
}

enum PayScheduleMath {
    static func lengthOfMonth(_ year: Int, _ month: Int, calendar: Calendar) -> Int {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 28 }
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 28
    }

    /// `0` and values past the month length are the last day of that month.
    static func clampedDay(_ day: Int, year: Int, month: Int, calendar: Calendar) -> Int {
        let length = lengthOfMonth(year, month, calendar: calendar)
        if day <= 0 { return length }
        return min(day, length)
    }

    static func isBusinessDay(_ day: LocalDay, calendar: Calendar, holidays: HolidayProviding) -> Bool {
        guard let date = day.date(in: calendar) else { return false }
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        return !holidays.isClosed(day)
    }

    /// Same-month schedules whose payday is not after the closing day in a non-leap February.
    static func breaksInShortFebruary(closingDay: Int, paydayDay: Int, monthOffset: Int, calendar: Calendar) -> Bool {
        guard monthOffset == 0 else { return false }
        let year = 2026
        let close = clampedDay(closingDay, year: year, month: 2, calendar: calendar)
        let pay = clampedDay(paydayDay, year: year, month: 2, calendar: calendar)
        return pay <= close
    }

    static func plan(
        workday: LocalDay,
        closingDay: Int,
        paydayDay: Int,
        monthOffset: Int,
        preferEarlier: Bool,
        calendar: Calendar,
        holidays: HolidayProviding = BankClosures()
    ) -> PaydayPlan {
        let closeNumber = clampedDay(closingDay, year: workday.year, month: workday.month, calendar: calendar)
        let periodStartMonth = workday.day <= closeNumber ? 0 : 1
        let period = monthShift(workday, by: periodStartMonth, calendar: calendar)
        let closing = LocalDay(
            year: period.year,
            month: period.month,
            day: clampedDay(closingDay, year: period.year, month: period.month, calendar: calendar)
        )
        let payMonth = monthShift(period, by: max(0, monthOffset), calendar: calendar)
        let raw = LocalDay(
            year: payMonth.year,
            month: payMonth.month,
            day: clampedDay(paydayDay, year: payMonth.year, month: payMonth.month, calendar: calendar)
        )
        let adjusted = adjust(raw, closing: closing, preferEarlier: preferEarlier, calendar: calendar, holidays: holidays)
        return PaydayPlan(closing: closing, payday: adjusted.day, direction: adjusted.direction)
    }

    static func sentence(closingDay: Int, paydayDay: Int, monthOffset: Int) -> String {
        let close = closingDay <= 0 ? "末日" : "\(closingDay)日"
        let pay = paydayDay <= 0 ? "末日" : "\(paydayDay)日"
        let when: String
        switch monthOffset {
        case 0: when = "当月"
        case 1: when = "翌月"
        case 2: when = "翌々月"
        default: when = "\(monthOffset)か月後"
        }
        return "毎月1日〜\(close)までの勤務分を、\(when)\(pay)に受け取ります。31日がない月は、その月の末日です。"
    }

    private static func monthShift(_ day: LocalDay, by months: Int, calendar: Calendar) -> LocalDay {
        guard let start = day.date(in: calendar),
              let next = calendar.date(byAdding: .month, value: months, to: start) else { return day }
        return LocalDay.from(next, calendar: calendar)
    }

    private static func adjust(
        _ raw: LocalDay,
        closing: LocalDay,
        preferEarlier: Bool,
        calendar: Calendar,
        holidays: HolidayProviding
    ) -> (day: LocalDay, direction: PaydayDirection) {
        if isBusinessDay(raw, calendar: calendar, holidays: holidays) {
            return (raw, .unchanged)
        }
        if preferEarlier {
            let earlier = walk(raw, step: -1, calendar: calendar, holidays: holidays)
            if earlier > closing { return (earlier, .earlier) }
        }
        return (walk(raw, step: 1, calendar: calendar, holidays: holidays), .later)
    }

    private static func walk(_ start: LocalDay, step: Int, calendar: Calendar, holidays: HolidayProviding) -> LocalDay {
        var day = start.adding(days: step, calendar: calendar)
        for _ in 0..<14 {
            if isBusinessDay(day, calendar: calendar, holidays: holidays) { return day }
            day = day.adding(days: step, calendar: calendar)
        }
        return day
    }
}

struct WagePoint: Equatable {
    var day: LocalDay
    var yen: Int
}

enum WageLookup {
    /// The last point on the latest day on or before `day` wins. Empty history uses `fallback`.
    static func yen(on day: LocalDay, history: [WagePoint], fallback: Int) -> Int {
        var chosen: WagePoint?
        for point in history where point.day <= day {
            if let current = chosen, point.day < current.day { continue }
            chosen = point
        }
        return chosen?.yen ?? fallback
    }
}

enum LiveEarnings {
    /// Breaks without a clock range contribute 0 seconds. The result is floored, so it does not rise by rounding.
    static func yen(elapsedSeconds: Int, breakSeconds: Int, hourlyYen: Int) -> Int {
        let paid = max(0, elapsedSeconds - max(0, breakSeconds))
        return Int((Int64(max(0, hourlyYen)) * Int64(paid)) / 3600)
    }
}
