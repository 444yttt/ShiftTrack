import Foundation

/// Phase of a shift (before, during, after) with a break scaled by elapsed
/// time. Kept for its tests; the home screen now uses `EarningsSoFar`.
enum LivePay {
    enum Phase: Equatable {
        case notAShift
        case beforeStart(remainingMinutes: Int)
        /// `scaledBreak` is omitted when the recovered scale is negative.
        /// A negative break was not observed on a screen.
        case during(scaledBreak: Int?, scheduledBreak: Int, remainingMinutes: Int)
        case afterEnd(scaledBreak: Int, scheduledBreak: Int)
    }

    static func phase(
        now: Date,
        day: Date,
        start: Int,
        end: Int,
        breakMinutes: Int,
        workplace: Workplace,
        customPay: Int? = nil,
        rollsToNextDay: Bool? = nil,
        calendar: Calendar = .current
    ) -> Phase {
        _ = workplace
        _ = customPay
        let span = BreakRules.selectionMinutes(start: start, end: end)
        // A ShiftPart with equal minutes ends the next day. The editor still
        // rejects that pair; this flag is set only by the place path.
        guard span > 0 || rollsToNextDay == true else { return .notAShift }
        let startDate = calendar.date(
            byAdding: .minute,
            value: ShiftDatePolicy.clockMinutes(start),
            to: calendar.startOfDay(for: day)
        ) ?? day
        let endDate = PayMath.endDate(
            day: day,
            start: start,
            end: end,
            rollsToNextDay: rollsToNextDay,
            calendar: calendar
        )
        if now < startDate {
            return .beforeStart(remainingMinutes: remainingMinutes(until: startDate, from: now))
        }
        let asOf = InOutRecovered.liveAsOf(now: now, shiftEnd: endDate)
        let scaled = InOutRecovered.scaledBreakMinutes(
            start: startDate,
            end: endDate,
            asOf: asOf,
            breakMinutes: breakMinutes
        )
        if now >= endDate {
            return .afterEnd(scaledBreak: scaled, scheduledBreak: breakMinutes)
        }
        return .during(
            scaledBreak: scaled < 0 ? nil : scaled,
            scheduledBreak: breakMinutes,
            remainingMinutes: remainingMinutes(until: endDate, from: now)
        )
    }

    /// Display for 「あと」. A remainder under a minute still shows 1 so the
    /// line does not say 0 while time is left. That ceiling is not recovered.
    static func remainingMinutes(until end: Date, from now: Date) -> Int {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds + 59.999) / 60)
    }
}
