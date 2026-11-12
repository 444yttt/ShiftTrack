import Foundation

/// Save checks of the workplace editor. Day equality uses the calendar the
/// caller passes. A date shared by the wage list and the pay-rule list is not
/// a duplicate; each list is checked on its own.
enum WorkplaceEditorCheck {
    static let emptyName = "勤務先の名前を入れてください。"
    static let duplicateWageDate = "時給の記録に同じ日付が2つあります。どちらかを消してください。"
    static let duplicatePayRuleDate = "給料の決まりの開始日に同じ日付が2つあります。どちらかを消してください。"
    static let negativeWage = "時給は0円以上で入れてください。"

    /// `hourlyWage` is nil when the form is not saving an hourly amount.
    /// The first failing check is the one the editor shows.
    static func message(
        name: String,
        hourlyWage: Int?,
        wageDates: [Date],
        payRuleDates: [Date],
        calendar: Calendar
    ) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return emptyName
        }
        if duplicated(wageDates, calendar: calendar) {
            return duplicateWageDate
        }
        if duplicated(payRuleDates, calendar: calendar) {
            return duplicatePayRuleDate
        }
        if let hourlyWage, hourlyWage < 0 {
            return negativeWage
        }
        return nil
    }

    /// Keeps a leading minus. Digits after that are the magnitude. Empty is 0.
    static func signedYen(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let negative = trimmed.first == "-" || trimmed.first == "−" || trimmed.first == "－"
        let digits = trimmed.filter(\.isNumber)
        let magnitude = Int(digits) ?? 0
        if negative, magnitude > 0 { return -magnitude }
        return magnitude
    }

    private static func duplicated(_ dates: [Date], calendar: Calendar) -> Bool {
        var seen = Set<Date>()
        for date in dates {
            let day = calendar.startOfDay(for: date)
            if !seen.insert(day).inserted { return true }
        }
        return false
    }
}
