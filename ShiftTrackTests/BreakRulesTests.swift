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
        XCTAssertEqual(workplace.roundingUnitMinutes, 1)
        XCTAssertEqual(workplace.roundingStartRaw, 0)
        XCTAssertEqual(workplace.roundingEndRaw, 0)
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

    func testScaledBreakAndRoundingMatchThePublicRecord() {
        let calendar = calendar()
        let start = day(2026, 11, 8, 9, 0)
        let end = start.addingTimeInterval(8 * 3600)
        let halfway = start.addingTimeInterval(4 * 3600)
        XCTAssertEqual(InOutRecovered.liveAsOf(now: halfway, shiftEnd: end), halfway)
        XCTAssertEqual(InOutRecovered.liveAsOf(now: end.addingTimeInterval(3600), shiftEnd: end), end)
        XCTAssertEqual(InOutRecovered.liveAsOf(now: end, shiftEnd: end), end)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: halfway, breakMinutes: 60), 30)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: start, breakMinutes: 60), 0)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: end, breakMinutes: 60), 60)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: start, asOf: start, breakMinutes: 60), 0)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: end, end: start, asOf: halfway, breakMinutes: 60), 0)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: start.addingTimeInterval(30), breakMinutes: 60), 0)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: start.addingTimeInterval(240), breakMinutes: 60), 1)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: start.addingTimeInterval(-4 * 3600), breakMinutes: 60), -30)
        XCTAssertEqual(InOutRecovered.scaledBreakMinutes(start: start, end: end, asOf: start.addingTimeInterval(-3600), breakMinutes: 60), -8)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(450, unitMinutes: 0, direction: .up), 450)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(450, unitMinutes: 1, direction: .nearest), 450)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(450, unitMinutes: -5, direction: .up), 450)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(450, unitMinutes: 15, direction: .exact), 450)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(450, unitMinutes: 15, direction: .nearest), 900)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(449, unitMinutes: 15, direction: .nearest), 0)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(1, unitMinutes: 15, direction: .up), 900)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(899, unitMinutes: 15, direction: .down), 0)
        XCTAssertEqual(InOutRecovered.roundedSecondsFromStartOfDay(-450, unitMinutes: 15, direction: .nearest), -900)
        let dayStart = calendar.startOfDay(for: start)
        let sample = dayStart.addingTimeInterval(450)
        let rounded = InOutRecovered.roundedDate(sample, unitMinutes: 15, direction: .nearest, calendar: calendar)
        XCTAssertEqual(rounded.timeIntervalSince(dayStart), 900)
        let endRounded = InOutRecovered.roundedDate(dayStart.addingTimeInterval(899), unitMinutes: 15, direction: .down, calendar: calendar)
        XCTAssertEqual(endRounded.timeIntervalSince(dayStart), 0)
        XCTAssertNotEqual(rounded, endRounded)
    }

    func testLiveScaleDoesNotInventYenAndLaterNowChangesTheBreak() {
        let calendar = calendar()
        let workplace = place(wage: 1200, transport: 500)
        let shiftDay = day(2026, 11, 8)
        let start = day(2026, 11, 8, 9, 0)
        let halfway = start.addingTimeInterval(4 * 3600)
        let after = start.addingTimeInterval(9 * 3600)
        let before = start.addingTimeInterval(-4 * 3600)
        XCTAssertEqual(
            LivePay.phase(now: before, day: shiftDay, start: 9 * 60, end: 17 * 60, breakMinutes: 60, workplace: workplace, calendar: calendar),
            .beforeStart(remainingMinutes: 240)
        )
        XCTAssertFalse(LivePay.line(.beforeStart(remainingMinutes: 240)).contains("円"))
        XCTAssertFalse(LivePay.breakCaption(.beforeStart(remainingMinutes: 240)).contains("-30"))
        XCTAssertEqual(
            LivePay.phase(now: start, day: shiftDay, start: 9 * 60, end: 17 * 60, breakMinutes: 60, workplace: workplace, calendar: calendar),
            .during(scaledBreak: 0, scheduledBreak: 60, remainingMinutes: 8 * 60)
        )
        XCTAssertEqual(
            LivePay.phase(now: halfway, day: shiftDay, start: 9 * 60, end: 17 * 60, breakMinutes: 60, workplace: workplace, calendar: calendar),
            .during(scaledBreak: 30, scheduledBreak: 60, remainingMinutes: 4 * 60)
        )
        XCTAssertEqual(
            LivePay.phase(now: after, day: shiftDay, start: 9 * 60, end: 17 * 60, breakMinutes: 60, workplace: workplace, calendar: calendar),
            .afterEnd(scaledBreak: 60, scheduledBreak: 60)
        )
        let during = LivePay.line(.during(scaledBreak: 30, scheduledBreak: 60, remainingMinutes: 240))
        XCTAssertTrue(during.contains("給与の目安"))
        XCTAssertTrue(during.contains("円は出していません"))
        let quote = PayMath.quote(
            workplace: workplace,
            day: shiftDay,
            start: 9 * 60,
            end: 17 * 60,
            breakMinutes: 60,
            customPay: nil,
            adjustment: 0,
            includeTransport: true,
            calendar: calendar
        )
        workplace.roundingUnitMinutes = 15
        workplace.roundingStartRaw = 3
        workplace.roundingEndRaw = 1
        XCTAssertEqual(
            PayMath.quote(
                workplace: workplace,
                day: shiftDay,
                start: 9 * 60,
                end: 17 * 60,
                breakMinutes: 60,
                customPay: nil,
                adjustment: 0,
                includeTransport: true,
                calendar: calendar
            ),
            quote
        )
        let stored = WorkShift(date: shiftDay, startMinutes: 9 * 60, endMinutes: 17 * 60, breakMinutes: 60, workplace: workplace)
        XCTAssertEqual(stored.startMinutes, 9 * 60)
        XCTAssertEqual(stored.endMinutes, 17 * 60)
    }

    func testOvernightAfterEndAndTwoWorkplacesStayIndependent() {
        let calendar = calendar()
        let first = place()
        let second = place()
        let shiftDay = day(2026, 11, 8)
        let midway = day(2026, 11, 9, 2, 0)
        let after = day(2026, 11, 9, 7, 0)
        XCTAssertEqual(
            LivePay.phase(now: midway, day: shiftDay, start: 22 * 60, end: 6 * 60, breakMinutes: 60, workplace: first, calendar: calendar),
            .during(scaledBreak: 30, scheduledBreak: 60, remainingMinutes: 4 * 60)
        )
        XCTAssertEqual(
            LivePay.phase(now: after, day: shiftDay, start: 22 * 60, end: 6 * 60, breakMinutes: 60, workplace: first, calendar: calendar),
            .afterEnd(scaledBreak: 60, scheduledBreak: 60)
        )
        let other = LivePay.phase(
            now: midway,
            day: shiftDay,
            start: 10 * 60,
            end: 12 * 60,
            breakMinutes: 0,
            workplace: second,
            calendar: calendar
        )
        XCTAssertEqual(other, .afterEnd(scaledBreak: 0, scheduledBreak: 0))
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
