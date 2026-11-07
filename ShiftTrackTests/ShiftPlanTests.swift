import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import ShiftTrack

final class ShiftPlanTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func place() -> Workplace {
        let place = Workplace(name: "店", colorHex: "C8FF00", hourlyWage: 1000, transportAllowance: 0)
        place.closingDay = 15
        place.paydayMonthOffset = 1
        place.paydayDay = 25
        return place
    }

    func testMonthPayKeepsTheExistingPayday() {
        let calendar = calendar()
        let workplace = place()
        XCTAssertEqual(workplace.payCycle, .month)
        XCTAssertEqual(workplace.payWeekday, 0)
        for shiftDay in [day(2026, 11, 10), day(2026, 11, 20)] {
            XCTAssertEqual(
                PaySchedule.payday(for: shiftDay, workplace: workplace, calendar: calendar),
                PayMath.payday(for: shiftDay, workplace: workplace, calendar: calendar)
            )
        }
        let mark = day(2026, 12, 25)
        XCTAssertTrue(PaySchedule.showsMark(on: mark, workplace: workplace, hasShiftThatDay: false, calendar: calendar))
        XCTAssertFalse(PaySchedule.showsMark(on: day(2026, 12, 24), workplace: workplace, hasShiftThatDay: true, calendar: calendar))
    }

    func testWeekAndDayPayApplyOnlyAfterTheCycleChanges() {
        let calendar = calendar()
        let workplace = place()
        let wednesday = day(2026, 11, 4)
        let saturday = day(2026, 11, 7)
        XCTAssertEqual(calendar.component(.weekday, from: wednesday), 4)
        XCTAssertEqual(calendar.component(.weekday, from: saturday), 7)
        workplace.payCycle = .week
        workplace.payWeekday = 0
        XCTAssertEqual(
            PaySchedule.payday(for: wednesday, workplace: workplace, calendar: calendar),
            PayMath.payday(for: wednesday, workplace: workplace, calendar: calendar)
        )
        workplace.payWeekday = 6
        XCTAssertEqual(PaySchedule.payday(for: wednesday, workplace: workplace, calendar: calendar), day(2026, 11, 6))
        XCTAssertEqual(PaySchedule.payday(for: saturday, workplace: workplace, calendar: calendar), day(2026, 11, 13))
        XCTAssertTrue(PaySchedule.showsMark(on: day(2026, 11, 6), workplace: workplace, hasShiftThatDay: false, calendar: calendar))
        XCTAssertFalse(PaySchedule.showsMark(on: wednesday, workplace: workplace, hasShiftThatDay: true, calendar: calendar))
        workplace.payCycle = .day
        XCTAssertEqual(PaySchedule.payday(for: saturday, workplace: workplace, calendar: calendar), saturday)
        XCTAssertFalse(PaySchedule.showsMark(on: saturday, workplace: workplace, hasShiftThatDay: false, calendar: calendar))
        XCTAssertTrue(PaySchedule.showsMark(on: saturday, workplace: workplace, hasShiftThatDay: true, calendar: calendar))
        let yen = PayMath.quote(
            workplace: workplace, day: wednesday, start: 9 * 60, end: 17 * 60,
            breakMinutes: 0, customPay: nil, adjustment: 0, includeTransport: false, calendar: calendar
        )
        XCTAssertEqual(yen, (1000 * 480 + 30) / 60)
    }

    func testPatternSkipsAnExistingWorkplaceDayAndLeavesItsTimes() {
        let calendar = calendar()
        let workplace = place()
        let other = UUID()
        let occupied = [
            ShiftPatternPlan.Occupied(day: day(2026, 11, 4), workplaceID: workplace.uuid),
            ShiftPatternPlan.Occupied(day: day(2026, 11, 5), workplaceID: other)
        ]
        let result = ShiftPatternPlan.proposals(
            workplaceID: workplace.uuid,
            startMinutes: 10 * 60,
            endMinutes: 19 * 60,
            breakMinutes: 45,
            from: day(2026, 11, 2),
            through: day(2026, 11, 8),
            weekdays: [2, 3, 4, 5, 6],
            occupied: occupied,
            allowEqualClock: false,
            calendar: calendar
        )
        XCTAssertFalse(result.blockedEqualClock)
        XCTAssertEqual(result.skippedExisting, 1)
        XCTAssertEqual(result.create.map(\.day), [day(2026, 11, 2), day(2026, 11, 3), day(2026, 11, 5), day(2026, 11, 6)])
        XCTAssertTrue(result.create.allSatisfy { $0.breakMinutes == 45 && $0.startMinutes == 10 * 60 && $0.endMinutes == 19 * 60 })
        let storedBreak = 15
        let storedStart = 9 * 60
        XCTAssertNotEqual(storedBreak, result.create.first?.breakMinutes)
        XCTAssertEqual(storedStart, 9 * 60)
    }

    func testEqualClockAndLongRangeCreateNothing() {
        let calendar = calendar()
        let workplace = place()
        let equal = ShiftPatternPlan.proposals(
            workplaceID: workplace.uuid,
            startMinutes: 9 * 60,
            endMinutes: 9 * 60,
            breakMinutes: 0,
            from: day(2026, 11, 2),
            through: day(2026, 11, 8),
            weekdays: [2],
            occupied: [],
            allowEqualClock: false,
            calendar: calendar
        )
        XCTAssertTrue(equal.blockedEqualClock)
        XCTAssertTrue(equal.create.isEmpty)
        let daily = ShiftPatternPlan.proposals(
            workplaceID: workplace.uuid,
            startMinutes: 9 * 60,
            endMinutes: 9 * 60,
            breakMinutes: 0,
            from: day(2026, 11, 2),
            through: day(2026, 11, 2),
            weekdays: [2],
            occupied: [],
            allowEqualClock: true,
            calendar: calendar
        )
        XCTAssertEqual(daily.create.count, 1)
        XCTAssertNil(ShiftPatternPlan.spanDays(from: day(2026, 11, 8), through: day(2026, 11, 2), calendar: calendar))
        XCTAssertNil(ShiftPatternPlan.spanDays(from: day(2026, 1, 1), through: day(2027, 1, 2), calendar: calendar))
        let none = ShiftPatternPlan.proposals(
            workplaceID: workplace.uuid,
            startMinutes: 9 * 60,
            endMinutes: 18 * 60,
            breakMinutes: 0,
            from: day(2026, 11, 2),
            through: day(2026, 11, 8),
            weekdays: [],
            occupied: [],
            allowEqualClock: false,
            calendar: calendar
        )
        XCTAssertTrue(none.create.isEmpty)
        XCTAssertFalse(none.blockedEqualClock)
    }

    @MainActor
    func testApplyingDoesNotRewriteTheStoredShiftOrCountARequest() throws {
        let calendar = calendar()
        let container = try ModelContainer(
            for: Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let workplace = place()
        context.insert(workplace)
        let existing = WorkShift(
            date: day(2026, 11, 4),
            startMinutes: 9 * 60,
            endMinutes: 13 * 60,
            breakMinutes: 15,
            workplace: workplace
        )
        context.insert(existing)
        let request = ShiftRequest(
            date: day(2026, 11, 5),
            startMinutes: 9 * 60,
            endMinutes: 12 * 60,
            breakMinutes: 0,
            workplaceUUID: workplace.uuid
        )
        context.insert(request)
        let beforeYen = existing.estimatedYen(includeTransport: false)
        let beforePay = PaySchedule.payday(for: existing.date, workplace: workplace)
        XCTAssertEqual(beforePay, PayMath.payday(for: existing.date, workplace: workplace))
        let result = ShiftPatternPlan.proposals(
            workplaceID: workplace.uuid,
            startMinutes: 18 * 60,
            endMinutes: 22 * 60,
            breakMinutes: 30,
            from: day(2026, 11, 2),
            through: day(2026, 11, 6),
            weekdays: [2, 3, 4, 5, 6],
            occupied: [ShiftPatternPlan.Occupied(day: existing.date, workplaceID: workplace.uuid)],
            allowEqualClock: false,
            calendar: calendar
        )
        for proposal in result.create {
            context.insert(WorkShift(
                date: proposal.day,
                startMinutes: proposal.startMinutes,
                endMinutes: proposal.endMinutes,
                breakMinutes: proposal.breakMinutes,
                breakFollowsRules: false,
                workplace: workplace
            ))
        }
        let shifts = try context.fetch(FetchDescriptor<WorkShift>())
        let snapshots = ShiftMapping.snapshots(shifts, includeTransport: false)
        XCTAssertEqual(existing.startMinutes, 9 * 60)
        XCTAssertEqual(existing.endMinutes, 13 * 60)
        XCTAssertEqual(existing.breakMinutes, 15)
        XCTAssertFalse(existing.breakFollowsRules)
        XCTAssertEqual(existing.estimatedYen(includeTransport: false), beforeYen)
        XCTAssertEqual(snapshots.first { $0.id == existing.uuid }?.payDate, beforePay)
        XCTAssertEqual(snapshots.count, shifts.count)
        XCTAssertFalse(snapshots.contains { $0.date == request.date && $0.minutes == 180 })
        XCTAssertTrue(request.isOpen)
        XCTAssertEqual(result.skippedExisting, 1)
        XCTAssertFalse(result.create.contains { calendar.isDate($0.day, inSameDayAs: existing.date) })
    }

    @MainActor
    func testCalendarAndPatternScreensRender() throws {
        let container = try ModelContainer(
            for: Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        context.insert(AppSettings())
        let workplace = place()
        context.insert(workplace)
        context.insert(ShiftRequest(
            date: day(2026, 11, 7),
            startMinutes: 10 * 60,
            endMinutes: 15 * 60,
            breakMinutes: 0,
            note: "入れてほしい",
            workplaceUUID: workplace.uuid
        ))
        context.insert(ShiftPattern(
            name: "早番",
            workplaceUUID: workplace.uuid,
            startMinutes: 9 * 60,
            endMinutes: 15 * 60,
            breakMinutes: 45,
            weekdays: [2, 3, 4, 5, 6]
        ))
        try context.save()
        let calendarView = CalendarScreen()
            .modelContainer(container)
            .frame(width: 390, height: 844)
            .preferredColorScheme(.dark)
        let patternView = PatternListView()
            .modelContainer(container)
            .frame(width: 390, height: 844)
            .preferredColorScheme(.dark)
        let calendarImage = ImageRenderer(content: calendarView).uiImage
        let patternImage = ImageRenderer(content: patternView).uiImage
        let calendarAttachment = XCTAttachment(image: calendarImage ?? UIImage())
        calendarAttachment.name = "calendar-with-request"
        calendarAttachment.lifetime = .keepAlways
        add(calendarAttachment)
        let patternAttachment = XCTAttachment(image: patternImage ?? UIImage())
        patternAttachment.name = "pattern-list"
        patternAttachment.lifetime = .keepAlways
        add(patternAttachment)
        XCTAssertNotNil(calendarImage)
        XCTAssertNotNil(patternImage)
        XCTAssertGreaterThan(calendarImage?.size.width ?? 0, 100)
        XCTAssertGreaterThan(patternImage?.size.width ?? 0, 100)
    }
}
