import Foundation
import SwiftData
import SwiftUI

@Model
final class Workplace {
    var uuid: UUID
    var name: String
    var colorHex: String
    var hourlyWage: Int
    var transportAllowance: Int
    var notes: String
    var genre: String
    var place: String
    /// Read from a shop card or a maps link. Empty on older rows.
    var phone: String = ""
    var openingHours: String = ""
    var officialURL: String = ""
    /// Set only when the person asks to look up the address. 0 is not a saved pin.
    var latitude: Double = 0
    var longitude: Double = 0
    var hasMapCoordinate: Bool = false
    var closingDay: Int
    var paydayMonthOffset: Int
    var paydayDay: Int
    var payIsDaily: Bool
    var dailyWage: Int
    var holidayPayEnabled: Bool
    var holidayWage: Int
    var holidayWeekdaysRaw: String
    var nightPayEnabled: Bool
    var nightWage: Int
    var nightStartMinutes: Int
    var nightEndMinutes: Int
    var holidayNightEnabled: Bool
    var holidayNightWage: Int
    var holidayNightStartMinutes: Int
    var holidayNightEndMinutes: Int
    var overtimeEnabled: Bool
    var overtimeAfterMinutes: Int
    var overtimePerHour: Bool
    var overtimeExtra: Int
    /// Percent added by the recovered night premium. 0 adds nothing.
    /// Existing rows stay 0, so this does not change stored shifts.
    var nightRatePercent: Int = 0
    /// Percent added on minutes past the overtime threshold. 0 adds nothing.
    var overtimeRatePercent: Int = 0
    /// Seven percents, Sunday first, matching `weekday - 1`. Empty is all zero.
    var holidayRatesRaw: String = ""
    /// `effectiveFrom|yen` rows, walked from the end. Empty selects wage 0.
    /// A row whose calendar day is after the shift does not match.
    var wageHistoryRaw: String = ""
    /// Calendar days the pay rules start. Empty on older rows. Not used by pay math.
    var payRuleDatesRaw: String = ""
    /// Stored `start|end|yen|night` rows. Band bounds are not closed, so the
    /// scheduled amount does not switch wages from these rows.
    var wageBandsRaw: String = ""
    /// Off uses the legal 6h/8h table. On uses `breakRulesRaw`.
    var customBreaks: Bool = false
    /// `overMinutes:breakMinutes` pairs, earlier first. Empty is not the legal table.
    var breakRulesRaw: String = ""
    /// Clock rounding from `PayTerms.rounding`. Unit below 2, or either
    /// direction `exact` (0), leaves that instant unchanged. Existing rows
    /// get 1 and exact, which is a no-op. Saving this does not rewrite shifts.
    var roundingUnitMinutes: Int = 1
    var roundingStartRaw: Int = 0
    var roundingEndRaw: Int = 0
    /// When true, a punch earlier than the planned start is paid from the plan.
    /// The stored punch stays the raw time. Existing rows stay false.
    var earlyClockCountsFromPlan: Bool = false
    /// Independent deposit cycle. `month` keeps the existing payday.
    /// `week` and `day` apply only after the user chooses them.
    var payCycleRaw: String = "month"
    /// Calendar weekday 1...7. Read only when the cycle is `week`.
    var payWeekday: Int = 0
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkShift.workplace)
    var shifts: [WorkShift]

    init(
        name: String,
        colorHex: String,
        hourlyWage: Int,
        transportAllowance: Int,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.uuid = UUID()
        self.name = name
        self.colorHex = colorHex
        self.hourlyWage = hourlyWage
        self.transportAllowance = transportAllowance
        self.notes = notes
        self.genre = ""
        self.place = ""
        self.phone = ""
        self.openingHours = ""
        self.officialURL = ""
        self.latitude = 0
        self.longitude = 0
        self.hasMapCoordinate = false
        self.closingDay = 0
        self.paydayMonthOffset = 0
        self.paydayDay = 0
        self.payIsDaily = false
        self.dailyWage = 0
        self.holidayPayEnabled = InOutRecovered.defaultHolidayEnabled
        self.holidayWage = 0
        self.holidayWeekdaysRaw = ""
        self.nightPayEnabled = false
        self.nightWage = 0
        self.nightStartMinutes = InOutRecovered.defaultNightStartMinute
        self.nightEndMinutes = InOutRecovered.defaultNightEndMinute
        self.holidayNightEnabled = false
        self.holidayNightWage = 0
        self.holidayNightStartMinutes = InOutRecovered.defaultNightStartMinute
        self.holidayNightEndMinutes = InOutRecovered.defaultNightEndMinute
        self.overtimeEnabled = false
        self.overtimeAfterMinutes = InOutRecovered.defaultOvertimeThresholdMinutes
        self.overtimePerHour = true
        self.overtimeExtra = 0
        self.nightRatePercent = 0
        self.overtimeRatePercent = 0
        self.holidayRatesRaw = ""
        self.wageHistoryRaw = ""
        self.payRuleDatesRaw = ""
        self.wageBandsRaw = ""
        self.customBreaks = false
        self.breakRulesRaw = ""
        self.roundingUnitMinutes = 1
        self.roundingStartRaw = Int(InOutRecovered.RoundingDirection.exact.rawValue)
        self.roundingEndRaw = Int(InOutRecovered.RoundingDirection.exact.rawValue)
        self.earlyClockCountsFromPlan = false
        self.payCycleRaw = PayCycle.month.rawValue
        self.payWeekday = 0
        self.createdAt = createdAt
        self.shifts = []
    }

    var holidayWeekdays: Set<Int> {
        Set(holidayWeekdaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    func setHolidayWeekdays(_ days: Set<Int>) {
        holidayWeekdaysRaw = days.sorted().map(String.init).joined(separator: ",")
    }

    var color: Color { Color(hexString: colorHex) }

    var breakRules: [InOutRecovered.BreakRule] {
        get { BreakRules.decode(breakRulesRaw) }
        set { breakRulesRaw = BreakRules.encode(newValue) }
    }

    var roundingChangesClock: Bool {
        if roundingUnitMinutes < 2 { return false }
        let start = InOutRecovered.RoundingDirection.resolved(roundingStartRaw)
        let end = InOutRecovered.RoundingDirection.resolved(roundingEndRaw)
        return start != .exact || end != .exact
    }

    var holidayRatePercents: [Int] {
        let parsed = holidayRatesRaw.split(separator: ",").map { Int($0) ?? 0 }
        if parsed.count == 7 { return parsed }
        return Array(repeating: 0, count: 7)
    }

    func setHolidayRatePercents(_ rates: [Int]) {
        let seven = (0..<7).map { index in
            rates.indices.contains(index) ? min(100, max(0, rates[index])) : 0
        }
        holidayRatesRaw = seven.map(String.init).joined(separator: ",")
    }

    struct WageHistoryEntry: Equatable {
        var at: Date
        var hourlyWage: Int
    }

    var wageHistory: [WageHistoryEntry] {
        get {
            wageHistoryRaw.split(separator: ";").compactMap { row in
                let parts = row.split(separator: "|")
                guard parts.count == 2, let seconds = TimeInterval(parts[0]), let wage = Int(parts[1]) else { return nil }
                return WageHistoryEntry(at: Date(timeIntervalSince1970: seconds), hourlyWage: wage)
            }
        }
        set {
            wageHistoryRaw = newValue.map { "\($0.at.timeIntervalSince1970)|\($0.hourlyWage)" }.joined(separator: ";")
        }
    }

    var payRuleDates: [Date] {
        get {
            payRuleDatesRaw.split(separator: ";").compactMap { TimeInterval($0) }.map {
                Date(timeIntervalSince1970: $0)
            }
        }
        set {
            payRuleDatesRaw = newValue.map { "\($0.timeIntervalSince1970)" }.joined(separator: ";")
        }
    }

    struct WageBandEntry: Equatable {
        var startMinutes: Int
        var endMinutes: Int
        var hourlyWage: Int
        var includesNightPremium: Bool
    }

    var wageBands: [WageBandEntry] {
        get {
            wageBandsRaw.split(separator: ";").compactMap { row in
                let parts = row.split(separator: "|")
                guard parts.count == 4,
                      let start = Int(parts[0]),
                      let end = Int(parts[1]),
                      let wage = Int(parts[2]),
                      let night = Int(parts[3]) else { return nil }
                return WageBandEntry(startMinutes: start, endMinutes: end, hourlyWage: wage, includesNightPremium: night == 1)
            }
        }
        set {
            wageBandsRaw = newValue.map {
                "\($0.startMinutes)|\($0.endMinutes)|\($0.hourlyWage)|\($0.includesNightPremium ? 1 : 0)"
            }.joined(separator: ";")
        }
    }
}

@Model
final class WorkShift {
    var uuid: UUID
    var date: Date
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var notes: String
    var customPay: Int?
    var adjustmentYen: Int
    var adjustmentNote: String
    /// True only after the user saves a shift with rule-based breaks.
    /// Existing rows stay false, so their stored break is left alone.
    var breakFollowsRules: Bool = false
    /// Set only by the ShiftPart place path. Existing rows stay nil.
    var partID: UUID? = nil
    /// True when that path's raw `start >= end` comparison added one day.
    /// Existing rows stay false, so their pay span is unchanged.
    var patternEndOnNextDay: Bool = false
    /// Copied todos. `done` stays false on the place path. Empty for older rows.
    var todosRaw: String = ""
    /// Set only when the user taps 「この内容で確定」. Existing rows stay false.
    var attendanceConfirmed: Bool = false
    /// Actual clock confirmed on 勤務の確認. Nil means the scheduled time.
    /// Optional with a nil default so existing stores keep their rows.
    var actualStartMinutes: Int? = nil
    /// Actual clock confirmed on 勤務の確認. Nil means the scheduled time.
    var actualEndMinutes: Int? = nil
    /// Optional trip target. Empty means the workplace itself. Does not change pay.
    var destinationName: String = ""
    var destinationPlace: String = ""
    /// Attendance stamps. They do not replace the scheduled start or end, and pay ignores them.
    var clockedInAt: Date? = nil
    var clockedOutAt: Date? = nil
    var workplace: Workplace?

    init(
        date: Date,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int,
        notes: String = "",
        customPay: Int? = nil,
        adjustmentYen: Int = 0,
        adjustmentNote: String = "",
        breakFollowsRules: Bool = false,
        partID: UUID? = nil,
        patternEndOnNextDay: Bool = false,
        todosRaw: String = "",
        workplace: Workplace?,
        attendanceConfirmed: Bool = false,
        destinationName: String = "",
        destinationPlace: String = "",
        actualStartMinutes: Int? = nil,
        actualEndMinutes: Int? = nil
    ) {
        self.uuid = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.breakMinutes = breakMinutes
        self.notes = notes
        self.customPay = customPay
        self.adjustmentYen = adjustmentYen
        self.adjustmentNote = adjustmentNote
        self.breakFollowsRules = breakFollowsRules
        self.partID = partID
        self.patternEndOnNextDay = patternEndOnNextDay
        self.todosRaw = todosRaw
        self.workplace = workplace
        self.attendanceConfirmed = attendanceConfirmed
        self.destinationName = destinationName
        self.destinationPlace = destinationPlace
        self.actualStartMinutes = actualStartMinutes
        self.actualEndMinutes = actualEndMinutes
        self.clockedInAt = nil
        self.clockedOutAt = nil
    }

    /// Clock used for pay. A nil actual time means the shift is still as scheduled.
    var payableStartMinutes: Int { actualStartMinutes ?? startMinutes }
    var payableEndMinutes: Int { actualEndMinutes ?? endMinutes }
    var timesDifferFromSchedule: Bool {
        actualStartMinutes != nil || actualEndMinutes != nil
    }

    var todos: [ShiftTodoCodec.Item] {
        get { ShiftTodoCodec.decode(todosRaw) }
        set { todosRaw = ShiftTodoCodec.encode(newValue) }
    }

    var workedMinutes: Int {
        if timesDifferFromSchedule {
            return PayMath.workedMinutes(start: payableStartMinutes, end: payableEndMinutes, breakMinutes: breakMinutes)
        }
        if partID == nil {
            return PayMath.workedMinutes(start: startMinutes, end: endMinutes, breakMinutes: breakMinutes)
        }
        let start = ShiftDatePolicy.clockMinutes(startMinutes)
        let end = ShiftDatePolicy.clockMinutes(endMinutes)
        let span: Int
        if patternEndOnNextDay {
            span = end + 24 * 60 - start
        } else if end > start {
            span = end - start
        } else {
            span = 0
        }
        return max(0, span - max(0, breakMinutes))
    }

    func estimatedYen(includeTransport: Bool) -> Int {
        guard let workplace else { return 0 }
        return PayMath.shiftYen(self, includeTransport: includeTransport)
    }

    var needsAttendanceCheck: Bool {
        hasEnded() && !attendanceConfirmed
    }

    func hasEnded(now: Date = .now, calendar: Calendar = .current) -> Bool {
        let roll: Bool? = partID == nil ? nil : patternEndOnNextDay
        return PayMath.endDate(
            day: date,
            start: startMinutes,
            end: endMinutes,
            rollsToNextDay: roll,
            calendar: calendar
        ) <= now
    }

    var scheduleLabel: String {
        let time = "\(Formatters.clock(startMinutes))–\(Formatters.clock(endMinutes))"
        var label = "\(Formatters.monthDayWeekday(date))  \(time)"
        if breakMinutes > 0 {
            label += "  休憩\(breakMinutes)分"
        }
        return label
    }
}

@Model
final class AppSettings {
    var weekStartsOnMonday: Bool
    var includeTransport: Bool
    var defaultHourlyWage: Int
    var defaultTransportAllowance: Int
    var annualIncomeGoal: Int
    var monthlyIncomeGoal: Int
    var showPaydayOnCalendar: Bool
    var goalMonthOverrides: String
    var goalYearOverrides: String
    var salarySeenKey: String
    var salarySeenWorked: Int

    init(
        weekStartsOnMonday: Bool = false,
        includeTransport: Bool = true,
        defaultHourlyWage: Int = 1_200,
        defaultTransportAllowance: Int = 500,
        annualIncomeGoal: Int = 1_000_000,
        monthlyIncomeGoal: Int = 100_000
    ) {
        self.weekStartsOnMonday = weekStartsOnMonday
        self.includeTransport = includeTransport
        self.defaultHourlyWage = defaultHourlyWage
        self.defaultTransportAllowance = defaultTransportAllowance
        self.annualIncomeGoal = annualIncomeGoal
        self.monthlyIncomeGoal = monthlyIncomeGoal
        self.showPaydayOnCalendar = true
        self.goalMonthOverrides = ""
        self.goalYearOverrides = ""
        self.salarySeenKey = ""
        self.salarySeenWorked = 0
    }

    func monthGoal(year: Int, month: Int) -> Int {
        Self.overrideMap(goalMonthOverrides)[Self.monthKey(year, month)] ?? monthlyIncomeGoal
    }

    func yearGoal(_ year: Int) -> Int {
        Self.overrideMap(goalYearOverrides)[String(year)] ?? annualIncomeGoal
    }

    func setMonthGoal(_ value: Int, year: Int, month: Int, applyForward: Bool) {
        let key = Self.monthKey(year, month)
        if applyForward {
            monthlyIncomeGoal = value
            goalMonthOverrides = Self.overrideMap(goalMonthOverrides)
                .filter { $0.key < key }
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "|")
        } else {
            var map = Self.overrideMap(goalMonthOverrides)
            map[key] = value
            goalMonthOverrides = map.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "|")
        }
    }

    func setYearGoal(_ value: Int, year: Int, applyForward: Bool) {
        let key = String(year)
        if applyForward {
            annualIncomeGoal = value
            goalYearOverrides = Self.overrideMap(goalYearOverrides)
                .filter { $0.key < key }
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "|")
        } else {
            var map = Self.overrideMap(goalYearOverrides)
            map[key] = value
            goalYearOverrides = map.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "|")
        }
    }

    private static func monthKey(_ year: Int, _ month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    private static func overrideMap(_ raw: String) -> [String: Int] {
        var map: [String: Int] = [:]
        for part in raw.split(separator: "|") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2, let value = Int(pieces[1]) else { continue }
            map[String(pieces[0])] = value
        }
        return map
    }
}
