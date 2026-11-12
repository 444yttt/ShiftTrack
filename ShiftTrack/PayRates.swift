import Foundation

/// The one per-minute wage table. `PayMath` (monthly totals, shift estimates)
/// and `EarningsSoFar` (the live number on the home screen) both read it, so a
/// shift's live earnings end exactly where its estimate in the totals is.
///
/// Base is `Workplace.hourlyWage`. A premium that is switched on uses its yen
/// amount when one is set. When the amount is 0 it uses its percent on top of
/// the base instead, so an enabled premium can never pay ¥0 for a minute.
/// (The setup wizard used to switch night pay on with only a percent, and the
/// old table then paid ¥0 for every night minute.)
struct PayRates {
    let workplace: Workplace
    /// True when holiday pay is on and the shift's day is one of its weekdays.
    let isHoliday: Bool
    /// Calendar weekday (1 = Sunday) of the shift's day.
    let weekday: Int

    init(workplace: Workplace, day: Date, calendar: Calendar = .current) {
        self.workplace = workplace
        let weekday = calendar.component(.weekday, from: calendar.startOfDay(for: day))
        self.weekday = weekday
        self.isHoliday = workplace.holidayPayEnabled && workplace.holidayWeekdays.contains(weekday)
    }

    var baseWage: Int { max(0, workplace.hourlyWage) }

    /// Holiday percent for this weekday, from the seven stored percents.
    var holidayPercent: Int {
        let rates = workplace.holidayRatePercents
        let index = weekday - 1
        guard rates.indices.contains(index) else { return 0 }
        return max(0, rates[index])
    }

    var nightPercent: Int { max(0, workplace.nightRatePercent) }

    /// Yen per hour for the minute `minuteOfDay` (any integer; wrapped to a clock minute).
    func hourlyRate(atMinuteOfDay minuteOfDay: Int) -> Int {
        let minute = PayRates.wrap(minuteOfDay)
        let base = baseWage
        if isHoliday,
           workplace.holidayNightEnabled,
           PayRates.contains(minute, workplace.holidayNightStartMinutes, workplace.holidayNightEndMinutes) {
            if workplace.holidayNightWage > 0 { return workplace.holidayNightWage }
            return PayRates.raised(base, percent: holidayPercent + nightPercent)
        }
        if !isHoliday,
           workplace.nightPayEnabled,
           PayRates.contains(minute, workplace.nightStartMinutes, workplace.nightEndMinutes) {
            if workplace.nightWage > 0 { return workplace.nightWage }
            return PayRates.raised(base, percent: nightPercent)
        }
        if isHoliday, workplace.holidayPayEnabled {
            if workplace.holidayWage > 0 { return workplace.holidayWage }
            return PayRates.raised(base, percent: holidayPercent)
        }
        return base
    }

    /// Overtime yen for a shift with `paidMinutes`, rounded like the rest of the
    /// monthly totals. A yen amount wins over the percent when both are set.
    func overtimeYen(paidMinutes: Int) -> Int {
        guard workplace.overtimeEnabled else { return 0 }
        let extra = max(0, paidMinutes - max(0, workplace.overtimeAfterMinutes))
        guard extra > 0 else { return 0 }
        let amount = max(0, workplace.overtimeExtra)
        if amount > 0 {
            return workplace.overtimePerHour ? (amount * extra + 30) / 60 : amount
        }
        let percent = max(0, workplace.overtimeRatePercent)
        guard percent > 0 else { return 0 }
        return (baseWage * percent * extra + 3_000) / 6_000
    }

    /// Unrounded overtime yen after `paidMinutes` (may be fractional) of paid time.
    func overtimeYenExact(paidMinutes: Double) -> Double {
        guard workplace.overtimeEnabled else { return 0 }
        let extra = max(0, paidMinutes - Double(max(0, workplace.overtimeAfterMinutes)))
        guard extra > 0 else { return 0 }
        let amount = max(0, workplace.overtimeExtra)
        if amount > 0 {
            return workplace.overtimePerHour ? Double(amount) * extra / 60 : Double(amount)
        }
        let percent = max(0, workplace.overtimeRatePercent)
        return Double(baseWage) * Double(percent) / 100 * extra / 60
    }

    /// Sum of yen-per-hour rates over the first `minutes` whole paid minutes from `start`.
    func weightedRateSum(start: Int, minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        var total = 0
        for offset in 0..<minutes {
            total += hourlyRate(atMinuteOfDay: start + offset)
        }
        return total
    }

    /// `base × (100 + percent) / 100`, rounded half up to whole yen per hour.
    static func raised(_ base: Int, percent: Int) -> Int {
        (max(0, base) * (100 + max(0, percent)) + 50) / 100
    }

    static func wrap(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }

    /// Half-open window `[start, end)` on the clock. Equal bounds are empty;
    /// a start after the end wraps past midnight.
    static func contains(_ minute: Int, _ start: Int, _ end: Int) -> Bool {
        let minute = wrap(minute)
        let start = wrap(start)
        let end = wrap(end)
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }
}
