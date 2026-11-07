import Foundation

/// Today-screen ticker. The IN/OUT strings describe a number that grows
/// during a shift ("いま稼いだお給料") and separate pay from transport
/// ("お給料（交通費の前）"). The pay function itself was not recovered.
/// Amounts below reuse `PayMath.timedAmount`, which is ShiftTrack's existing
/// per-minute reimplementation, not IN/OUT's `PayCalculator`.
///
/// Break spans were not recovered. Unpaid break minutes are the tail of the
/// shift. A break that sits in the middle of a shift is not reproduced.
enum LivePay {
    enum Phase: Equatable {
        case notAShift
        case beforeStart(remainingMinutes: Int)
        case working(earnedYen: Int, remainingMinutes: Int, inUnpaidTail: Bool)
        case finished(earnedYen: Int)
    }

    static func phase(
        now: Date,
        day: Date,
        start: Int,
        end: Int,
        breakMinutes: Int,
        workplace: Workplace,
        customPay: Int? = nil,
        calendar: Calendar = .current
    ) -> Phase {
        let span = BreakRules.selectionMinutes(start: start, end: end)
        guard span > 0 else { return .notAShift }
        let startDate = calendar.date(
            byAdding: .minute,
            value: ShiftDatePolicy.clockMinutes(start),
            to: calendar.startOfDay(for: day)
        ) ?? day
        let endDate = PayMath.endDate(day: day, start: start, end: end, calendar: calendar)
        if now < startDate {
            return .beforeStart(remainingMinutes: remainingMinutes(until: startDate, from: now))
        }
        let earned = earnedYen(
            elapsedMinutes: min(span, elapsedMinutes(from: startDate, to: min(now, endDate))),
            span: span,
            breakMinutes: breakMinutes,
            workplace: workplace,
            day: day,
            start: start,
            customPay: customPay,
            calendar: calendar
        )
        if now >= endDate {
            return .finished(earnedYen: earned)
        }
        let paidSpan = max(0, span - max(0, breakMinutes))
        let elapsed = min(span, elapsedMinutes(from: startDate, to: now))
        return .working(
            earnedYen: earned,
            remainingMinutes: remainingMinutes(until: endDate, from: now),
            inUnpaidTail: elapsed > paidSpan
        )
    }

    static func earnedYen(
        elapsedMinutes: Int,
        span: Int,
        breakMinutes: Int,
        workplace: Workplace,
        day: Date,
        start: Int,
        customPay: Int?,
        calendar: Calendar
    ) -> Int {
        if let customPay { return max(0, customPay) }
        if workplace.payIsDaily { return max(0, workplace.dailyWage) }
        let paidSpan = max(0, span - max(0, breakMinutes))
        let paidElapsed = min(paidSpan, max(0, elapsedMinutes))
        return PayMath.timedAmount(
            workplace: workplace,
            day: day,
            start: start,
            paidMinutes: paidElapsed,
            calendar: calendar
        )
    }

    /// Positive elapsed seconds truncated toward zero. Same direction as the
    /// recovered `fcvtzs` on a seconds value, applied here to the ticker.
    static func elapsedMinutes(from start: Date, to now: Date) -> Int {
        let seconds = now.timeIntervalSince(start)
        guard seconds > 0 else { return 0 }
        return Int(seconds / 60)
    }

    /// Display for 「あと」. A remainder under a minute still shows 1 so the
    /// line does not say 0 while time is left. That ceiling is not recovered.
    static func remainingMinutes(until end: Date, from now: Date) -> Int {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds + 59.999) / 60)
    }
}
