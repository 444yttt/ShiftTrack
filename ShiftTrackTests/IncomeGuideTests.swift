import Testing
@testable import ShiftTrack

struct IncomeGuideTests {
    @Test(arguments: [
        (1_424_999, IncomeGuide.Bound.lessThan, IncomeGuide.Outlook.under),
        (1_425_000, IncomeGuide.Bound.lessThan, IncomeGuide.Outlook.approaching),
        (1_499_999, IncomeGuide.Bound.lessThan, IncomeGuide.Outlook.approaching),
        (1_500_000, IncomeGuide.Bound.lessThan, IncomeGuide.Outlook.over),
        (1_780_000, IncomeGuide.Bound.atMost, IncomeGuide.Outlook.approaching),
        (1_780_001, IncomeGuide.Bound.atMost, IncomeGuide.Outlook.over),
    ])
    func boundDecidesWhetherTheAmountItselfIsInside(estimate: Int, bound: IncomeGuide.Bound, expected: IncomeGuide.Outlook) {
        let line = bound == .lessThan ? 1_500_000 : 1_780_000
        #expect(IncomeGuide.outlook(estimate: estimate, line: line, bound: bound) == expected)
    }

    @Test
    func verifiedTableUsesSeparateTotalsAndDoesNotHardcodeResidentTax() {
        #expect(IncomeGuide.asOf == LocalDay(year: 2026, month: 11, day: 11))
        #expect(IncomeGuide.sourceNote.contains("目安"))
        #expect(IncomeGuide.sourceNote.contains("2026年11月11日"))
        let lines = IncomeGuide.lines(year: 2026, ageOnDecember31: 20)
        #expect(lines.contains { $0.id == "own-tax" && $0.yen == 1_780_000 && $0.basis == .salary && $0.bound == .atMost })
        #expect(lines.contains { $0.id == "dependent" && $0.yen == 1_360_000 && $0.basis == .salary })
        #expect(lines.contains { $0.id == "special-relative" && $0.yen == 1_970_000 && $0.bound == .atMost })
        #expect(lines.contains { $0.id == "health" && $0.yen == 1_500_000 && $0.bound == .lessThan && $0.basis == .socialExpected })
        #expect(lines.contains { $0.id == "short-time" && $0.yen == nil })
        #expect(lines.contains { $0.id == "resident-tax" && $0.yen == nil })
        #expect(IncomeGuide.ownIncomeTaxYen(year: 2028) == 1_680_000)
        #expect(IncomeGuide.lines(year: 2026, ageOnDecember31: 23).contains { $0.id == "health" && $0.yen == 1_300_000 })
        #expect(IncomeGuide.lines(year: 2026, ageOnDecember31: 60).contains { $0.id == "health" && $0.yen == 1_800_000 })
        #expect(IncomeGuide.lines(year: 2026, ageOnDecember31: nil).contains { $0.id == "health-unset" && $0.yen == nil })
        let figures = IncomeGuide.Figures(salaryYen: 1_200_000, socialYen: 1_450_000)
        #expect(IncomeGuide.estimate(.salary, figures: figures) == 1_200_000)
        #expect(IncomeGuide.estimate(.socialExpected, figures: figures) == 1_450_000)
        let over = IncomeGuide.message(title: "社会保険の扶養", outlook: .over)
        #expect(over.contains("見込み"))
        #expect(!over.contains("壁"))
    }

    @Test(arguments: [
        (1_360_000, IncomeGuide.SpecialRelative.dependent),
        (1_360_001, IncomeGuide.SpecialRelative.full),
        (1_590_000, IncomeGuide.SpecialRelative.full),
        (1_590_001, IncomeGuide.SpecialRelative.phased),
        (1_970_000, IncomeGuide.SpecialRelative.phased),
        (1_970_001, IncomeGuide.SpecialRelative.none),
    ])
    func specialRelativeKeeps197ManInclusive(salary: Int, expected: IncomeGuide.SpecialRelative) {
        #expect(IncomeGuide.specialRelative(salary, year: 2026) == expected)
    }

    @Test
    func december31AgeSelectsTheHealthLine() {
        let born = LocalDay(year: 2006, month: 4, day: 2)
        #expect(IncomeGuide.age(on: IncomeGuide.december31(2026), born: born) == 20)
        #expect(IncomeGuide.isAge19Until23(20))
        #expect(!IncomeGuide.isAge19Until23(23))
        #expect(IncomeGuide.healthLine(year: 2026, ageOnDecember31: 20)?.yen == 1_500_000)
        #expect(IncomeGuide.healthLine(year: 2026, ageOnDecember31: 18)?.yen == 1_300_000)
        #expect(IncomeGuide.healthLine(year: 2024, ageOnDecember31: 20)?.yen == 1_300_000)
    }

    @Test
    func salaryAndSocialWindowsDoNotShareASum() {
        let rows = [
            (day: LocalDay(year: 2026, month: 1, day: 10), yen: 100_000),
            (day: LocalDay(year: 2026, month: 12, day: 1), yen: 50_000),
        ]
        let salary = IncomeGuide.sum(rows, from: LocalDay(year: 2026, month: 1, day: 1), until: LocalDay(year: 2027, month: 1, day: 1))
        let social = IncomeGuide.sum(
            rows.map { (day: $0.day, yen: $0.yen + 500) },
            from: LocalDay(year: 2026, month: 11, day: 11),
            until: LocalDay(year: 2027, month: 11, day: 11)
        )
        #expect(salary == 150_000)
        #expect(social == 50_500)
        #expect(salary != social)
    }
}
