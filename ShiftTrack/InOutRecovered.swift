import Foundation

/// Reconstruction from the authorized IN/OUT binary. Not original Swift,
/// not Ghidra output, and not a guess at payroll, rounding, break selection,
/// or week paging.
///
/// Addresses are in `com.graff.inout` 1.0 (3). Pseudocode for the same
/// addresses is in the public analysis repo `notes/ghidra/`, commit
/// `ba221abdcf7d483b50a28aaf0fb4bcbe7fd40459`.
enum InOutRecovered {
    struct BreakRule {
        var overMinutes: Int
        var breakMinutes: Int
    }

    /// `0x1000da43c` writes these two BreakRule values. The comparison that
    /// would choose one of them from worked minutes was not recovered, so
    /// nothing in the editor or pay path reads this table.
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
}
