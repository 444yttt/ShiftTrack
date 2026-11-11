import Foundation

struct PayShiftInput: Equatable {
    var shiftID: UUID
    var workplaceID: UUID
    var workplaceName: String
    var day: LocalDay
    var minutes: Int
    var hourlyFallback: Int
    var history: [WagePoint]
    var transport: Int
    var adjustment: Int
    var closingDay: Int
    var paydayDay: Int
    var monthOffset: Int
}

struct PaySlice: Equatable, Identifiable {
    var id: String { shiftID.uuidString }
    var shiftID: UUID
    var workplaceID: UUID
    var workplaceName: String
    var day: LocalDay
    var minutes: Int
    var baseYen: Int
    var transportYen: Int
    var adjustmentYen: Int
    var payday: LocalDay

    var total: Int { baseYen + transportYen + adjustmentYen }
}

enum PayBreakdown {
    static func slice(
        _ input: PayShiftInput,
        calendar: Calendar,
        holidays: HolidayProviding = BankClosures()
    ) -> PaySlice {
        let wage = WageLookup.yen(on: input.day, history: input.history, fallback: input.hourlyFallback)
        let base = ExactYen.wage(yenPerHour: wage, minutes: max(0, input.minutes), rateBasisPoints: 10_000).roundedYen()
        let plan = PayScheduleMath.plan(
            workday: input.day,
            closingDay: input.closingDay,
            paydayDay: input.paydayDay,
            monthOffset: input.monthOffset,
            preferEarlier: true,
            calendar: calendar,
            holidays: holidays
        )
        return PaySlice(
            shiftID: input.shiftID,
            workplaceID: input.workplaceID,
            workplaceName: input.workplaceName,
            day: input.day,
            minutes: max(0, input.minutes),
            baseYen: base,
            transportYen: max(0, input.transport),
            adjustmentYen: input.adjustment,
            payday: plan.payday
        )
    }

    static func groupedByPayday(_ slices: [PaySlice]) -> [(day: LocalDay, slices: [PaySlice])] {
        let days = Set(slices.map(\.payday)).sorted()
        return days.map { day in (day, slices.filter { $0.payday == day }) }
    }
}

struct WageChange: Equatable {
    var day: LocalDay
    var minutes: Int
}

enum WagePreview {
    /// The new rate applies on and after `day`. Older history rows stay as they are.
    static func note(
        day: LocalDay,
        yen: Int,
        shifts: [WageChange],
        history: [WagePoint],
        fallback: Int
    ) -> String {
        var count = 0
        var delta = 0
        for shift in shifts where shift.day >= day {
            count += 1
            let before = WageLookup.yen(on: shift.day, history: history, fallback: fallback)
            let oldYen = ExactYen.wage(yenPerHour: before, minutes: shift.minutes, rateBasisPoints: 10_000).roundedYen()
            let newYen = ExactYen.wage(yenPerHour: yen, minutes: shift.minutes, rateBasisPoints: 10_000).roundedYen()
            delta += newYen - oldYen
        }
        var text = "\(day.month)月\(day.day)日以降の勤務に \(Formatters.yen(yen)) を使用します。過去の時給は上書きしません。"
        if count > 0 {
            text += "既存のシフト\(count)件の見込みが \(signedYen(delta)) 変わります。"
        }
        return text
    }

    private static func signedYen(_ value: Int) -> String {
        value > 0 ? "+\(Formatters.yen(value))" : Formatters.yen(value)
    }
}
