import Foundation

/// Reconstruction from the authorized IN/OUT binary. Not original Swift
/// and not Ghidra output. The yen formula is not here.
///
/// Addresses are in `com.graff.inout` 1.0 (3). Pseudocode is in the public
/// analysis repo. Minute and day calls match commit `ba221ab`. Break
/// selection, the editor minute count, and week-times-7 match `06aefb3`.
/// Break scaling and pay-term rounding match `cd54b57`. Rounding changes
/// a clock instant. It is not a yen amount.
enum InOutRecovered {
    struct BreakRule {
        var overMinutes: Int
        var breakMinutes: Int
    }

    /// `0x1000da43c` writes these two BreakRule values. `BreakRules` reads
    /// them when a workplace's `customBreaks` is off.
    static let legalBreakRules: [BreakRule] = [
        .init(overMinutes: 360, breakMinutes: 45),
        .init(overMinutes: 480, breakMinutes: 60),
    ]

    /// `0x1000defb8` constant pool `(1320, 300)` with enabled byte 1 and rate 25.
    /// 1320 and 300 are 22:00 and 05:00. The percent is not a yen wage, and the
    /// formula that would apply it was not recovered.
    static let defaultNightStartMinute = 1320
    static let defaultNightEndMinute = 300
    static let defaultNightRatePercent = 25

    /// Same function. Threshold 480 minutes (8 hours), rate 25, enabled byte 1.
    static let defaultOvertimeThresholdMinutes = 480
    static let defaultOvertimeRatePercent = 25

    /// Same function. Seven weekday percents, all zero, enabled byte 0.
    static let defaultHolidayEnabled = false

    /// `0x1000968c4`. Remainder of 1440, then 1440 added when negative.
    /// Hour is `/ 60`. Minute is the remainder.
    static func minuteOfDay(_ absoluteMinutes: Int) -> (hour: Int, minute: Int) {
        var wrapped = absoluteMinutes % 1440
        if wrapped < 0 {
            wrapped += 1440
        }
        let hour = wrapped / 60
        let minute = wrapped - hour * 60
        return (hour, minute)
    }

    /// `0x100027f04` calls `date(bySettingHour:minute:second:of:matchingPolicy:repeatedTimePolicy:direction:)`
    /// with second 0, `.nextTime`, `.first`, and `.forward` after the 1440/60 split.
    /// The product passes a fixed anchor day here. Passing the shift's stored day,
    /// or `Date()` as the decompiled `of:` slot may be, would let the wheel carry a
    /// calendar day into the shift.
    static func date(
        fromMinuteBinding minutes: Int,
        on day: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let parts = minuteOfDay(minutes)
        return calendar.date(
            bySettingHour: parts.hour,
            minute: parts.minute,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    /// `Calendar.date(byAdding:value:to:wrappingComponents:)` with `.day` and
    /// `wrappingComponents: false`, the call recovered at `0x1001b4a94`,
    /// `0x1000837d8`, and `0x10006028c`. The fixed offsets below are not a
    /// week-of-year step and are not used to change the visible month.
    static func addingDays(_ value: Int, to day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: value, to: day, wrappingComponents: false)
    }

    /// `0x1001b4a94`: `startOfDay`, then day offsets -1 and +2.
    static func dayWindow(around day: Date, calendar: Calendar = .current) -> (previous: Date?, twoAhead: Date?) {
        let start = calendar.startOfDay(for: day)
        return (
            addingDays(-1, to: start, calendar: calendar),
            addingDays(2, to: start, calendar: calendar)
        )
    }

    /// `0x1000837d8`: day offsets +14 and -1.
    static func dayOffsets(from day: Date, calendar: Calendar = .current) -> (ahead: Date?, previous: Date?) {
        (
            addingDays(14, to: day, calendar: calendar),
            addingDays(-1, to: day, calendar: calendar)
        )
    }

    /// `0x10020499c`. Week count times 7, then `Calendar.Component.day`,
    /// wrappingComponents false. The ±1 that produces the week count was not
    /// in this function. `weekSlideTag` is not used.
    static func addingWeeks(_ weeks: Int, to day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: weeks * 7, to: day, wrappingComponents: false)
    }

    /// `0x1000e967c`. Rules with `overMinutes < minutes`, then the greatest
    /// threshold. An equal threshold keeps the earlier rule. No match is 0.
    static func selectedBreakMinutes(_ minutes: Int, rules: [BreakRule]) -> Int {
        var best: BreakRule?
        for rule in rules where rule.overMinutes < minutes {
            if let current = best, current.overMinutes >= rule.overMinutes {
                continue
            }
            best = rule
        }
        return best?.breakMinutes ?? 0
    }

    /// `0x1001c75ec`. Signed division by 1440 using the instruction's magic
    /// constant, then hour = `(remainder * 0x8889) >> 21`. Second is 0 when
    /// this pair is passed to `bySettingHour`. Not a wage formula.
    static func clockFromPatternMinute(_ minute: Int) -> (hour: Int, minute: Int) {
        let magic = Int(bitPattern: 0x2D82_D82D_D82D_82D3)
        let (high, _) = minute.multipliedFullWidth(by: magic)
        let quotient = (high >> 8) &+ (high < 0 ? 1 : 0)
        var remainder = minute &- quotient &* 1440
        if remainder < 0 {
            remainder &+= 1440
        }
        let hour = (remainder * 0x8889) >> 21
        return (hour, remainder - hour * 60)
    }

    /// `0x1001c80a4`. `start >= end`, including equal minutes, adds one day
    /// before the end `bySettingHour`. The compared values are the pattern
    /// fields, not the wrapped clocks.
    static func patternEndAddsOneDay(startMinute: Int, endMinute: Int) -> Bool {
        startMinute >= endMinute
    }

    /// `0x1001b8770`. End minus start, positive remainder of 1440.
    /// A zero remainder, including equal minutes, is 1440.
    /// `BreakRules` does not pass that 1440 into a shift the product rejects.
    static func editorMinuteCount(startMinute: Int, endMinute: Int) -> Int {
        let difference = endMinute - startMinute
        let remainder = difference % 1440
        let positive = remainder < 0 ? remainder + 1440 : remainder
        return positive == 0 ? 1440 : positive
    }

    /// Case order matches `0x10011b1d0`: exact, up, down. Any other byte,
    /// including nearest, uses ties away from zero.
    enum RoundingDirection: UInt8 {
        case exact = 0
        case up = 1
        case down = 2
        case nearest = 3

        /// A byte outside the three compared values takes the nearest path.
        static func resolved(_ raw: Int) -> RoundingDirection {
            RoundingDirection(rawValue: UInt8(clamping: raw)) ?? .nearest
        }
    }

    /// `PayRounding`: unit, then the start direction at byte +8 and the end
    /// direction at byte +9. `PayTerms.rounding` is field 6.
    struct PayRounding {
        var unitMinutes: Int
        var start: RoundingDirection
        var end: RoundingDirection
    }

    /// `0x10011b1d0`. `unitMinutes < 2` or `exact` returns the seconds unchanged.
    /// Otherwise divide seconds-from-start-of-day by `unitMinutes * 60`,
    /// round up with `frintp`, down with `frintm`, or ties away from zero,
    /// then multiply the unit back. This is not a 1440-minute wrap.
    /// The binary's multiply is checked and traps on overflow. This copy uses
    /// Swift `*`, which also traps. The published tests do not overflow.
    static func roundedSecondsFromStartOfDay(
        _ seconds: Double,
        unitMinutes: Int,
        direction: RoundingDirection
    ) -> Double {
        if unitMinutes < 2 || direction == .exact {
            return seconds
        }
        let unit = Double(unitMinutes * 60)
        let units = seconds / unit
        let rounded: Double
        switch direction {
        case .exact:
            rounded = units
        case .up:
            rounded = units.rounded(.up)
        case .down:
            rounded = units.rounded(.down)
        case .nearest:
            rounded = units.rounded(.toNearestOrAwayFromZero)
        }
        return rounded * unit
    }

    /// Rounds one instant against its own start of day. Start and end each
    /// call this with their own direction byte.
    static func roundedDate(
        _ date: Date,
        unitMinutes: Int,
        direction: RoundingDirection,
        calendar: Calendar = .current
    ) -> Date {
        let start = calendar.startOfDay(for: date)
        let original = date.timeIntervalSince(start)
        let seconds = roundedSecondsFromStartOfDay(
            original,
            unitMinutes: unitMinutes,
            direction: direction
        )
        if seconds == original {
            return date
        }
        return start.addingTimeInterval(seconds)
    }

    /// `0x10026e844`. `shiftEnd < now` uses the end. Equal instants stay on now.
    static func liveAsOf(now: Date, shiftEnd: Date) -> Date {
        shiftEnd < now ? shiftEnd : now
    }

    /// Same function. Zero or negative duration stores 0. Otherwise
    /// `frinta(elapsedSeconds * breakMinutes / duration)` then toward zero.
    /// The result is `WorkRecord.breakMinutes`. Planned start and end stay
    /// put. A negative elapsed value stays negative. That path was not seen
    /// on a screen. This number is a break input, not yen.
    static func scaledBreakMinutes(start: Date, end: Date, asOf: Date, breakMinutes: Int) -> Int {
        let duration = end.timeIntervalSince(start)
        if duration <= 0 {
            return 0
        }
        let elapsed = asOf.timeIntervalSince(start)
        let scaled = (elapsed * Double(breakMinutes) / duration).rounded(.toNearestOrAwayFromZero)
        return Int(scaled)
    }

    /// 0x10011b848. With any BreakSpan the fraction stays 1 and those minutes
    /// are dropped one by one. Without spans the fraction is
    /// `max(0, minutes - breakMinutes) / minutes`.
    static func paidMinuteFraction(totalSeconds: Double, breakMinutes: Int, hasBreakSpans: Bool) -> Double {
        if hasBreakSpans {
            return 1
        }
        let minutes = totalSeconds / 60
        if minutes <= 0 {
            return 0
        }
        let paid = minutes - Double(breakMinutes)
        return (paid >= 0 ? paid : 0) / minutes
    }

    /// 0x10011bf14. Paid minutes times the hourly integer, divided by 60.
    /// The integer is a band wage or the wage-history return. This is base.
    static func hourlyYen(paidMinutes: Double, hourlyWage: Int) -> Double {
        paidMinutes * Double(hourlyWage) / 60
    }

    /// No BreakSpans. `totalSeconds` is the record's own start-to-end interval.
    static func scheduledHourlyYen(totalSeconds: Double, breakMinutes: Int, hourlyWage: Int) -> Double {
        let fraction = paidMinuteFraction(
            totalSeconds: totalSeconds,
            breakMinutes: breakMinutes,
            hasBreakSpans: false
        )
        return hourlyYen(paidMinutes: (totalSeconds / 60) * fraction, hourlyWage: hourlyWage)
    }

    /// 0x10011bd08. Equal bounds are empty. Same-day end is exclusive.
    /// Otherwise the window wraps midnight.
    static func minuteIsInPremiumWindow(minuteOfDay: Int, start: Int, end: Int) -> Bool {
        if start == end {
            return false
        }
        if start < end {
            return minuteOfDay >= start && minuteOfDay < end
        }
        return minuteOfDay >= start || minuteOfDay < end
    }

    /// 0x10011c168. Night premium is the slice's own base times rate / 100.
    static func nightPremiumYen(
        sliceYen: Double,
        ratePercent: Int,
        enabled: Bool,
        inWindow: Bool,
        bandIncludesNight: Bool
    ) -> Double {
        if enabled && inWindow && !bandIncludesNight && ratePercent != 0 {
            return sliceYen * Double(ratePercent) / 100
        }
        return 0
    }

    /// 0x10011c454. The minute that lands on the threshold adds nothing.
    static func overtimeMinutes(sliceMinutes: Double, priorMinutes: Double, threshold: Double) -> Double {
        let under = threshold - priorMinutes
        let capped = under < sliceMinutes ? under : sliceMinutes
        if capped < 0 {
            return sliceMinutes
        }
        let extra = sliceMinutes - capped
        return extra > 0 ? extra : 0
    }

    /// 0x10011c684.
    static func overtimePremiumYen(overtimeMinutes: Double, hourlyWage: Int, ratePercent: Int) -> Double {
        if ratePercent == 0 || overtimeMinutes == 0 {
            return 0
        }
        return overtimeMinutes * Double(hourlyWage) / 60 * Double(ratePercent) / 100
    }

    /// Weekday is `DateComponents.weekday`. The index is that value minus 1.
    static func holidayRatePercent(weekday: Int?, rates: [Int]) -> Int? {
        guard let weekday else { return nil }
        let index = weekday - 1
        guard index >= 0, index < rates.count else { return nil }
        return rates[index]
    }

    static func holidayPremiumYen(sliceYen: Double, ratePercent: Int) -> Double {
        sliceYen * Double(ratePercent) / 100
    }

    /// 0x10011a36c. Daily wage is added only when `PayMethod` is daily and
    /// `UUID.==` is true. The two UUID fields were not identified, so the
    /// caller passes the comparison result. A false result does not add yen.
    static func baseAfterDailyWage(base: Double, dailyWage: Int, methodIsDaily: Bool, flagBit: Bool) -> Double {
        guard methodIsDaily, flagBit else { return base }
        return base + Double(dailyWage)
    }

    /// 0x10011acd0. Transport kind and amount of at least 1. Not an allowance.
    static func transportAfterExtra(transport: Double, amount: Int, kindIsTransport: Bool) -> Double {
        guard kindIsTransport, amount >= 1 else { return transport }
        return transport + Double(amount)
    }

    /// 0x10026ecf0 adds base and premium for `numericText`. Transport is absent.
    static func liveNumericTotal(base: Double, premium: Double) -> Double {
        base + premium
    }

    /// 0x100262af8 and 0x100262b14. `WorkplaceListView` builds the 1-second
    /// timeline only when `start <= gate < end`. The compares do not write
    /// the dates. `gate` comes from 0x100260e08 and was not reduced to `Date()`
    /// or `TimelineView.Context.date`.
    static func showsOneSecondPayTimeline(start: Date, end: Date, gate: Date) -> Bool {
        start <= gate && gate < end
    }

    /// 0x1000de424. Walks history from the last element. `effectiveFrom` is
    /// reduced to a calendar day and compared with the shift's start of day.
    /// The first day that is <= the shift day supplies its hourly wage.
    /// Empty history returns 0. If every day is after the shift, the return
    /// was not reduced, so this returns nil instead of inventing a wage.
    /// The loop does not sort the array.
    static func selectedHourlyWage(
        shiftDate: Date,
        history: [(effectiveFrom: Date, hourlyWage: Int)],
        calendar: Calendar = .current
    ) -> Int? {
        if history.isEmpty {
            return 0
        }
        let shiftDay = calendar.startOfDay(for: shiftDate)
        for rate in history.reversed() {
            let parts = calendar.dateComponents([.year, .month, .day], from: rate.effectiveFrom)
            guard let rateDay = calendar.date(from: parts) else { continue }
            if rateDay <= shiftDay {
                return rate.hourlyWage
            }
        }
        return nil
    }

    /// 0x100119384. perPeriod (2) is skipped. Only transport kind 0 is added,
    /// once, when amount is at least 1. perDay reaches that same add only
    /// after a UUID and count check that was not reduced, so this is not
    /// "multiplied by the number of days". Allowance and deduction are not added.
    static func transportAfterPayItem(
        transport: Double,
        kind: Int,
        unit: Int,
        amount: Int,
        condition: Int,
        nightMinutes: Double
    ) -> Double {
        if unit == 2 || kind != 0 {
            return transport
        }
        if condition == 1 && !(nightMinutes > 0) {
            return transport
        }
        if amount < 1 {
            return transport
        }
        return transport + Double(amount)
    }
}
