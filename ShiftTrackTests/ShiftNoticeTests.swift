import Foundation
import Testing
@testable import ShiftTrack

struct ShiftNoticeTests {
    private let calendar = ShiftOverlap.tokyo
    private let now = ShiftOverlap.tokyo.date(
        from: DateComponents(year: 2026, month: 11, day: 11, hour: 9)
    )!

    @Test
    func bothSwitchesScheduleAFutureShift() {
        let id = UUID()
        let start = now.addingTimeInterval(3 * 60 * 60)
        let end = start.addingTimeInterval(8 * 60 * 60)
        let notices = ShiftNotices.plan(
            [ShiftNotice.Input(id: id, name: "架空茶房", start: start, end: end)],
            now: now,
            before: true,
            atEnd: true
        )
        #expect(notices.count == 2)
        #expect(notices[0].kind == .before)
        #expect(notices[0].fire == start.addingTimeInterval(-30 * 60))
        #expect(notices[0].body.contains("架空茶房"))
        #expect(notices[1].kind == .end)
        #expect(notices[1].fire == end)
        #expect(notices[0].identifier.hasPrefix(ShiftNotice.prefix))
    }

    @Test
    func aLeadThatAlreadyPassedIsDropped() {
        let start = now.addingTimeInterval(10 * 60)
        let notices = ShiftNotices.plan(
            [ShiftNotice.Input(id: UUID(), name: "架空茶房", start: start, end: start.addingTimeInterval(60 * 60))],
            now: now,
            before: true,
            atEnd: false
        )
        #expect(notices.isEmpty)
    }

    @Test
    func switchesOffAndPastShiftsStayQuiet() {
        let past = now.addingTimeInterval(-2 * 60 * 60)
        let off = ShiftNotices.plan(
            [ShiftNotice.Input(id: UUID(), name: "架空茶房", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))],
            now: now,
            before: false,
            atEnd: false
        )
        let ended = ShiftNotices.plan(
            [ShiftNotice.Input(id: UUID(), name: "架空茶房", start: past, end: past.addingTimeInterval(3600))],
            now: now,
            before: true,
            atEnd: true
        )
        #expect(off.isEmpty)
        #expect(ended.isEmpty)
    }

    @Test
    func overnightEndIsTheNextMorning() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let span = ShiftNotices.interval(day: day, startMinutes: 22 * 60, endMinutes: 5 * 60, calendar: calendar)
        #expect(calendar.component(.hour, from: span.start) == 22)
        #expect(calendar.component(.day, from: span.end) == 13)
        #expect(calendar.component(.hour, from: span.end) == 5)
    }
}

struct ShiftMirrorPlanTests {
    @Test
    func endedShiftsAreNotWrittenAndTodosKeepATitle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let live = UUID()
        let done = UUID()
        let events = ShiftMirrorPlan.events(
            [
                ShiftNotice.Input(id: live, name: "架空茶房", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200)),
                ShiftNotice.Input(id: done, name: "架空茶房", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
            ],
            places: [live: "北窓"],
            now: now
        )
        #expect(events.map(\.shiftID) == [live])
        #expect(events.first?.place == "北窓")
        let todo = UUID()
        let reminders = ShiftMirrorPlan.reminders(
            [(id: todo, title: " かぎ ", due: now.addingTimeInterval(3600), done: false)],
            now: now
        )
        #expect(reminders == [ShiftMirrorPlan.Reminder(todoID: todo, title: "かぎ", due: now.addingTimeInterval(3600), completed: false)])
    }
}
