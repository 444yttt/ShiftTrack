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
}
