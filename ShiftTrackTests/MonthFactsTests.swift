import Testing
@testable import ShiftTrack

struct MonthFactsTests {
    @Test(arguments: [
        (start: 10 * 60, end: 18 * 60, night: false),
        (start: 18 * 60, end: 23 * 60, night: true),
        (start: 23 * 60, end: 2 * 60, night: true),
        (start: 1 * 60, end: 4 * 60, night: true),
        (start: 6 * 60, end: 14 * 60, night: false),
    ])
    func nightWindow(start: Int, end: Int, night: Bool) {
        #expect(MonthFacts.overlapsNight(start: start, end: end, nightStart: 22 * 60, nightEnd: 5 * 60) == night)
    }

    @Test
    func headlineUsesTheCountedNumbers() {
        let summary = MonthFacts.summarize([
            MonthShiftFact(startMinutes: 18 * 60, endMinutes: 23 * 60, workedMinutes: 300, yen: 6_000, workplaceName: "架空茶房"),
            MonthShiftFact(startMinutes: 10 * 60, endMinutes: 15 * 60, workedMinutes: 300, yen: 5_000, workplaceName: "架空茶房"),
        ])
        #expect(summary.shiftCount == 2)
        #expect(summary.workedMinutes == 600)
        #expect(summary.estimatedPayYen == 11_000)
        #expect(summary.lateNightShiftCount == 1)
        #expect(summary.workplaceCount == 1)
        let line = MonthFacts.headline(summary)
        #expect(line.contains("10時間勤務"))
        #expect(line.contains("11,000"))
        #expect(line.contains("深夜勤務1回"))
    }
}
