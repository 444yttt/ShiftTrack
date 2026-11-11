import Foundation

/// Today-screen clock. `WorkplaceListView` installs a 1-second timeline only
/// while `start <= gate < end`. The closure copies shift start and end, then
/// scales break minutes from `Context.date`. The gate date from `0x100260e08`
/// was not reduced to `Date()` or `Context.date`. The yen is that copied
/// interval, not pay earned so far.
///
/// 「いま稼いだお給料」 is a different function. Its help text says the number
/// increases. This amount does not, and 7500 yen was not read from a screen.
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

    static func line(_ phase: Phase, evaluation: ScheduledPay.Evaluation?) -> String {
        switch phase {
        case .notAShift:
            return "開始と終了が同じです"
        case .beforeStart(let minutes):
            return "はじまりまで あと \(Formatters.hours(minutes))"
        case .during(_, _, let minutes):
            return scheduledLine(evaluation, suffix: "終わりまで あと \(Formatters.hours(minutes))")
        case .afterEnd:
            return scheduledLine(evaluation, suffix: "終了しました")
        }
    }

    private static func scheduledLine(_ evaluation: ScheduledPay.Evaluation?, suffix: String) -> String {
        switch evaluation {
        case .amount(let amount):
            return "予定全体の時給分 \(ScheduledPay.amountText(amount.total))（交通費の前）。今まで稼いだ金額ではありません。\(suffix)"
        case .historyOpen:
            return "給与の目安：時給の履歴がすべてシフト日より後で、そのときの時給は未確定です。\(suffix)"
        case .notThisFormula, nil:
            return "給与の目安：日給の未確定な条件、または入力した金額のため、予定全体の時給分は出していません。\(suffix)"
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
