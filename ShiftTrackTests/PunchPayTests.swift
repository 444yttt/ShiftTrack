import Foundation
import Testing
@testable import ShiftTrack

struct PunchPayTests {
    @Test
    func sixtyMinuteRoundingUsesTheWallClockInAHalfHourZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let clockIn = date(calendar, year: 2026, month: 11, day: 11, hour: 10, minute: 7)
        let clockOut = date(calendar, year: 2026, month: 11, day: 11, hour: 18, minute: 4)
        let planned = date(calendar, year: 2026, month: 11, day: 11, hour: 10, minute: 0)
        let view = PunchPay.payable(
            plannedStart: planned,
            clockIn: clockIn,
            clockOut: clockOut,
            unitMinutes: 60,
            start: .down,
            end: .down,
            earlyCountsFromPlan: false,
            calendar: calendar
        )
        #expect(PunchPay.clock(view.payableStart, calendar: calendar) == "10:00")
        #expect(PunchPay.clock(view.payableEnd, calendar: calendar) == "18:00")
        let unixStart = Date(timeIntervalSince1970: (clockIn.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        #expect(PunchPay.clock(unixStart, calendar: calendar) == "9:30")
        #expect(view.payableStart != unixStart)
        #expect(view.shorterThanPunch)
    }

    @Test
    func earlyClockInCanCountFromThePlannedStart() {
        let calendar = ShiftOverlap.tokyo
        let planned = date(calendar, year: 2026, month: 11, day: 11, hour: 10, minute: 0)
        let clockIn = date(calendar, year: 2026, month: 11, day: 11, hour: 9, minute: 50)
        let clockOut = date(calendar, year: 2026, month: 11, day: 11, hour: 18, minute: 0)
        let held = PunchPay.payable(
            plannedStart: planned,
            clockIn: clockIn,
            clockOut: clockOut,
            unitMinutes: 15,
            start: .down,
            end: .exact,
            earlyCountsFromPlan: true,
            calendar: calendar
        )
        let raw = PunchPay.payable(
            plannedStart: planned,
            clockIn: clockIn,
            clockOut: clockOut,
            unitMinutes: 15,
            start: .down,
            end: .exact,
            earlyCountsFromPlan: false,
            calendar: calendar
        )
        #expect(PunchPay.clock(held.payableStart, calendar: calendar) == "10:00")
        #expect(PunchPay.clock(raw.payableStart, calendar: calendar) == "9:45")
        #expect(held.payableMinutes < raw.payableMinutes)
        let line = PunchPay.line(clockIn: clockIn, clockOut: clockOut, payable: held, calendar: calendar)
        #expect(line.contains("予定の給料は変えていません"))
        #expect(line.contains("丸めた時間は打刻より短いです"))
    }

    private func date(_ calendar: Calendar, year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
