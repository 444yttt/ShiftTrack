import Foundation

/// How a saved pattern decides the break on the shifts it creates.
enum PatternBreakMode: Int, CaseIterable, Identifiable {
    /// A set number of minutes. 0 means no break.
    case fixed = 0
    /// Follow the workplace's break rules (the legal 6h/8h table or its own).
    case workplace = 1
    /// Rules that belong to this pattern only.
    case custom = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fixed: "分数"
        case .workplace: "勤務先"
        case .custom: "専用"
        }
    }
}

/// Break for a shift placed from a pattern. Pure, so it can be tested without a store.
enum PatternBreak {
    struct Result: Equatable {
        var minutes: Int
        /// True only for the workplace's own rules, so the shift keeps following
        /// them when its times are edited later.
        var followsRules: Bool
    }

    /// What the chosen mode does, for the line under the picker.
    static func detail(_ mode: PatternBreakMode) -> String {
        switch mode {
        case .fixed: "置くシフトに、決めた分数の休憩を入れます。0分なら休憩なしです。"
        case .workplace: "勤務先の「休憩の決まり」に合わせます。あとで時刻を変えると、休憩も一緒に変わります。"
        case .custom: "このパターンだけの決まりで休憩を入れます。勤務先の設定は変わりません。"
        }
    }

    static func mode(_ raw: Int) -> PatternBreakMode {
        PatternBreakMode(rawValue: raw) ?? .fixed
    }

    static func resolve(
        modeRaw: Int,
        fixedMinutes: Int,
        customRulesRaw: String,
        startMinutes: Int,
        endMinutes: Int,
        workplace: Workplace?
    ) -> Result {
        if workplace?.payIsDaily == true {
            return Result(minutes: 0, followsRules: false)
        }
        switch mode(modeRaw) {
        case .fixed:
            return Result(
                minutes: ShiftDatePolicy.clampedBreak(fixedMinutes, range: 0...600),
                followsRules: false
            )
        case .workplace:
            guard let workplace else { return Result(minutes: 0, followsRules: false) }
            return Result(
                minutes: BreakRules.automaticMinutes(
                    start: startMinutes,
                    end: endMinutes,
                    customBreaks: workplace.customBreaks,
                    rules: workplace.breakRules
                ),
                followsRules: true
            )
        case .custom:
            return Result(
                minutes: BreakRules.automaticMinutes(
                    start: startMinutes,
                    end: endMinutes,
                    customBreaks: true,
                    rules: BreakRules.decode(customRulesRaw)
                ),
                followsRules: false
            )
        }
    }

    /// One line for lists, e.g. 「休憩 45分」.
    static func summary(modeRaw: Int, fixedMinutes: Int, customRulesRaw: String) -> String {
        switch mode(modeRaw) {
        case .fixed:
            return fixedMinutes > 0 ? "休憩 \(Formatters.hours(fixedMinutes))" : "休憩なし"
        case .workplace:
            return "休憩は勤務先の決まりどおり"
        case .custom:
            let rules = BreakRules.decode(customRulesRaw)
            return rules.isEmpty ? "休憩なし（専用の決まりが空です）" : "休憩は専用の決まり（\(rules.count)件）"
        }
    }
}
