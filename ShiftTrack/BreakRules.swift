import Foundation

/// Product policy around the recovered break selector.
/// The selector and the editor minute count are reconstructions.
/// Which of the two minute callers feeds payroll was not recovered, so pay
/// still receives the break minutes stored on the shift.
enum BreakRules {
    struct TextBreakDecision: Equatable {
        var minutes: Int
        var followsRules: Bool
    }

    /// Minutes passed to the selector from a clock pair.
    /// Equal clock minutes are 0 here. The recovered editor count would be
    /// 1440, and the shift editor still rejects that pair.
    static func selectionMinutes(start: Int, end: Int) -> Int {
        let start = ShiftDatePolicy.clockMinutes(start)
        let end = ShiftDatePolicy.clockMinutes(end)
        if start == end { return 0 }
        return InOutRecovered.editorMinuteCount(startMinute: start, endMinute: end)
    }

    static func activeRules(customBreaks: Bool, rules: [InOutRecovered.BreakRule]) -> [InOutRecovered.BreakRule] {
        customBreaks ? rules : InOutRecovered.legalBreakRules
    }

    static func automaticMinutes(
        start: Int,
        end: Int,
        customBreaks: Bool,
        rules: [InOutRecovered.BreakRule]
    ) -> Int {
        let chosen = InOutRecovered.selectedBreakMinutes(
            selectionMinutes(start: start, end: end),
            rules: activeRules(customBreaks: customBreaks, rules: rules)
        )
        return ShiftDatePolicy.clampedBreak(chosen, range: 0...600)
    }

    static func minutesForEditor(
        payIsDaily: Bool,
        followsRules: Bool,
        manualMinutes: Int,
        start: Int,
        end: Int,
        customBreaks: Bool,
        rules: [InOutRecovered.BreakRule]
    ) -> Int {
        if payIsDaily { return 0 }
        if followsRules {
            return automaticMinutes(start: start, end: end, customBreaks: customBreaks, rules: rules)
        }
        return ShiftDatePolicy.clampedBreak(manualMinutes, range: 0...600)
    }

    /// A written break stays manual. A line with no break uses the rules.
    /// Daily pay stores 0. This does not rewrite shifts that are already saved.
    static func textDecision(
        breakIsExplicit: Bool,
        explicitMinutes: Int,
        payIsDaily: Bool,
        customBreaks: Bool,
        rules: [InOutRecovered.BreakRule],
        start: Int,
        end: Int
    ) -> TextBreakDecision {
        if payIsDaily {
            return TextBreakDecision(minutes: 0, followsRules: false)
        }
        if breakIsExplicit {
            return TextBreakDecision(
                minutes: min(8 * 60, max(0, explicitMinutes)),
                followsRules: false
            )
        }
        return TextBreakDecision(
            minutes: automaticMinutes(start: start, end: end, customBreaks: customBreaks, rules: rules),
            followsRules: true
        )
    }

    static func refreshed(_ candidate: ImportCandidate, workplace: Workplace?) -> ImportCandidate {
        var copy = candidate
        if workplace?.payIsDaily == true {
            copy.breakMinutes = 0
            copy.breakFollowsRules = false
            return copy
        }
        guard copy.breakFollowsRules else { return copy }
        copy.breakMinutes = automaticMinutes(
            start: copy.startMinutes,
            end: copy.endMinutes,
            customBreaks: workplace?.customBreaks ?? false,
            rules: workplace?.breakRules ?? []
        )
        return copy
    }

    static func encode(_ rules: [InOutRecovered.BreakRule]) -> String {
        rules.map { "\($0.overMinutes):\($0.breakMinutes)" }.joined(separator: ",")
    }

    static func decode(_ raw: String) -> [InOutRecovered.BreakRule] {
        raw.split(separator: ",").compactMap { part in
            let pieces = part.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, let over = Int(pieces[0]), let rest = Int(pieces[1]) else { return nil }
            guard over >= 0, rest >= 0 else { return nil }
            return .init(overMinutes: over, breakMinutes: rest)
        }
    }

    static func summary(customBreaks: Bool, rules: [InOutRecovered.BreakRule]) -> String {
        let active = activeRules(customBreaks: customBreaks, rules: rules)
        if active.isEmpty { return "規則がないので、自動の休憩は0分です。" }
        let lines = active.map { "\(Formatters.hours($0.overMinutes))を超えたら\(Formatters.hours($0.breakMinutes))" }
        return lines.joined(separator: "、") + "。"
    }
}
