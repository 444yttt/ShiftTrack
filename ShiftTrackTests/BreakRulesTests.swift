import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import ShiftTrack

final class BreakRulesTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func place(wage: Int = 1200, transport: Int = 0, daily: Bool = false) -> Workplace {
        let place = Workplace(name: "店", colorHex: "C8FF00", hourlyWage: wage, transportAllowance: transport)
        place.payIsDaily = daily
        place.dailyWage = daily ? 8000 : 0
        return place
    }

    func testLegalBreakBoundariesAndTies() {
        let legal = InOutRecovered.legalBreakRules
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(360, rules: legal), 0)
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(361, rules: legal), 45)
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(480, rules: legal), 45)
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(481, rules: legal), 60)
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(0, rules: legal), 0)
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(-5, rules: legal), 0)
        XCTAssertEqual(InOutRecovered.selectedBreakMinutes(50, rules: []), 0)
        XCTAssertEqual(
            InOutRecovered.selectedBreakMinutes(101, rules: [
                .init(overMinutes: 100, breakMinutes: 10),
                .init(overMinutes: 100, breakMinutes: 99),
            ]),
            10
        )
    }

    func testEqualClockMinutesStayRejectedWhileRecoveredCountIs24Hours() {
        XCTAssertEqual(InOutRecovered.editorMinuteCount(startMinute: 100, endMinute: 100), 1440)
        XCTAssertEqual(BreakRules.selectionMinutes(start: 100, end: 100), 0)
        XCTAssertEqual(
            BreakRules.automaticMinutes(start: 10 * 60, end: 10 * 60, customBreaks: false, rules: []),
            0
        )
        XCTAssertEqual(PayMath.workedMinutes(start: 10 * 60, end: 10 * 60, breakMinutes: 0), 0)
    }

    func testOvernightUsesEditorCountAndNotA24HourEqual() {
        XCTAssertEqual(BreakRules.selectionMinutes(start: 22 * 60, end: 6 * 60), 8 * 60)
        XCTAssertEqual(
            BreakRules.automaticMinutes(start: 22 * 60, end: 6 * 60, customBreaks: false, rules: []),
            45
        )
        XCTAssertEqual(
            BreakRules.automaticMinutes(start: 22 * 60, end: 6 * 60 + 1, customBreaks: false, rules: []),
            60
        )
        XCTAssertEqual(InOutRecovered.editorMinuteCount(startMinute: 22 * 60, endMinute: 6 * 60), 8 * 60)
    }

    func testCustomRulesApplyOnlyWhenEnabled() {
        let custom = [InOutRecovered.BreakRule(overMinutes: 1, breakMinutes: 99)]
        XCTAssertEqual(
            BreakRules.automaticMinutes(start: 10 * 60, end: 18 * 60, customBreaks: false, rules: custom),
            45
        )
        XCTAssertEqual(
            BreakRules.automaticMinutes(start: 10 * 60, end: 18 * 60, customBreaks: true, rules: custom),
            99
        )
        XCTAssertEqual(
            BreakRules.automaticMinutes(start: 10 * 60, end: 18 * 60, customBreaks: true, rules: []),
            0
        )
        XCTAssertEqual(
            BreakRules.automaticMinutes(
                start: 9 * 60,
                end: 20 * 60,
                customBreaks: true,
                rules: [.init(overMinutes: 1, breakMinutes: 900)]
            ),
            600
        )
    }

    func testManualBreakAndExistingShiftStayPut() {
        XCTAssertEqual(
            BreakRules.minutesForEditor(
                payIsDaily: false,
                followsRules: false,
                manualMinutes: 15,
                start: 9 * 60,
                end: 18 * 60,
                customBreaks: false,
                rules: []
            ),
            15
        )
        let existing = WorkShift(
            date: day(2026, 11, 8),
            startMinutes: 9 * 60,
            endMinutes: 18 * 60,
            breakMinutes: 15,
            workplace: place()
        )
        XCTAssertFalse(existing.breakFollowsRules)
        XCTAssertEqual(existing.breakMinutes, 15)
        let workplace = place()
        XCTAssertFalse(workplace.customBreaks)
        XCTAssertTrue(workplace.breakRules.isEmpty)
        workplace.breakRules = [.init(overMinutes: 360, breakMinutes: 45), .init(overMinutes: 100, breakMinutes: 10)]
        XCTAssertEqual(BreakRules.decode(workplace.breakRulesRaw).map(\.breakMinutes), [45, 10])
        XCTAssertEqual(existing.breakMinutes, 15)
    }

    func testTextAndImportKeepExplicitBreaks() {
        let explicit = BreakRules.textDecision(
            breakIsExplicit: true,
            explicitMinutes: 60,
            payIsDaily: false,
            customBreaks: false,
            rules: [],
            start: 10 * 60,
            end: 12 * 60
        )
        XCTAssertEqual(explicit.minutes, 60)
        XCTAssertFalse(explicit.followsRules)
        let writtenZero = BreakRules.textDecision(
            breakIsExplicit: true,
            explicitMinutes: 0,
            payIsDaily: false,
            customBreaks: false,
            rules: [],
            start: 10 * 60,
            end: 19 * 60
        )
        XCTAssertEqual(writtenZero.minutes, 0)
        XCTAssertFalse(writtenZero.followsRules)
        let missing = BreakRules.textDecision(
            breakIsExplicit: false,
            explicitMinutes: 0,
            payIsDaily: false,
            customBreaks: false,
            rules: [],
            start: 10 * 60,
            end: 18 * 60
        )
        XCTAssertEqual(missing.minutes, 45)
        XCTAssertTrue(missing.followsRules)
        let daily = BreakRules.textDecision(
            breakIsExplicit: false,
            explicitMinutes: 0,
            payIsDaily: true,
            customBreaks: false,
            rules: [],
            start: 10 * 60,
            end: 18 * 60
        )
        XCTAssertEqual(daily.minutes, 0)
        XCTAssertFalse(daily.followsRules)

        let calendar = calendar()
        let parsed = ShiftTextParser.parse(
            text: "11/8 カフェ 10:00-18:00\n11/8 カフェ 10:00-12:00 休憩0分\n11/8 カフェ 22:00-6:00 休憩30分",
            now: day(2026, 11, 8),
            calendar: calendar,
            fallbackDate: day(2026, 11, 8),
            defaultWorkplace: "カフェ"
        )
        XCTAssertEqual(parsed.count, 3)
        XCTAssertFalse(parsed[0].breakIsExplicit)
        XCTAssertEqual(parsed[0].breakMinutes, 0)
        XCTAssertTrue(parsed[1].breakIsExplicit)
        XCTAssertEqual(parsed[1].breakMinutes, 0)
        XCTAssertTrue(parsed[2].breakIsExplicit)
        XCTAssertEqual(parsed[2].breakMinutes, 30)
    }

    func testPendingImportWithoutTheNewFlagStaysManual() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","workplaceName":"店","createWorkplace":true,"date":0,"startMinutes":600,"endMinutes":900,"breakMinutes":20,"included":true}
        """.data(using: .utf8)!
        let candidate = try JSONDecoder().decode(ImportCandidate.self, from: json)
        XCTAssertEqual(candidate.breakMinutes, 20)
        XCTAssertFalse(candidate.breakFollowsRules)
    }

    func testWeekMoveDoesNotRewriteAStoredShiftDate() {
        let calendar = calendar()
        let stored = calendar.startOfDay(for: day(2026, 11, 8))
        let viewed = WeekPage.day(byAddingWeeks: 1, to: stored, calendar: calendar)
        XCTAssertEqual(viewed, calendar.date(from: DateComponents(year: 2026, month: 11, day: 15)))
        XCTAssertEqual(
            ShiftDatePolicy.dateToStore(existing: stored, draft: viewed, userEditedDate: false, calendar: calendar),
            stored
        )
        XCTAssertEqual(WeekPage.day(byAddingWeeks: -1, to: stored, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    }

    func testLivePayUsesExistingMinuteRatesAndLeavesFullQuoteAlone() {
        let calendar = calendar()
        let workplace = place(wage: 1200, transport: 500)
        let start = day(2026, 11, 8, 10, 0)
        let at30 = day(2026, 11, 8, 10, 30)
        let atEnd = day(2026, 11, 8, 12, 0)
        let before = day(2026, 11, 8, 9, 50)
        XCTAssertEqual(
            LivePay.phase(now: before, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 0, workplace: workplace, calendar: calendar),
            .beforeStart(remainingMinutes: 10)
        )
        XCTAssertEqual(
            LivePay.phase(now: start, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 0, workplace: workplace, calendar: calendar),
            .working(earnedYen: 0, remainingMinutes: 120, inUnpaidTail: false)
        )
        XCTAssertEqual(
            LivePay.phase(now: at30, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 0, workplace: workplace, calendar: calendar),
            .working(earnedYen: 600, remainingMinutes: 90, inUnpaidTail: false)
        )
        XCTAssertEqual(
            LivePay.phase(now: atEnd, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 0, workplace: workplace, calendar: calendar),
            .finished(earnedYen: 2400)
        )
        let full = PayMath.quote(
            workplace: workplace,
            day: start,
            start: 10 * 60,
            end: 12 * 60,
            breakMinutes: 0,
            customPay: nil,
            adjustment: 0,
            includeTransport: true,
            calendar: calendar
        )
        XCTAssertEqual(full, 2400 + 500)
        let untouched = PayMath.quote(
            workplace: workplace,
            day: start,
            start: 9 * 60,
            end: 18 * 60,
            breakMinutes: 0,
            customPay: nil,
            adjustment: 0,
            includeTransport: false,
            calendar: calendar
        )
        XCTAssertEqual(untouched, (1200 * 540 + 30) / 60)
    }

    func testUnpaidBreakIsTheTailNotARecoveredBreakClock() {
        let calendar = calendar()
        let workplace = place()
        let start = day(2026, 11, 8, 10, 0)
        let at90 = day(2026, 11, 8, 11, 30)
        let at100 = day(2026, 11, 8, 11, 40)
        let end = day(2026, 11, 8, 12, 0)
        XCTAssertEqual(
            LivePay.phase(now: at90, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 30, workplace: workplace, calendar: calendar),
            .working(earnedYen: 1800, remainingMinutes: 30, inUnpaidTail: false)
        )
        XCTAssertEqual(
            LivePay.phase(now: at100, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 30, workplace: workplace, calendar: calendar),
            .working(earnedYen: 1800, remainingMinutes: 20, inUnpaidTail: true)
        )
        XCTAssertEqual(
            LivePay.phase(now: end, day: start, start: 10 * 60, end: 12 * 60, breakMinutes: 30, workplace: workplace, calendar: calendar),
            .finished(earnedYen: 1800)
        )
    }

    func testDailyAndCustomPayAreNotSplitByTheSecond() {
        let calendar = calendar()
        let daily = place(daily: true)
        let midway = day(2026, 11, 8, 11, 0)
        let phase = LivePay.phase(
            now: midway,
            day: day(2026, 11, 8),
            start: 10 * 60,
            end: 18 * 60,
            breakMinutes: 0,
            workplace: daily,
            calendar: calendar
        )
        XCTAssertEqual(phase, .working(earnedYen: 8000, remainingMinutes: 7 * 60, inUnpaidTail: false))
        let customPlace = place()
        let custom = LivePay.phase(
            now: midway,
            day: day(2026, 11, 8),
            start: 10 * 60,
            end: 18 * 60,
            breakMinutes: 0,
            workplace: customPlace,
            customPay: 3000,
            calendar: calendar
        )
        XCTAssertEqual(custom, .working(earnedYen: 3000, remainingMinutes: 7 * 60, inUnpaidTail: false))
    }

    @MainActor
    func testTodayScreenRenders() throws {
        let container = try ModelContainer(
            for: Schema([Workplace.self, WorkShift.self, AppSettings.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let view = TodayScreen()
            .modelContainer(container)
            .frame(width: 390, height: 844)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = renderer.uiImage
        let attachment = XCTAttachment(image: image ?? UIImage())
        attachment.name = "today-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 100)
    }
}
