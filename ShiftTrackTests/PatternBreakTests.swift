import SwiftData
import XCTest
@testable import ShiftTrack

final class PatternBreakTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func place(daily: Bool = false, custom: Bool = false, rules: [InOutRecovered.BreakRule] = []) -> Workplace {
        let place = Workplace(name: "架空茶房 北窓", colorHex: "C6F24E", hourlyWage: 1200, transportAllowance: 0)
        place.payIsDaily = daily
        place.dailyWage = daily ? 8000 : 0
        place.customBreaks = custom
        place.breakRules = rules
        return place
    }

    func testFixedModeUsesItsMinutesAndClamps() {
        let normal = PatternBreak.resolve(
            modeRaw: PatternBreakMode.fixed.rawValue, fixedMinutes: 45, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(normal, PatternBreak.Result(minutes: 45, followsRules: false))
        let clamped = PatternBreak.resolve(
            modeRaw: PatternBreakMode.fixed.rawValue, fixedMinutes: 9_999, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(clamped.minutes, 600)
        let none = PatternBreak.resolve(
            modeRaw: PatternBreakMode.fixed.rawValue, fixedMinutes: 0, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(none.minutes, 0)
    }

    func testWorkplaceModeFollowsTheLegalTableAndKeepsFollowing() {
        let long = PatternBreak.resolve(
            modeRaw: PatternBreakMode.workplace.rawValue, fixedMinutes: 0, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(long, PatternBreak.Result(minutes: 60, followsRules: true))
        let exactlySix = PatternBreak.resolve(
            modeRaw: PatternBreakMode.workplace.rawValue, fixedMinutes: 0, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 15 * 60, workplace: place()
        )
        XCTAssertEqual(exactlySix.minutes, 0)
        let missing = PatternBreak.resolve(
            modeRaw: PatternBreakMode.workplace.rawValue, fixedMinutes: 30, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: nil
        )
        XCTAssertEqual(missing, PatternBreak.Result(minutes: 0, followsRules: false))
    }

    func testWorkplaceModeUsesTheWorkplacesOwnRulesWhenCustom() {
        let shop = place(custom: true, rules: [.init(overMinutes: 240, breakMinutes: 15)])
        let result = PatternBreak.resolve(
            modeRaw: PatternBreakMode.workplace.rawValue, fixedMinutes: 0, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 15 * 60, workplace: shop
        )
        XCTAssertEqual(result, PatternBreak.Result(minutes: 15, followsRules: true))
    }

    func testCustomModeUsesThePatternsOwnRulesNotTheWorkplaces() {
        let raw = BreakRules.encode([.init(overMinutes: 300, breakMinutes: 20), .init(overMinutes: 480, breakMinutes: 50)])
        let six = PatternBreak.resolve(
            modeRaw: PatternBreakMode.custom.rawValue, fixedMinutes: 99, customRulesRaw: raw,
            startMinutes: 9 * 60, endMinutes: 15 * 60, workplace: place()
        )
        XCTAssertEqual(six, PatternBreak.Result(minutes: 20, followsRules: false))
        let nine = PatternBreak.resolve(
            modeRaw: PatternBreakMode.custom.rawValue, fixedMinutes: 99, customRulesRaw: raw,
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(nine.minutes, 50)
        let empty = PatternBreak.resolve(
            modeRaw: PatternBreakMode.custom.rawValue, fixedMinutes: 99, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(empty.minutes, 0)
    }

    func testDailyPayNeverGetsABreakAndUnknownModeIsFixed() {
        for mode in PatternBreakMode.allCases {
            let result = PatternBreak.resolve(
                modeRaw: mode.rawValue, fixedMinutes: 60, customRulesRaw: "300:20",
                startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place(daily: true)
            )
            XCTAssertEqual(result, PatternBreak.Result(minutes: 0, followsRules: false))
        }
        let unknown = PatternBreak.resolve(
            modeRaw: 42, fixedMinutes: 30, customRulesRaw: "",
            startMinutes: 9 * 60, endMinutes: 18 * 60, workplace: place()
        )
        XCTAssertEqual(unknown.minutes, 30)
    }

    func testSummaryLines() {
        XCTAssertEqual(PatternBreak.summary(modeRaw: 0, fixedMinutes: 0, customRulesRaw: ""), "休憩なし")
        XCTAssertEqual(PatternBreak.summary(modeRaw: 0, fixedMinutes: 45, customRulesRaw: ""), "休憩 45分")
        XCTAssertEqual(PatternBreak.summary(modeRaw: 1, fixedMinutes: 0, customRulesRaw: ""), "休憩は勤務先の決まりどおり")
        XCTAssertTrue(PatternBreak.summary(modeRaw: 2, fixedMinutes: 0, customRulesRaw: "300:20,480:50").contains("2件"))
    }

    /// Rows saved before the break fields existed read the defaults, which
    /// reproduce the old behaviour (no break). This is what lightweight
    /// migration hands an old store.
    func testPatternsWithoutBreakFieldsKeepTheOldBehaviour() throws {
        let part = ShiftPart(name: "朝", workplaceUUID: UUID(), startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertEqual(part.breakModeRaw, PatternBreakMode.fixed.rawValue)
        XCTAssertEqual(part.breakMinutes, 0)
        XCTAssertEqual(part.breakRulesRaw, "")
        let pattern = ShiftPattern(
            name: "平日", workplaceUUID: UUID(), startMinutes: 9 * 60, endMinutes: 17 * 60,
            breakMinutes: 60, weekdays: [2, 3]
        )
        XCTAssertEqual(pattern.breakModeRaw, PatternBreakMode.fixed.rawValue)
        XCTAssertEqual(pattern.breakMinutes, 60)
        XCTAssertEqual(pattern.breakRulesRaw, "")
    }

    @MainActor
    func testEditedPatternBreakIsStoredAndPlacedOnTheShift() throws {
        let container = try ModelContainer(
            for: Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self, ShiftPart.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let shop = place()
        context.insert(shop)
        let part = ShiftPart(name: "朝", workplaceUUID: shop.uuid, startMinute: 9 * 60, endMinute: 18 * 60)
        context.insert(part)
        try context.save()

        // Edit the saved pattern: it now follows the workplace's rules.
        part.name = "朝番"
        part.breakModeRaw = PatternBreakMode.workplace.rawValue
        try context.save()
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<ShiftPart>()).first)
        XCTAssertEqual(stored.name, "朝番")
        XCTAssertEqual(stored.breakModeRaw, PatternBreakMode.workplace.rawValue)

        let placed = ShiftPartCommit.apply(
            part: stored, days: [day(2026, 11, 12)], shifts: [], workplaces: [shop], context: context, calendar: calendar()
        )
        let shift = try XCTUnwrap(placed.inserted.first)
        XCTAssertEqual(shift.breakMinutes, 60)
        XCTAssertTrue(shift.breakFollowsRules)

        // 「取り消す」 removes exactly what the tap added.
        ShiftPartCommit.undo(placed.inserted, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkShift>()).isEmpty)

        // Deleting the pattern never touches shifts already placed.
        let again = ShiftPartCommit.apply(
            part: stored, days: [day(2026, 11, 13)], shifts: [], workplaces: [shop], context: context, calendar: calendar()
        )
        XCTAssertEqual(again.inserted.count, 1)
        context.delete(stored)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkShift>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShiftPart>()).isEmpty)
    }
}
