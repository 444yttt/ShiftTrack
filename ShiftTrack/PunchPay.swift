import Foundation

/// Payable minutes from raw punches. The stored punch is not rewritten.
/// Rounding uses the workplace wall clock, not seconds since 1970.
enum PunchPay {
    struct View: Equatable {
        var payableStart: Date
        var payableEnd: Date
        var actualMinutes: Int
        var payableMinutes: Int
        var shorterThanPunch: Bool
    }

    static func payable(
        plannedStart: Date,
        clockIn: Date,
        clockOut: Date,
        unitMinutes: Int,
        start: InOutRecovered.RoundingDirection,
        end: InOutRecovered.RoundingDirection,
        earlyCountsFromPlan: Bool,
        calendar: Calendar
    ) -> View {
        var payableStart = InOutRecovered.roundedDate(
            clockIn,
            unitMinutes: unitMinutes,
            direction: start,
            calendar: calendar
        )
        let payableEnd = InOutRecovered.roundedDate(
            clockOut,
            unitMinutes: unitMinutes,
            direction: end,
            calendar: calendar
        )
        if earlyCountsFromPlan, payableStart < plannedStart {
            payableStart = plannedStart
        }
        let actual = minutes(from: clockIn, to: clockOut)
        let paid = minutes(from: payableStart, to: payableEnd)
        return View(
            payableStart: payableStart,
            payableEnd: payableEnd,
            actualMinutes: actual,
            payableMinutes: paid,
            shorterThanPunch: paid < actual
        )
    }

    static func minutes(from start: Date, to end: Date) -> Int {
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.down))
    }

    static func line(clockIn: Date, clockOut: Date, payable: View, calendar: Calendar) -> String {
        var text = "打刻 \(clock(clockIn, calendar: calendar))–\(clock(clockOut, calendar: calendar))。丸め後 \(clock(payable.payableStart, calendar: calendar))–\(clock(payable.payableEnd, calendar: calendar))。予定の給料は変えていません。"
        if payable.shorterThanPunch {
            text += "丸めた時間は打刻より短いです。"
        }
        return text
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
