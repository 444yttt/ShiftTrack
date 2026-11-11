import Foundation

/// Figures from the 2026-11-11 design consultation. They are not checked against
/// 国税庁, 厚生労働省, or 日本年金機構. Replace this table when verified numbers arrive.
enum IncomeGuide {
    static let asOf = LocalDay(year: 2026, month: 11, day: 11)
    static let sourceNote = "2026-11-11 の相談メモ。一次資料では未確認。画面では目安と書く。"

    enum Basis: String, Equatable {
        /// Pay received in the year, without commuting allowance.
        case paydayExcludingTransport
        /// Annualized estimate, commuting allowance included.
        case annualizedIncludingTransport
    }

    struct Line: Equatable, Identifiable {
        var id: String
        var title: String
        var yen: Int?
        var basis: Basis
        var note: String
    }

    static let lines: [Line] = [
        Line(
            id: "tax-2026",
            title: "本人の所得税",
            yen: 1_780_000,
            basis: .paydayExcludingTransport,
            note: "相談メモでは、2026–2027年分は178万円。2025年分は160万円、2028年分は168万円の予定とある。103万円は現行ではない、とメモにある。"
        ),
        Line(
            id: "dependent-2026",
            title: "家族の税控除",
            yen: 1_360_000,
            basis: .paydayExcludingTransport,
            note: "相談メモでは、2026年の扶養控除の線は136万円。2025年は123万円とある。19–22歳の特別控除は159万円まで満額、197万円で消える、とある。"
        ),
        Line(
            id: "health-19-22",
            title: "社会保険の扶養（19–22歳）",
            yen: 1_500_000,
            basis: .annualizedIncludingTransport,
            note: "相談メモでは、2025年10月から19–22歳は150万円未満。別の資料は130万円のまま、とあり未確定。交通費を含む。"
        ),
        Line(
            id: "health-130",
            title: "社会保険の扶養",
            yen: 1_300_000,
            basis: .annualizedIncludingTransport,
            note: "相談メモでは、130万円はまだ使われる。60歳以上は180万円未満、とある。交通費を含む。"
        ),
        Line(
            id: "health-60",
            title: "社会保険の扶養（60歳以上）",
            yen: 1_800_000,
            basis: .annualizedIncludingTransport,
            note: "相談メモでは、60歳以上は180万円未満。交通費を含む。"
        ),
        Line(
            id: "employment-106",
            title: "短時間の社会保険",
            yen: nil,
            basis: .annualizedIncludingTransport,
            note: "相談メモでは、2026年10月1日に月額8.8万円の要件は無くなった。週20時間の要件は残る、とある。金額の線は出さない。"
        ),
    ]

    enum Outlook: Equatable {
        case under
        case approaching
        case over
    }

    static func outlook(estimate: Int, line: Int) -> Outlook {
        if estimate >= line { return .over }
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
            return "現在の予定では、\(title)の基準を超える見込みです。扶養や税の条件を確認しておくと安心です。"
        }
    }
}
