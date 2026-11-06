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
        self.createdAt = createdAt
        self.shifts = []
    }

    var color: Color { Color(hexString: colorHex) }
}

@Model
final class WorkShift {
    var uuid: UUID
    var date: Date
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var notes: String
    var workplace: Workplace?

    init(
        date: Date,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int,
        notes: String = "",
        workplace: Workplace?
    ) {
        self.uuid = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.breakMinutes = breakMinutes
        self.notes = notes
        self.workplace = workplace
    }

    var workedMinutes: Int {
        PayMath.workedMinutes(start: startMinutes, end: endMinutes, breakMinutes: breakMinutes)
    }

    func estimatedYen(includeTransport: Bool) -> Int {
        guard let workplace else { return 0 }
        return PayMath.yen(
            hourlyWage: workplace.hourlyWage,
            transport: workplace.transportAllowance,
            minutes: workedMinutes,
            includeTransport: includeTransport
        )
    }

    func hasEnded(now: Date = .now, calendar: Calendar = .current) -> Bool {
        PayMath.endDate(day: date, start: startMinutes, end: endMinutes, calendar: calendar) <= now
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

    init(
        weekStartsOnMonday: Bool = false,
        includeTransport: Bool = true,
        defaultHourlyWage: Int = 1_200,
        defaultTransportAllowance: Int = 500,
        annualIncomeGoal: Int = 1_000_000
    ) {
        self.weekStartsOnMonday = weekStartsOnMonday
        self.includeTransport = includeTransport
        self.defaultHourlyWage = defaultHourlyWage
        self.defaultTransportAllowance = defaultTransportAllowance
        self.annualIncomeGoal = annualIncomeGoal
    }
}
