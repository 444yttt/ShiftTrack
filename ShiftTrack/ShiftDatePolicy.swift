import Foundation

/// Keeps a stored shift date separate from the day the calendar is showing.
enum ShiftDatePolicy {
    static func dateToStore(
        existing: Date?,
        draft: Date,
        userEditedDate: Bool,
        calendar: Calendar = .current
    ) -> Date {
        if let existing, !userEditedDate {
            return calendar.startOfDay(for: existing)
        }
        return calendar.startOfDay(for: draft)
    }

    /// Minutes from midnight, wrapped inside a single day.
    /// An end earlier than the start stays an overnight shift in PayMath.
    static func clockMinutes(_ minutes: Int) -> Int {
        let day = 24 * 60
        let wrapped = minutes % day
        return wrapped >= 0 ? wrapped : wrapped + day
    }

    static func clockDate(minutes: Int, calendar: Calendar = .current) -> Date {
        let minute = clockMinutes(minutes)
        var parts = DateComponents()
        parts.year = 2001
        parts.month = 1
        parts.day = 1
        parts.hour = minute / 60
        parts.minute = minute % 60
        return calendar.date(from: parts) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func clockMinutes(from date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// A horizontal month swipe changes which month is visible.
    /// It does not move the selected day onto another date.
    static func selectedDayAfterMonthChange(
        selected: Date?,
        visibleMonth: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let selected else { return nil }
        guard calendar.isDate(selected, equalTo: visibleMonth, toGranularity: .month) else { return nil }
        return calendar.startOfDay(for: selected)
    }
}
