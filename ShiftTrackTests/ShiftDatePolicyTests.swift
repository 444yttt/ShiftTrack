import XCTest
@testable import ShiftTrack

final class ShiftDatePolicyTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = calendar()
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!
    }

    func testSwipeAndCancelKeepStoredDate() {
        let calendar = calendar()
        let stored = day(2026, 11, 8)
        let otherMonth = day(2026, 12, 8)
        XCTAssertNil(
            ShiftDatePolicy.selectedDayAfterMonthChange(selected: stored, visibleMonth: otherMonth, calendar: calendar)
        )
        let kept = ShiftDatePolicy.dateToStore(
            existing: stored,
            draft: otherMonth,
            userEditedDate: false,
            calendar: calendar
        )
        XCTAssertEqual(kept, calendar.startOfDay(for: stored))
    }

    func testDateChangesOnlyWhenCommitted() {
        let calendar = calendar()
        let stored = day(2026, 11, 8)
        let picked = day(2026, 11, 20)
        let changed = ShiftDatePolicy.dateToStore(
            existing: stored,
            draft: picked,
            userEditedDate: true,
            calendar: calendar
        )
        XCTAssertEqual(changed, calendar.startOfDay(for: picked))
        XCTAssertNotEqual(changed, calendar.startOfDay(for: stored))
    }

    func testAddAnchorStaysAfterVisibleMonthChanges() {
        let calendar = calendar()
        let selected = day(2026, 11, 8)
        let anchor = ShiftDatePolicy.anchorDay(
            selectedDay: selected,
            visibleMonth: selected,
            now: day(2026, 11, 3),
            calendar: calendar
        )
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: selected)!
        XCTAssertNil(
            ShiftDatePolicy.selectedDayAfterMonthChange(selected: selected, visibleMonth: nextMonth, calendar: calendar)
        )
        XCTAssertEqual(anchor, calendar.startOfDay(for: selected))
        let newShift = ShiftDatePolicy.dateToStore(existing: nil, draft: anchor, userEditedDate: false, calendar: calendar)
        XCTAssertEqual(newShift, calendar.startOfDay(for: selected))
    }

    func testTimeSheetCancelAndCommitDoNotUseADate() {
        XCTAssertEqual(
            ShiftDatePolicy.minutesAfterDismiss(original: 10 * 60, draft: 18 * 60, committed: false),
            10 * 60
        )
        XCTAssertEqual(
            ShiftDatePolicy.minutesAfterDismiss(original: 22 * 60, draft: 25 * 60, committed: true),
            60
        )
        let clock = ShiftDatePolicy.clockDate(minutes: 22 * 60 + 15, calendar: calendar())
        let parts = calendar().dateComponents([.year, .month, .day, .hour, .minute], from: clock)
        XCTAssertEqual(parts.year, 2001)
        XCTAssertEqual(parts.month, 1)
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(parts.hour, 22)
        XCTAssertEqual(parts.minute, 15)
    }

    func testOvernightAndBreakStayOnTheSameStoredDay() {
        let calendar = calendar()
        let stored = calendar.startOfDay(for: day(2026, 11, 8))
        XCTAssertEqual(ShiftDatePolicy.breakToStore(payIsDaily: true, minutes: 60), 0)
        XCTAssertEqual(ShiftDatePolicy.breakToStore(payIsDaily: false, minutes: 60), 60)
        XCTAssertEqual(ShiftDatePolicy.clampedBreak(-15, range: 0...600), 0)
        XCTAssertEqual(ShiftDatePolicy.clampedBreak(615, range: 0...600), 600)
        XCTAssertEqual(PayMath.workedMinutes(start: 22 * 60, end: 5 * 60, breakMinutes: 45), 7 * 60 - 45)
        let end = PayMath.endDate(day: stored, start: 22 * 60, end: 5 * 60, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: stored), 8)
        XCTAssertEqual(calendar.component(.day, from: end), 9)
        XCTAssertEqual(
            ShiftDatePolicy.dateToStore(existing: stored, draft: end, userEditedDate: false, calendar: calendar),
            stored
        )
    }

    func testImportFallbackKeepsItsDateWhenTimesChange() {
        let calendar = calendar()
        let fallback = day(2026, 11, 8)
        let overnight = ShiftTextParser.parse(
            text: "22:00-5:00 休憩45分",
            now: fallback,
            calendar: calendar,
            fallbackDate: fallback,
            defaultWorkplace: "カフェ"
        )
        XCTAssertEqual(overnight.count, 1)
        XCTAssertEqual(overnight[0].year, 2026)
        XCTAssertEqual(overnight[0].month, 11)
        XCTAssertEqual(overnight[0].day, 8)
        XCTAssertEqual(overnight[0].startMinutes, 22 * 60)
        XCTAssertEqual(overnight[0].endMinutes, 5 * 60)
        XCTAssertEqual(overnight[0].breakMinutes, 45)

        let explicit = ShiftTextParser.parse(
            text: "11/2 10:00-15:00",
            now: fallback,
            calendar: calendar,
            fallbackDate: fallback,
            defaultWorkplace: "カフェ"
        )
        XCTAssertEqual(explicit.count, 1)
        XCTAssertEqual(explicit[0].day, 2)
        XCTAssertEqual(explicit[0].startMinutes, 10 * 60)
        XCTAssertEqual(explicit[0].endMinutes, 15 * 60)
    }

    func testRecoveredMinuteNormalizationStaysInsideOneDay() {
        let calendar = calendar()
        XCTAssertEqual(ShiftDatePolicy.clockMinutes(-15), 23 * 60 + 45)
        XCTAssertEqual(Formatters.clock(-15), "23:45")
        XCTAssertEqual(ShiftDatePolicy.clockMinutes(25 * 60), 60)
        for minutes in [0, 23 * 60 + 59, -1440, 1440] {
            let clock = ShiftDatePolicy.clockDate(minutes: minutes, calendar: calendar)
            let parts = calendar.dateComponents([.year, .month, .day], from: clock)
            XCTAssertEqual(parts.year, 2001)
            XCTAssertEqual(parts.month, 1)
            XCTAssertEqual(parts.day, 1)
        }
        let stored = day(2026, 11, 8)
        let clock = ShiftDatePolicy.clockDate(minutes: 22 * 60, calendar: calendar)
        XCTAssertNotEqual(calendar.component(.day, from: clock), calendar.component(.day, from: stored))
        XCTAssertEqual(
            ShiftDatePolicy.dateToStore(existing: stored, draft: clock, userEditedDate: false, calendar: calendar),
            calendar.startOfDay(for: stored)
        )
    }

    func testNewWorkplaceKeepsRecoveredTimesWithoutTurningPremiumsOn() {
        let place = Workplace(name: "店", colorHex: "C8FF00", hourlyWage: 1200, transportAllowance: 0)
        XCTAssertEqual(place.nightStartMinutes, InOutRecovered.defaultNightStartMinute)
        XCTAssertEqual(place.nightEndMinutes, InOutRecovered.defaultNightEndMinute)
        XCTAssertEqual(place.overtimeAfterMinutes, InOutRecovered.defaultOvertimeThresholdMinutes)
        XCTAssertFalse(place.nightPayEnabled)
        XCTAssertFalse(place.overtimeEnabled)
        XCTAssertFalse(place.holidayPayEnabled)
        XCTAssertEqual(place.nightWage, 0)
        XCTAssertNotEqual(place.nightWage, InOutRecovered.defaultNightRatePercent)
        XCTAssertEqual(place.overtimeExtra, 0)
        let shift = WorkShift(
            date: day(2026, 11, 8),
            startMinutes: 9 * 60,
            endMinutes: 18 * 60,
            breakMinutes: 0,
            workplace: place
        )
        XCTAssertEqual(shift.breakMinutes, 0)
        XCTAssertFalse(InOutRecovered.legalBreakRules.map(\.breakMinutes).contains(shift.breakMinutes))
        let calendar = calendar()
        let yen = PayMath.quote(
            workplace: place,
            day: shift.date,
            start: 23 * 60,
            end: 60,
            breakMinutes: 0,
            customPay: nil,
            adjustment: 0,
            includeTransport: false,
            calendar: calendar
        )
        XCTAssertEqual(yen, (1200 * 120 + 30) / 60)
    }

    func testDayAdditionsDoNotMoveTheVisibleMonthOrStoredDate() {
        let calendar = calendar()
        let stored = calendar.startOfDay(for: day(2026, 11, 8))
        let window = InOutRecovered.dayWindow(around: stored, calendar: calendar)
        XCTAssertEqual(window.previous, calendar.date(byAdding: .day, value: -1, to: stored))
        XCTAssertEqual(window.twoAhead, calendar.date(byAdding: .day, value: 2, to: stored))
        let offsets = InOutRecovered.dayOffsets(from: stored, calendar: calendar)
        XCTAssertEqual(offsets.ahead, calendar.date(byAdding: .day, value: 14, to: stored))
        XCTAssertEqual(
            ShiftDatePolicy.dateToStore(existing: stored, draft: window.twoAhead!, userEditedDate: false, calendar: calendar),
            stored
        )
        XCTAssertNil(
            ShiftDatePolicy.selectedDayAfterMonthChange(
                selected: stored,
                visibleMonth: offsets.ahead!,
                calendar: calendar
            )
        )
        let month = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))!
        let cells = CalendarGrid.days(in: month, weekStartsOnMonday: false, calendar: calendar)
        let days = cells.compactMap { $0 }
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(calendar.component(.day, from: days[0]), 1)
        XCTAssertEqual(calendar.component(.day, from: days[29]), 30)
        XCTAssertTrue(days.allSatisfy { calendar.component(.month, from: $0) == 11 })
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let february = InOutRecovered.addingDays(1, to: calendar.startOfDay(for: january), calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: february!), 2)
        XCTAssertEqual(calendar.component(.day, from: february!), 1)
    }
}
