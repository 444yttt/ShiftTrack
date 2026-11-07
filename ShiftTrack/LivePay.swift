import Foundation

/// Today-screen clock. The recovered path scales break minutes from
/// `TimelineView.Context.date` (`0x10026e844`). It does not produce yen, and
/// it does not show that worked time is cut at now. Planned start and end
/// stay on the shift. Yen stays off this screen.
///
/// Two recovered timeline periods are 30 seconds and one is 1 second. Which
/// of them feeds this context was not tied by a pointer.
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
        calendar: Calendar = .current
    ) -> Phase {
        _ = workplace
        _ = customPay
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

    static func line(_ phase: Phase) -> String {
        switch phase {
        case .notAShift:
            return "開始と終了が同じです"
        case .beforeStart(let minutes):
            return "はじまりまで あと \(Formatters.hours(minutes))"
        case .during(_, _, let minutes):
            return "給与の目安：円は出していません。終わりまで あと \(Formatters.hours(minutes))"
        case .afterEnd:
            return "終了しました。給与の目安：円は出していません"
        }
    }

    static func breakCaption(_ phase: Phase) -> String {
        switch phase {
        case .notAShift:
            return "休憩は計算していません"
        case .beforeStart:
            return "開始前です。負の休憩按分は画面で未確認のため出していません"
        case .during(let scaled, let scheduled, _):
            guard let scaled else { return "休憩の目安は出していません" }
            return "休憩の目安 \(scaled)分（予定\(scheduled)分を経過の割合で按分。開始と終了は予定のまま）"
        case .afterEnd(let scaled, let scheduled):
            return "終了後の休憩は予定の\(scheduled)分です（按分 \(scaled)分）"
        }
    }

    /// Display for 「あと」. A remainder under a minute still shows 1 so the
    /// line does not say 0 while time is left. That ceiling is not recovered.
    static func remainingMinutes(until end: Date, from now: Date) -> Int {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds + 59.999) / 60)
    }
}
