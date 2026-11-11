import Testing
@testable import ShiftTrack

struct IncomeGuideTests {
    @Test(arguments: [
        (1_234_999, IncomeGuide.Outlook.under),
        (1_235_000, IncomeGuide.Outlook.approaching),
        (1_299_999, IncomeGuide.Outlook.approaching),
        (1_300_000, IncomeGuide.Outlook.over),
    ])
    func outlookChangesAtNinetyFivePercent(estimate: Int, expected: IncomeGuide.Outlook) {
        #expect(IncomeGuide.outlook(estimate: estimate, line: 1_300_000) == expected)
    }

    @Test
    func tableIsDatedAndDoesNotTreatTheChatFiguresAsLaw() {
        #expect(IncomeGuide.asOf == LocalDay(year: 2026, month: 11, day: 11))
        #expect(IncomeGuide.sourceNote.contains("未確認"))
        #expect(IncomeGuide.lines.contains { $0.id == "employment-106" && $0.yen == nil })
        #expect(IncomeGuide.lines.contains { $0.yen == 1_780_000 && $0.basis == .paydayExcludingTransport })
        #expect(IncomeGuide.lines.contains { $0.yen == 1_500_000 && $0.basis == .annualizedIncludingTransport })
        let over = IncomeGuide.message(title: "社会保険の扶養", outlook: .over)
        #expect(over.contains("見込み"))
        #expect(!over.contains("壁"))
    }
}
