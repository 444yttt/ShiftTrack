import Foundation

/// Thresholds checked on 2026-11-11 against 国税庁, 財務省, 厚生労働省, and 日本年金機構.
/// Every figure on screen is a 目安. This is not a tax or insurance decision.
enum IncomeGuide {
    static let asOf = LocalDay(year: 2026, month: 11, day: 11)
    static let sourceNote = "2026年11月11日に国税庁・財務省・厚生労働省・日本年金機構の案内で確認した目安です。税や社会保険の判定ではありません。制度は変わります。"

    enum Basis: String, Equatable {
        /// 給与収入. Non-taxable commuting allowance is not included.
        case salary
        /// 今後1年間の見込収入. Commuting allowance is included.
        case socialExpected
    }

    enum Bound: String, Equatable {
        /// 未満. The amount itself is already over.
        case lessThan
        /// 以下. The amount itself is still inside.
        case atMost
    }

    enum Outlook: Equatable {
        case under
        case approaching
        case over
    }

    struct Figures: Equatable {
        var salaryYen: Int
        var socialYen: Int
    }

    struct Line: Equatable, Identifiable {
        var id: String
        var title: String
        var yen: Int?
        var bound: Bound
        var basis: Basis
        var note: String
    }

    enum SpecialRelative: Equatable {
        case dependent
        case full
        case phased
        case none
        case notThisYear
    }

    static func age(on day: LocalDay, born: LocalDay) -> Int {
        var years = day.year - born.year
        if (day.month, day.day) < (born.month, born.day) { years -= 1 }
        return years
    }

    static func december31(_ year: Int) -> LocalDay {
        LocalDay(year: year, month: 12, day: 31)
    }

    /// 19歳以上23歳未満 on 31 December. Spouses of the insured are outside the 150万円 line.
    static func isAge19Until23(_ age: Int) -> Bool {
        (19..<23).contains(age)
    }

    static func ownIncomeTaxYen(year: Int) -> Int {
        switch year {
        case ...2024: return 1_030_000
        case 2025: return 1_600_000
        case 2026, 2027: return 1_780_000
        default: return 1_680_000
        }
    }

    static func dependentSalaryYen(year: Int) -> Int {
        switch year {
        case ...2024: return 1_030_000
        case 2025: return 1_230_000
        default: return 1_360_000
        }
    }

    /// Full amount through this salary, then a reduced amount through `phaseEnd` inclusive.
    static func specialRelativeBand(year: Int) -> (fullThrough: Int, phaseEnd: Int)? {
        switch year {
        case 2025: return (1_500_000, 1_880_000)
        case 2026...: return (1_590_000, 1_970_000)
        default: return nil
        }
    }

    static func specialRelative(_ salary: Int, year: Int) -> SpecialRelative {
        guard let band = specialRelativeBand(year: year) else { return .notThisYear }
        let dependent = dependentSalaryYen(year: year)
        if salary <= dependent { return .dependent }
        if salary <= band.fullThrough { return .full }
        if salary <= band.phaseEnd { return .phased }
        return .none
    }

    /// Nil until a birthdate is known. 150万円 is only for ages 19 up to but not including 23, and not for a spouse.
    static func healthLine(year: Int, ageOnDecember31: Int?) -> (yen: Int, title: String)? {
        guard let age = ageOnDecember31 else { return nil }
        if age >= 60 { return (1_800_000, "社会保険の扶養（60歳以上）") }
        if year >= 2025, isAge19Until23(age) { return (1_500_000, "社会保険の扶養（19歳以上23歳未満）") }
        return (1_300_000, "社会保険の扶養")
    }

    static func lines(year: Int, ageOnDecember31: Int?) -> [Line] {
        var rows: [Line] = []
        let tax = ownIncomeTaxYen(year: year)
        let taxNote: String
        if year == 2026 || year == 2027 {
            taxNote = "給与のみの場合、2026–2027年分は178万円まで所得税がかかりません。現行法では2028年分から168万円です。今後の改正で変わりえます。給与収入で見ます。通勤手当は含めません。"
        } else if year >= 2028 {
            taxNote = "現行法では2028年分以後は168万円です。財務省は、今後の改正で178万円付近に残る余地もあると説明しています。給与収入で見ます。"
        } else if year == 2025 {
            taxNote = "2025年分の給与のみの課税最低限は160万円です。給与収入で見ます。"
        } else {
            taxNote = "2024年分以前の給与のみの課税最低限は103万円です。"
        }
        rows.append(Line(id: "own-tax", title: "本人の所得税", yen: tax, bound: .atMost, basis: .salary, note: taxNote))

        rows.append(Line(
            id: "dependent",
            title: "親の扶養控除",
            yen: dependentSalaryYen(year: year),
            bound: .atMost,
            basis: .salary,
            note: year >= 2026
                ? "2026年分以後、給与のみなら136万円以下で扶養控除の対象です。2025年分は123万円以下です。"
                : "この年分の、給与のみの場合の扶養控除の線です。"
        ))

        if let band = specialRelativeBand(year: year) {
            rows.append(Line(
                id: "special-relative",
                title: "特定親族特別控除",
                yen: band.phaseEnd,
                bound: .atMost,
                basis: .salary,
                note: "19歳以上23歳未満の親族です。\(band.fullThrough / 10_000)万円以下は満額、\(band.phaseEnd / 10_000)万円以下まで段階的に残り、それを超えるとなくなります。\(band.phaseEnd / 10_000)万円ちょうどは残ります。"
            ))
        }

        if let health = healthLine(year: year, ageOnDecember31: ageOnDecember31) {
            let spouse = health.yen == 1_500_000 ? "被保険者の配偶者は150万円の対象外で、130万円未満です。" : ""
            rows.append(Line(
                id: "health",
                title: health.title,
                yen: health.yen,
                bound: .lessThan,
                basis: .socialExpected,
                note: "\(health.yen / 10_000)万円未満です。ちょうどその金額は入りません。今後1年間の見込収入で、通勤手当を含めます。労働契約で見る場合の目安です。\(spouse)"
            ))
        } else {
            rows.append(Line(
                id: "health-unset",
                title: "社会保険の扶養",
                yen: nil,
                bound: .lessThan,
                basis: .socialExpected,
                note: "12月31日時点の年齢で、150万円未満か130万円未満かが決まります。60歳以上は180万円未満です。生年月日を入れてください。"
            ))
        }

        rows.append(Line(
            id: "short-time",
            title: "短時間の社会保険",
            yen: nil,
            bound: .lessThan,
            basis: .socialExpected,
            note: "月額8.8万円の賃金要件は2026年10月1日になくなりました。週20時間と、学生ではないことは残ります。昼間の学生は、この加入では原則対象外です。"
        ))

        rows.append(Line(
            id: "resident-tax",
            title: "住民税",
            yen: nil,
            bound: .atMost,
            basis: .salary,
            note: "非課税の線は自治体で違います。全国一律の金額は置きません。"
        ))
        return rows
    }

    static func estimate(_ basis: Basis, figures: Figures) -> Int {
        switch basis {
        case .salary: return figures.salaryYen
        case .socialExpected: return figures.socialYen
        }
    }

    static func isOver(estimate: Int, line: Int, bound: Bound) -> Bool {
        switch bound {
        case .lessThan: return estimate >= line
        case .atMost: return estimate > line
        }
    }

    static func outlook(estimate: Int, line: Int, bound: Bound) -> Outlook {
        if isOver(estimate: estimate, line: line, bound: bound) { return .over }
        if estimate * 100 >= line * 95 { return .approaching }
        return .under
    }

    static func message(title: String, outlook: Outlook) -> String {
        switch outlook {
        case .under:
            return "現在のペースでは、\(title)の基準内に収まる見込みです。"
        case .approaching:
            return "現在の予定では、\(title)の基準に近づく見込みです。条件を確認しておくと安心です。"
        case .over:
            return "現在の予定では、\(title)の基準を超える見込みです。条件を確認しておくと安心です。"
        }
    }

    static func sum(_ amounts: [(day: LocalDay, yen: Int)], from: LocalDay, until: LocalDay) -> Int {
        amounts.reduce(0) { partial, row in
            guard row.day >= from, row.day < until else { return partial }
            return partial + row.yen
        }
    }
}
