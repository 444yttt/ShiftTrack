import Foundation

/// The shift-request screen builds one month and fetches two lists.
/// Kind 0 is shown as 出勤希望 and kind 1 as 休み希望. Which integer is
/// 出勤希望 is not confirmed; this assignment is a choice, not a finding.
enum ShiftRequestKind {
    static let hopedAttendance = 0
    static let hopedRest = 1
}

enum ShiftRequestLists {
    struct Item: Equatable, Identifiable {
        var id: UUID
        var date: Date
        var kind: Int
    }

    struct Month: Equatable {
        var start: Date
        /// First instant of the next month. The month is `[start, end)`.
        var end: Date
    }

    struct Pair: Equatable {
        var attendance: [Item]
        var rest: [Item]
    }

    static func month(containing day: Date, calendar: Calendar) -> Month? {
        let parts = calendar.dateComponents([.year, .month], from: day)
        guard
            let start = calendar.date(from: parts),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return Month(start: start, end: end)
    }

    static func split(_ items: [Item], month: Month) -> Pair {
        let inside = items.filter { $0.date >= month.start && $0.date < month.end }
        return Pair(
            attendance: inside.filter { $0.kind == ShiftRequestKind.hopedAttendance },
            rest: inside.filter { $0.kind == ShiftRequestKind.hopedRest }
        )
    }
}
