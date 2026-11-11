import XCTest
@testable import ShiftTrack

final class ConfirmedFindingsTests: XCTestCase {
    private var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testLaunchWaitsWhenReturningAndSpringsOtherwise() {
        XCTAssertEqual(LaunchCover.motion(returnFlag: true), .hold(seconds: 0.8))
        XCTAssertEqual(
            LaunchCover.motion(returnFlag: false),
            .spring(response: 0.55, dampingFraction: 0.68, delay: 0.15)
        )
        let suite = UserDefaults(suiteName: "ConfirmedFindingsTests.launch")!
        suite.removePersistentDomain(forName: "ConfirmedFindingsTests.launch")
        XCTAssertFalse(LaunchCover.returnFlag(defaults: suite))
        LaunchCover.markReturn(defaults: suite)
        XCTAssertTrue(LaunchCover.returnFlag(defaults: suite))
        XCTAssertEqual(LaunchCover.motion(returnFlag: LaunchCover.returnFlag(defaults: suite)), .hold(seconds: 0.8))
    }

    func testWorkplaceEditorMessagesFollowTheRecoveredOrder() {
        let calendar = tokyo
        let first = day(2026, 11, 12, hour: 9)
        let laterSameDay = day(2026, 11, 12, hour: 22)
        let nextDay = day(2026, 11, 13)

        XCTAssertEqual(
            WorkplaceEditorCheck.message(name: "  \n", hourlyWage: -1, wageDates: [first, laterSameDay], payRuleDates: [first, first], calendar: calendar),
            WorkplaceEditorCheck.emptyName
        )
        XCTAssertEqual(
            WorkplaceEditorCheck.message(name: "架空茶房 北窓", hourlyWage: -1, wageDates: [first, laterSameDay], payRuleDates: [], calendar: calendar),
            WorkplaceEditorCheck.duplicateWageDate
        )
        XCTAssertEqual(
            WorkplaceEditorCheck.message(name: "架空茶房 北窓", hourlyWage: -1, wageDates: [first], payRuleDates: [first, laterSameDay], calendar: calendar),
            WorkplaceEditorCheck.duplicatePayRuleDate
        )
        XCTAssertEqual(
            WorkplaceEditorCheck.message(name: "架空茶房 北窓", hourlyWage: -1, wageDates: [first, nextDay], payRuleDates: [first], calendar: calendar),
            WorkplaceEditorCheck.negativeWage
        )
        XCTAssertNil(
            WorkplaceEditorCheck.message(name: "架空茶房 北窓", hourlyWage: 0, wageDates: [first, nextDay], payRuleDates: [first], calendar: calendar)
        )
        XCTAssertNil(
            WorkplaceEditorCheck.message(name: "架空茶房 北窓", hourlyWage: nil, wageDates: [], payRuleDates: [], calendar: calendar)
        )
        XCTAssertNil(
            WorkplaceEditorCheck.message(name: "架空茶房 北窓", hourlyWage: 1200, wageDates: [first], payRuleDates: [first], calendar: calendar)
        )
    }

    func testSignedYenKeepsALeadingMinus() {
        XCTAssertEqual(WorkplaceEditorCheck.signedYen("-1200"), -1200)
        XCTAssertEqual(WorkplaceEditorCheck.signedYen("−1200"), -1200)
        XCTAssertEqual(WorkplaceEditorCheck.signedYen("－50"), -50)
        XCTAssertEqual(WorkplaceEditorCheck.signedYen("1200"), 1200)
        XCTAssertEqual(WorkplaceEditorCheck.signedYen(""), 0)
        XCTAssertEqual(WorkplaceEditorCheck.signedYen("-"), 0)
        XCTAssertEqual(WorkplaceEditorCheck.signedYen("  1,200円"), 1200)
    }

    func testLocationRequestRunsOnlyWhenTheFlagIsNonzero() {
        XCTAssertFalse(WhenInUseLocation.shouldRequest(flag: 0))
        XCTAssertTrue(WhenInUseLocation.shouldRequest(flag: 1))
        XCTAssertTrue(WhenInUseLocation.shouldRequest(flag: -1))
    }

    func testShiftRequestMonthFetchesKindZeroAndKindOne() {
        let calendar = tokyo
        let december = day(2026, 12, 15)
        let month = ShiftRequestLists.month(containing: december, calendar: calendar)
        XCTAssertEqual(month?.start, day(2026, 12, 1))
        XCTAssertEqual(month?.end, day(2027, 1, 1))

        let leap = ShiftRequestLists.month(containing: day(2024, 2, 29, hour: 23), calendar: calendar)
        XCTAssertEqual(leap?.start, day(2024, 2, 1))
        XCTAssertEqual(leap?.end, day(2024, 3, 1))

        let yearEnd = ShiftRequestLists.month(containing: day(2026, 12, 31, hour: 23, minute: 59), calendar: calendar)!
        let nextYear = ShiftRequestLists.month(containing: day(2027, 1, 1), calendar: calendar)!
        XCTAssertEqual(yearEnd.end, nextYear.start)

        let items = [
            ShiftRequestLists.Item(id: UUID(), date: day(2026, 11, 30, hour: 23), kind: 0),
            ShiftRequestLists.Item(id: UUID(), date: day(2026, 12, 1), kind: 0),
            ShiftRequestLists.Item(id: UUID(), date: day(2026, 12, 20, hour: 18), kind: 1),
            ShiftRequestLists.Item(id: UUID(), date: day(2026, 12, 25), kind: 2),
            ShiftRequestLists.Item(id: UUID(), date: day(2026, 12, 31, hour: 23, minute: 30), kind: 0),
            ShiftRequestLists.Item(id: UUID(), date: day(2027, 1, 1), kind: 1),
        ]
        let pair = ShiftRequestLists.split(items, month: yearEnd)
        XCTAssertEqual(pair.attendance.map(\.date), [day(2026, 12, 1), day(2026, 12, 31, hour: 23, minute: 30)])
        XCTAssertEqual(pair.rest.map(\.date), [day(2026, 12, 20, hour: 18)])
        XCTAssertEqual(ShiftRequestKind.hopedAttendance, 0)
        XCTAssertEqual(ShiftRequestKind.hopedRest, 1)
    }
}
