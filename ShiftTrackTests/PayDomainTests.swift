import Foundation
import Testing
@testable import ShiftTrack

struct PayDomainTests {
    private static var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    @Test(arguments: [
        (2026, 2, 0, 28),
        (2026, 2, 31, 28),
        (2024, 2, 31, 29),
        (2026, 11, 15, 15),
    ])
    func closingDayClampsToTheMonth(year: Int, month: Int, requested: Int, expected: Int) {
        #expect(PayScheduleMath.clampedDay(requested, year: year, month: month, calendar: Self.tokyo) == expected)
    }

    @Test
    func oneMinuteRoundsHalfAwayFromZeroOnce() {
        let exact = ExactYen.wage(yenPerHour: 1000, minutes: 1, rateBasisPoints: 10_000)
        #expect(exact.roundedYen() == 17)
        #expect(ExactYen.wage(yenPerHour: 1200, minutes: 60, rateBasisPoints: 10_000).roundedYen() == 1200)
        #expect(ExactYen.wage(yenPerHour: 1200, minutes: 30, rateBasisPoints: 2_500).roundedYen() == 150)
    }

    @Test
    func wageOnADayUsesTheLatestEditOfThatDay() {
        let april = LocalDay(year: 2026, month: 4, day: 1)
        let october = LocalDay(year: 2026, month: 10, day: 1)
        let history = [
            WagePoint(day: october, yen: 1600),
            WagePoint(day: april, yen: 1500),
            WagePoint(day: october, yen: 1650),
        ]
        #expect(WageLookup.yen(on: LocalDay(year: 2026, month: 3, day: 31), history: history, fallback: 1200) == 1200)
        #expect(WageLookup.yen(on: april, history: history, fallback: 1200) == 1500)
        #expect(WageLookup.yen(on: october, history: history, fallback: 1200) == 1650)
        #expect(WageLookup.yen(on: LocalDay(year: 2026, month: 12, day: 1), history: history, fallback: 1200) == 1650)
    }

    @Test
    func saturdayMovesEarlierUntilItWouldPassTheClosingDay() {
        let calendar = Self.tokyo
        let saturday = weekday(7, year: 2026, month: 11, onOrAfter: 8, calendar: calendar)
        let workday = LocalDay(year: 2026, month: 11, day: 1)
        let earlier = PayScheduleMath.plan(
            workday: workday,
            closingDay: 1,
            paydayDay: saturday,
            monthOffset: 0,
            preferEarlier: true,
            calendar: calendar
        )
        #expect(earlier.direction == .earlier)
        #expect(earlier.payday == LocalDay(year: 2026, month: 11, day: saturday).adding(days: -1, calendar: calendar))
        #expect(PayScheduleMath.isBusinessDay(earlier.payday, calendar: calendar, holidays: BankClosures()))

        let blocked = PayScheduleMath.plan(
            workday: workday,
            closingDay: saturday,
            paydayDay: saturday,
            monthOffset: 0,
            preferEarlier: true,
            calendar: calendar
        )
        #expect(blocked.direction == .later)
        #expect(blocked.payday > LocalDay(year: 2026, month: 11, day: saturday))
    }

    @Test
    func newYearPaydayMovesOffTheBankClosure() {
        let calendar = Self.tokyo
        let plan = PayScheduleMath.plan(
            workday: LocalDay(year: 2026, month: 12, day: 20),
            closingDay: 20,
            paydayDay: 3,
            monthOffset: 1,
            preferEarlier: true,
            calendar: calendar
        )
        #expect(plan.closing == LocalDay(year: 2026, month: 12, day: 20))
        #expect(plan.direction == .earlier)
        #expect(plan.payday < LocalDay(year: 2027, month: 1, day: 3))
        #expect(plan.payday > plan.closing)
        #expect(PayScheduleMath.isBusinessDay(plan.payday, calendar: calendar, holidays: BankClosures()))
    }

    @Test
    func movingEarlierPastTheClosingDayGoesLaterInstead() {
        let plan = PayScheduleMath.plan(
            workday: LocalDay(year: 2026, month: 12, day: 15),
            closingDay: 31,
            paydayDay: 3,
            monthOffset: 1,
            preferEarlier: true,
            calendar: Self.tokyo
        )
        #expect(plan.direction == .later)
        #expect(plan.payday > LocalDay(year: 2027, month: 1, day: 3))
        #expect(PayScheduleMath.isBusinessDay(plan.payday, calendar: Self.tokyo, holidays: BankClosures()))
    }

    @Test
    func februarySameMonthScheduleIsFlagged() {
        #expect(PayScheduleMath.breaksInShortFebruary(closingDay: 28, paydayDay: 30, monthOffset: 0, calendar: Self.tokyo))
        #expect(!PayScheduleMath.breaksInShortFebruary(closingDay: 15, paydayDay: 25, monthOffset: 1, calendar: Self.tokyo))
    }

    @Test
    func liveEarningsFloorAndIgnoreUntimedBreaks() {
        #expect(LiveEarnings.yen(elapsedSeconds: 3599, breakSeconds: 0, hourlyYen: 3600) == 3599)
        #expect(LiveEarnings.yen(elapsedSeconds: 3600, breakSeconds: 0, hourlyYen: 3600) == 3600)
        #expect(LiveEarnings.yen(elapsedSeconds: 7200, breakSeconds: 0, hourlyYen: 1200) == 2400)
        #expect(LiveEarnings.yen(elapsedSeconds: 3600, breakSeconds: 3600, hourlyYen: 1200) == 0)
        let before = LiveEarnings.yen(elapsedSeconds: 1000, breakSeconds: 0, hourlyYen: 1500)
        let after = LiveEarnings.yen(elapsedSeconds: 1001, breakSeconds: 0, hourlyYen: 1500)
        #expect(after >= before)
    }

    @Test
    func scheduleSentenceNamesTheClosingDayAndPayday() {
        let text = PayScheduleMath.sentence(closingDay: 0, paydayDay: 25, monthOffset: 1)
        #expect(text.contains("末日"))
        #expect(text.contains("翌月25日"))
    }

    private func weekday(_ weekday: Int, year: Int, month: Int, onOrAfter start: Int, calendar: Calendar) -> Int {
        for day in start...28 {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            if calendar.component(.weekday, from: date) == weekday { return day }
        }
        return start
    }
}
