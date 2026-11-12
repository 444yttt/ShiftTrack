import SwiftData
import XCTest
@testable import ShiftTrack

final class ShiftPartPlaceTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testPatternMinuteTableMatchesTheRecoveredDivision() {
        let cases: [(Int, Int, Int)] = [
            (0, 0, 0),
            (59, 0, 59),
            (60, 1, 0),
            (1439, 23, 59),
            (1500, 1, 0),
            (-1, 23, 59),
            (-1440, 0, 0),
            (-1441, 23, 59),
            (22 * 60, 22, 0),
            (5 * 60, 5, 0),
        ]
        for item in cases {
            let clock = ShiftPartPlace.clock(item.0)
            XCTAssertEqual(clock.hour, item.1, "hour \(item.0)")
            XCTAssertEqual(clock.minute, item.2, "minute \(item.0)")
        }
        XCTAssertFalse(InOutRecovered.patternEndAddsOneDay(startMinute: 9 * 60, endMinute: 17 * 60))
        XCTAssertTrue(InOutRecovered.patternEndAddsOneDay(startMinute: 22 * 60, endMinute: 5 * 60))
        XCTAssertTrue(InOutRecovered.patternEndAddsOneDay(startMinute: 10 * 60, endMinute: 10 * 60))
        XCTAssertTrue(InOutRecovered.patternEndAddsOneDay(startMinute: 1500, endMinute: 60))
        XCTAssertFalse(InOutRecovered.patternEndAddsOneDay(startMinute: 60, endMinute: 1500))
        XCTAssertFalse(InOutRecovered.patternEndAddsOneDay(startMinute: -1, endMinute: 0))
    }

    func testResolvedClocksHaveZeroSecondsAndRollWhenStartIsAtLeastEnd() {
        let calendar = calendar()
        let day = day(2026, 11, 11)
        let same = ShiftPartPlace.resolvedDates(day: day, startMinute: 9 * 60, endMinute: 17 * 60, calendar: calendar)
        XCTAssertEqual(same?.start.minutes, 9 * 60)
        XCTAssertEqual(same?.end.minutes, 17 * 60)
        XCTAssertEqual(same?.endAddsOneDay, false)
        XCTAssertEqual(calendar.component(.second, from: same!.start.date), 0)
        XCTAssertEqual(calendar.component(.second, from: same!.end.date), 0)
        XCTAssertTrue(calendar.isDate(same!.start.date, inSameDayAs: day))
        XCTAssertTrue(calendar.isDate(same!.end.date, inSameDayAs: day))
        XCTAssertEqual(calendar.component(.hour, from: same!.end.date), 17)

        let night = ShiftPartPlace.resolvedDates(day: day, startMinute: 22 * 60, endMinute: 5 * 60, calendar: calendar)
        XCTAssertEqual(night?.endAddsOneDay, true)
        XCTAssertEqual(night?.start.minutes, 22 * 60)
        XCTAssertEqual(night?.end.minutes, 5 * 60)
        XCTAssertEqual(calendar.component(.second, from: night!.end.date), 0)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        XCTAssertTrue(calendar.isDate(night!.end.date, inSameDayAs: next))
        XCTAssertEqual(calendar.component(.hour, from: night!.start.date), 22)
        XCTAssertEqual(calendar.component(.hour, from: night!.end.date), 5)

        let equal = ShiftPartPlace.resolvedDates(day: day, startMinute: 10 * 60, endMinute: 10 * 60, calendar: calendar)
        XCTAssertEqual(equal?.endAddsOneDay, true)
        XCTAssertEqual(equal?.start.minutes, 10 * 60)
        XCTAssertEqual(equal?.end.minutes, 10 * 60)
        XCTAssertTrue(calendar.isDate(equal!.end.date, inSameDayAs: next))
        XCTAssertEqual(calendar.component(.second, from: equal!.start.date), 0)
        XCTAssertEqual(calendar.component(.minute, from: equal!.end.date), 0)
    }

    func testEmptyClashPlacesAndSkipsTheSamePartWithoutCopyingBreakOrTodosDone() {
        let calendar = calendar()
        let day = day(2026, 11, 11)
        let other = self.day(2026, 11, 12)
        let part = UUID()
        let workplace = UUID()
        let sourceTodo = ShiftTodoCodec.Item(id: UUID(), title: "レジ", done: true)
        let placed = ShiftPartPlace.outcome(
            partID: part,
            workplaceID: workplace,
            startMinute: 9 * 60,
            endMinute: 18 * 60,
            todos: [sourceTodo],
            days: [day, day, other],
            existing: [ShiftPartPlace.Existing(day: other, partID: part)],
            calendar: calendar
        )
        guard case .placed(let drafts) = placed else {
            return XCTFail("expected place")
        }
        XCTAssertEqual(drafts.map { $0.day }, [day])
        XCTAssertEqual(drafts[0].breakMinutes, 0)
        XCTAssertFalse(drafts[0].breakFollowsRules)
        XCTAssertEqual(drafts[0].startMinutes, 9 * 60)
        XCTAssertEqual(drafts[0].endMinutes, 18 * 60)
        XCTAssertFalse(drafts[0].endAddsOneDay)
        XCTAssertEqual(drafts[0].todos.map { $0.title }, ["レジ"])
        XCTAssertEqual(drafts[0].todos.map { $0.done }, [false])
        XCTAssertNotEqual(drafts[0].todos[0].id, sourceTodo.id)
        XCTAssertNotEqual(drafts[0].breakMinutes, 45)
        XCTAssertNotEqual(drafts[0].breakMinutes, 60)
    }

    func testClashHoldsEveryDayAndASamePartDayDoesNotClash() {
        let calendar = calendar()
        let blocked = day(2026, 11, 11)
        let open = day(2026, 11, 12)
        let part = UUID()
        let other = UUID()
        let pending = ShiftPartPlace.outcome(
            partID: part,
            workplaceID: UUID(),
            startMinute: 10 * 60,
            endMinute: 15 * 60,
            todos: [],
            days: [blocked, open],
            existing: [
                ShiftPartPlace.Existing(day: blocked, partID: nil),
                ShiftPartPlace.Existing(day: open, partID: other),
            ],
            calendar: calendar
        )
        guard case .pending(let hold) = pending else {
            return XCTFail("expected pending")
        }
        XCTAssertEqual(hold.partID, part)
        XCTAssertEqual(hold.days, [blocked, open])
        XCTAssertEqual(hold.clashes, [ShiftPartPlace.clashText, ShiftPartPlace.clashText])

        let again = ShiftPartPlace.outcome(
            partID: part,
            workplaceID: UUID(),
            startMinute: 10 * 60,
            endMinute: 15 * 60,
            todos: [],
            days: [blocked],
            existing: [
                ShiftPartPlace.Existing(day: blocked, partID: part),
                ShiftPartPlace.Existing(day: blocked, partID: other),
            ],
            calendar: calendar
        )
        guard case .placed(let skipped) = again else {
            return XCTFail("same part skips without a clash")
        }
        XCTAssertTrue(skipped.isEmpty)
    }

    func testMissingWorkplaceInsertsNothing() {
        let outcome = ShiftPartPlace.outcome(
            partID: UUID(),
            workplaceID: nil,
            startMinute: 22 * 60,
            endMinute: 5 * 60,
            todos: [],
            days: [day(2026, 11, 11)],
            existing: [],
            calendar: calendar()
        )
        guard case .missingWorkplace = outcome else {
            return XCTFail("expected missing workplace")
        }
    }

    @MainActor
    func testApplyLeavesTheStoredShiftAndSkipsLegalBreak() throws {
        // WorkShift stores Calendar.current.startOfDay. A fixed Tokyo date
        // moves to the previous civil day on a UTC runner, so the repeat
        // no longer sees the part it just saved.
        let calendar = Calendar.current
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = 12
            return calendar.date(from: parts)!
        }
        let container = try ModelContainer(
            for: Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self, ShiftPart.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let workplace = Workplace(name: "店", colorHex: "C8FF00", hourlyWage: 1000, transportAllowance: 0)
        context.insert(workplace)
        let stored = WorkShift(
            date: day(2026, 11, 4),
            startMinutes: 9 * 60,
            endMinutes: 13 * 60,
            breakMinutes: 15,
            notes: "残す",
            workplace: workplace
        )
        context.insert(stored)
        let part = ShiftPart(
            name: "朝",
            workplaceUUID: workplace.uuid,
            startMinute: 9 * 60,
            endMinute: 17 * 60,
            breakMinutes: 45
        )
        let blocked = ShiftPartCommit.apply(
            part: part,
            days: [stored.date, day(2026, 11, 5)],
            shifts: [stored],
            workplaces: [workplace],
            context: context,
            calendar: calendar
        )
        guard case .pending = blocked.outcome else {
            return XCTFail("pending")
        }
        XCTAssertEqual(stored.startMinutes, 9 * 60)
        XCTAssertEqual(stored.endMinutes, 13 * 60)
        XCTAssertEqual(stored.breakMinutes, 15)
        XCTAssertEqual(stored.notes, "残す")
        XCTAssertNil(stored.partID)
        XCTAssertFalse(stored.patternEndOnNextDay)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkShift>()).count, 1)

        let night = ShiftPart(
            name: "夜",
            workplaceUUID: workplace.uuid,
            startMinute: 22 * 60,
            endMinute: 5 * 60,
            breakMinutes: 60
        )
        let placed = ShiftPartCommit.apply(
            part: night,
            days: [day(2026, 11, 5)],
            shifts: [stored],
            workplaces: [workplace],
            context: context,
            calendar: calendar
        )
        guard case .placed(let drafts) = placed.outcome else {
            return XCTFail("place")
        }
        XCTAssertEqual(drafts.count, 1)
        // The pattern carries a fixed 60 minute break, so the shift gets it.
        XCTAssertEqual(drafts[0].breakMinutes, 60)
        XCTAssertFalse(drafts[0].breakFollowsRules)
        XCTAssertTrue(drafts[0].endAddsOneDay)
        let rows = try context.fetch(FetchDescriptor<WorkShift>())
        XCTAssertEqual(rows.count, 2)
        let kept = try XCTUnwrap(rows.first { $0.notes == "残す" })
        XCTAssertEqual(kept.startMinutes, 9 * 60)
        XCTAssertEqual(kept.breakMinutes, 15)
        let added = try XCTUnwrap(rows.first { $0.partID == night.uuid })
        XCTAssertTrue(calendar.isDate(added.date, inSameDayAs: day(2026, 11, 5)))
        XCTAssertEqual(added.breakMinutes, 60)
        XCTAssertFalse(added.breakFollowsRules)
        XCTAssertEqual(added.startMinutes, 22 * 60)
        XCTAssertEqual(added.endMinutes, 5 * 60)
        XCTAssertTrue(added.patternEndOnNextDay)
        XCTAssertEqual(added.workedMinutes, 6 * 60)
        XCTAssertEqual(added.estimatedYen(includeTransport: false), (1000 * 6 * 60 + 30) / 60)
        XCTAssertEqual(placed.inserted.count, 1)
        XCTAssertEqual(stored.estimatedYen(includeTransport: false), kept.estimatedYen(includeTransport: false))

        let repeatNight = ShiftPartCommit.apply(
            part: night,
            days: [day(2026, 11, 5)],
            shifts: rows,
            workplaces: [workplace],
            context: context,
            calendar: calendar
        )
        guard case .placed(let none) = repeatNight.outcome else {
            return XCTFail("same part")
        }
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkShift>()).count, 2)

        let equal = WorkShift(
            date: day(2026, 11, 6),
            startMinutes: 10 * 60,
            endMinutes: 10 * 60,
            breakMinutes: 0,
            partID: part.uuid,
            patternEndOnNextDay: true,
            workplace: workplace
        )
        XCTAssertEqual(equal.workedMinutes, 24 * 60)
        XCTAssertEqual(equal.estimatedYen(includeTransport: false), (1000 * 24 * 60 + 30) / 60)
        let legacy = WorkShift(
            date: day(2026, 11, 6),
            startMinutes: 10 * 60,
            endMinutes: 10 * 60,
            breakMinutes: 0,
            workplace: workplace
        )
        XCTAssertEqual(legacy.workedMinutes, 0)
        XCTAssertEqual(legacy.estimatedYen(includeTransport: false), 0)
    }
}
