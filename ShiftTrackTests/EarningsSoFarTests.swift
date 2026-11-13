import XCTest
@testable import ShiftTrack

/// Live “earnings so far” on the home screen. An empty wage history still
/// pays `Workplace.hourlyWage` for the time already worked.
final class EarningsSoFarTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// Noon on a calendar day. `WorkShift` stores `Calendar.current.startOfDay`,
    /// and noon keeps that the same day whether the simulator runs in UTC or JST.
    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        at(year, month, day, 12)
    }

    /// The fictional demo store. Empty wage history, like every workplace made
    /// in the editor or by import.
    private func store(wage: Int = 1_200) -> Workplace {
        Workplace(name: "架空茶房 北窓", colorHex: "C6F24E", hourlyWage: wage, transportAllowance: 300)
    }

    func testHourlyWageIsAppliedWhenTheWageHistoryIsEmpty() throws {
        let place = store(wage: 1_200)
        XCTAssertTrue(place.wageHistory.isEmpty)
        let day = noon(2026, 11, 12)
        let now = at(2026, 11, 12, 12, 30)

        let progress = try XCTUnwrap(EarningsSoFar.progress(
            workplace: place, day: day, start: 10 * 60, end: 15 * 60, breakMinutes: 0,
            now: now, calendar: calendar
        ))
        XCTAssertTrue(progress.isWorking)
        XCTAssertEqual(progress.earnedYen, 3_000) // 2.5 h × ¥1,200
        XCTAssertEqual(progress.wageTotalYen, 6_000)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
        if case .working(let elapsed, let remaining) = progress.phase {
            XCTAssertEqual(elapsed, 2.5 * 3_600, accuracy: 0.5)
            XCTAssertEqual(remaining, 2.5 * 3_600, accuracy: 0.5)
        } else {
            XCTFail("expected working")
        }
    }

    func testBeforeStartIsZeroAndAfterTheEndIsTheShiftWage() throws {
        let place = store(wage: 1_200)
        let day = noon(2026, 11, 12)
        let before = try XCTUnwrap(EarningsSoFar.progress(
            workplace: place, day: day, start: 10 * 60, end: 15 * 60, breakMinutes: 0,
            now: at(2026, 11, 12, 9, 0), calendar: calendar
        ))
        XCTAssertEqual(before.earnedYen, 0)
        XCTAssertEqual(before.phase, .upcoming(startsIn: 3_600))

        let after = try XCTUnwrap(EarningsSoFar.progress(
            workplace: place, day: day, start: 10 * 60, end: 15 * 60, breakMinutes: 0,
            now: at(2026, 11, 12, 15, 0), calendar: calendar
        ))
        XCTAssertEqual(after.phase, .finished)
        let quote = PayMath.quote(
            workplace: place, day: day, start: 10 * 60, end: 15 * 60, breakMinutes: 0,
            customPay: nil, adjustment: 0, includeTransport: false, calendar: calendar
        )
        XCTAssertEqual(after.earnedYen, quote)
        XCTAssertEqual(after.earnedYen, 6_000)
    }

    func testBreakIsSpreadOverTheShift() throws {
        let place = store(wage: 1_000)
        let progress = try XCTUnwrap(EarningsSoFar.progress(
            workplace: place, day: noon(2026, 11, 12), start: 9 * 60, end: 17 * 60, breakMinutes: 60,
            now: at(2026, 11, 12, 13, 0), calendar: calendar
        ))
        // Half of 7 paid hours.
        XCTAssertEqual(progress.earnedYen, 3_500)
        XCTAssertEqual(progress.wageTotalYen, 7_000)
    }

    func testAnOvernightShiftFromYesterdayIsFoundAndEarns() throws {
        let place = store(wage: 1_000)
        let shift = WorkShift(
            date: noon(2026, 11, 11),
            startMinutes: 22 * 60,
            endMinutes: 5 * 60,
            breakMinutes: 0,
            workplace: place
        )
        let now = at(2026, 11, 12, 1, 0)
        let running = try XCTUnwrap(EarningsSoFar.current(in: [shift], now: now, calendar: calendar))
        XCTAssertEqual(running.uuid, shift.uuid)
        let rows = HomeFocus.shifts(on: noon(2026, 11, 12), from: [shift], now: now, calendar: calendar)
        XCTAssertEqual(rows.map(\.uuid), [shift.uuid])
        XCTAssertEqual(HomeFocus.tickSeconds(shifts: [shift], now: now, calendar: calendar), 1)
        let progress = try XCTUnwrap(EarningsSoFar.progress(for: shift, now: now, calendar: calendar))
        XCTAssertEqual(progress.earnedYen, 3_000)
        XCTAssertEqual(progress.wageTotalYen, 7_000)
    }

    func testNightPremiumSwitchedOnWithoutAnAmountNeverPaysZero() throws {
        // What the old setup wizard stored: night pay on, 25%, night wage 0.
        let place = store(wage: 1_000)
        place.nightPayEnabled = true
        place.nightWage = 0
        place.nightRatePercent = 25
        let day = noon(2026, 11, 12)
        let quote = PayMath.quote(
            workplace: place, day: day, start: 22 * 60, end: 2 * 60, breakMinutes: 0,
            customPay: nil, adjustment: 0, includeTransport: false, calendar: calendar
        )
        XCTAssertEqual(quote, 5_000) // 4 h × ¥1,250
        let progress = try XCTUnwrap(EarningsSoFar.progress(
            workplace: place, day: day, start: 22 * 60, end: 2 * 60, breakMinutes: 0,
            now: at(2026, 11, 13, 0, 0), calendar: calendar
        ))
        XCTAssertEqual(progress.earnedYen, 2_500)

        place.nightWage = 1_300
        XCTAssertEqual(PayMath.quote(
            workplace: place, day: day, start: 22 * 60, end: 2 * 60, breakMinutes: 0,
            customPay: nil, adjustment: 0, includeTransport: false, calendar: calendar
        ), 5_200)
    }

    func testPayPeriodPartsUseTheHourlyWageInsteadOfAnEmptyHistory() {
        let place = store(wage: 1_000)
        place.nightPayEnabled = true
        place.nightWage = 0
        place.nightRatePercent = 25
        let shift = WorkShift(date: noon(2026, 11, 12), startMinutes: 22 * 60, endMinutes: 2 * 60, breakMinutes: 0, workplace: place)
        let parts = PayMath.wageParts(shift, calendar: calendar)
        XCTAssertEqual(parts.base, 4_000)
        XCTAssertEqual(parts.premium, 1_000)
        XCTAssertEqual(parts.base + parts.premium, shift.estimatedYen(includeTransport: false))
    }

    func testOvertimePercentIsAddedWhenNoYenAmountIsSet() {
        let place = store(wage: 1_000)
        place.overtimeEnabled = true
        place.overtimeAfterMinutes = 480
        place.overtimeExtra = 0
        place.overtimeRatePercent = 25
        let quote = PayMath.quote(
            workplace: place, day: noon(2026, 11, 12), start: 9 * 60, end: 18 * 60, breakMinutes: 0,
            customPay: nil, adjustment: 0, includeTransport: false, calendar: calendar
        )
        XCTAssertEqual(quote, 9_250)
    }

    func testEarningsRiseEverySecondAndStopAtTheShiftWage() throws {
        let place = store(wage: 3_600) // ¥1 per second
        let day = noon(2026, 11, 12)
        var previous = -1
        for second in stride(from: 0, through: 120, by: 1) {
            let now = at(2026, 11, 12, 10, 0, 0).addingTimeInterval(TimeInterval(second))
            let progress = try XCTUnwrap(EarningsSoFar.progress(
                workplace: place, day: day, start: 10 * 60, end: 11 * 60, breakMinutes: 0,
                now: now, calendar: calendar
            ))
            XCTAssertGreaterThanOrEqual(progress.earnedYen, previous)
            XCTAssertLessThanOrEqual(progress.earnedYen, progress.wageTotalYen)
            XCTAssertEqual(progress.earnedYen, second)
            previous = progress.earnedYen
        }
    }

    func testDailyWageAndCustomPayAccrueWithTime() throws {
        let daily = store()
        daily.payIsDaily = true
        daily.dailyWage = 8_000
        let day = noon(2026, 11, 12)
        let progress = try XCTUnwrap(EarningsSoFar.progress(
            workplace: daily, day: day, start: 9 * 60, end: 17 * 60, breakMinutes: 60,
            now: at(2026, 11, 12, 13, 0), calendar: calendar
        ))
        XCTAssertEqual(progress.earnedYen, 4_000)

        let custom = try XCTUnwrap(EarningsSoFar.progress(
            workplace: store(), day: day, start: 9 * 60, end: 17 * 60, breakMinutes: 0, customPay: 10_000,
            now: at(2026, 11, 12, 11, 0), calendar: calendar
        ))
        XCTAssertEqual(custom.earnedYen, 2_500)
    }

    func testTheClockTicksEverySecondOnlyWhileAShiftRuns() {
        let place = store()
        let shift = WorkShift(date: noon(2026, 11, 12), startMinutes: 10 * 60, endMinutes: 15 * 60, breakMinutes: 0, workplace: place)
        XCTAssertEqual(HomeFocus.tickSeconds(shifts: [shift], now: at(2026, 11, 12, 9, 59), calendar: calendar), 30)
        XCTAssertEqual(HomeFocus.tickSeconds(shifts: [shift], now: at(2026, 11, 12, 10, 0), calendar: calendar), 1)
        XCTAssertEqual(HomeFocus.tickSeconds(shifts: [shift], now: at(2026, 11, 12, 15, 0), calendar: calendar), 30)
    }

    func testQuickActionsFollowTheShiftInProgressThenTheNextOne() {
        let first = store()
        let second = Workplace(name: "架空書店 南口", colorHex: "A9C7F5", hourlyWage: 1_100, transportAllowance: 0)
        let morning = WorkShift(date: noon(2026, 11, 12), startMinutes: 9 * 60, endMinutes: 12 * 60, breakMinutes: 0, workplace: first)
        let evening = WorkShift(date: noon(2026, 11, 12), startMinutes: 17 * 60, endMinutes: 21 * 60, breakMinutes: 0, workplace: second)
        let rows = [morning, evening]
        XCTAssertEqual(HomeFocus.workplace(rows: rows, fallback: [], now: at(2026, 11, 12, 10, 0), calendar: calendar)?.name, "架空茶房 北窓")
        XCTAssertEqual(HomeFocus.workplace(rows: rows, fallback: [], now: at(2026, 11, 12, 13, 0), calendar: calendar)?.name, "架空書店 南口")
        XCTAssertEqual(HomeFocus.workplace(rows: [], fallback: [second], now: at(2026, 11, 12, 13, 0), calendar: calendar)?.name, "架空書店 南口")
    }
}
