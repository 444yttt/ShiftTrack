import Testing
@testable import ShiftTrack

struct PayBreakdownTests {
    private let calendar = ShiftOverlap.tokyo

    @Test
    func sliceUsesTheWageInForceAndKeepsPremiumsOut() {
        let place = UUID()
        let history = [
            WagePoint(day: LocalDay(year: 2026, month: 4, day: 1), yen: 1_500),
            WagePoint(day: LocalDay(year: 2026, month: 10, day: 1), yen: 1_600),
            WagePoint(day: LocalDay(year: 2026, month: 10, day: 1), yen: 1_650),
        ]
        let september = slice(place: place, day: LocalDay(year: 2026, month: 9, day: 30), minutes: 60, history: history, adjustment: -100)
        let october = slice(place: place, day: LocalDay(year: 2026, month: 10, day: 1), minutes: 60, history: history, adjustment: 0)
        #expect(september.workplaceName == "架空茶房 北窓")
        #expect(september.baseYen == 1_500)
        #expect(september.transportYen == 500)
        #expect(september.adjustmentYen == -100)
        #expect(september.total == 1_900)
        #expect(october.baseYen == 1_650)
        #expect(september.payday == october.payday)
        let groups = PayBreakdown.groupedByPayday([october, september])
        #expect(groups.count == 1)
        #expect(groups[0].slices.count == 2)
        #expect(groups[0].day == september.payday)
    }

    @Test
    func paydayGroupsStayInDateOrder() {
        let place = UUID()
        let early = slice(place: place, day: LocalDay(year: 2026, month: 11, day: 1), minutes: 30, history: [], adjustment: 0, closing: 31, payday: 10, offset: 0)
        let late = slice(place: place, day: LocalDay(year: 2026, month: 11, day: 20), minutes: 30, history: [], adjustment: 0, closing: 31, payday: 25, offset: 1)
        let groups = PayBreakdown.groupedByPayday([late, early])
        #expect(groups.map(\.day) == [early.payday, late.payday])
        #expect(early.baseYen == 600)
    }

    @Test
    func addingAWageDoesNotRewriteOlderShifts() {
        let history = [WagePoint(day: LocalDay(year: 2026, month: 4, day: 1), yen: 1_200)]
        let note = WagePreview.note(
            day: LocalDay(year: 2026, month: 11, day: 11),
            yen: 1_500,
            shifts: [
                WageChange(day: LocalDay(year: 2026, month: 11, day: 1), minutes: 60),
                WageChange(day: LocalDay(year: 2026, month: 11, day: 11), minutes: 60),
            ],
            history: history,
            fallback: 1_200
        )
        #expect(note.contains("11月11日以降の勤務に ¥1,500 を使用します。"))
        #expect(note.contains("過去の時給は上書きしません。"))
        #expect(note.contains("既存のシフト1件"))
        #expect(note.contains("+¥300"))
        #expect(!note.contains("壁"))
    }

    private func slice(
        place: UUID,
        day: LocalDay,
        minutes: Int,
        history: [WagePoint],
        adjustment: Int,
        closing: Int = 20,
        payday: Int = 25,
        offset: Int = 1
    ) -> PaySlice {
        PayBreakdown.slice(
            PayShiftInput(
                shiftID: UUID(),
                workplaceID: place,
                workplaceName: "架空茶房 北窓",
                day: day,
                minutes: minutes,
                hourlyFallback: 1_200,
                history: history,
                transport: 500,
                adjustment: adjustment,
                closingDay: closing,
                paydayDay: payday,
                monthOffset: offset
            ),
            calendar: calendar
        )
    }
}
