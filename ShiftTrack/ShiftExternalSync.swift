import EventKit
import Foundation

/// What to write into this app's own calendar and reminder list.
enum ShiftMirrorPlan {
    struct Event: Equatable {
        var shiftID: UUID
        var title: String
        var start: Date
        var end: Date
        var place: String
    }

    struct Reminder: Equatable {
        var todoID: UUID
        var title: String
        var due: Date
        var completed: Bool
    }

    static func events(
        _ rows: [ShiftNotice.Input],
        places: [UUID: String] = [:],
        now: Date,
        horizon: TimeInterval = 60 * 24 * 60 * 60
    ) -> [Event] {
        let limit = now.addingTimeInterval(horizon)
        return rows.compactMap { row in
            guard row.end > now, row.start <= limit else { return nil }
            let name = row.name.isEmpty ? "勤務" : row.name
            return Event(
                shiftID: row.id,
                title: name,
                start: row.start,
                end: row.end,
                place: places[row.id] ?? ""
            )
        }
    }

    static func reminders(
        _ items: [(id: UUID, title: String, due: Date, done: Bool)],
        now: Date,
        horizon: TimeInterval = 60 * 24 * 60 * 60
    ) -> [Reminder] {
        let limit = now.addingTimeInterval(horizon)
        return items.compactMap { item in
            guard item.due > now.addingTimeInterval(-24 * 60 * 60), item.due <= limit else { return nil }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return Reminder(todoID: item.id, title: title, due: item.due, completed: item.done)
        }
    }
}

enum ExternalMirrorError: Error {
    case noSource
}

/// Writes only into calendars this app created. Other calendars stay untouched.
@MainActor
final class ExternalMirror {
    static let shared = ExternalMirror()
    static let calendarTitle = "しふとらっく"
    private let store = EKEventStore()

    func requestEvents() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func requestReminders() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func syncEvents(_ events: [ShiftMirrorPlan.Event]) throws {
        let calendar = try ownedCalendar(for: .event)
        let start = Date().addingTimeInterval(-36 * 60 * 60)
        let end = Date().addingTimeInterval(70 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let existing = store.events(matching: predicate)
        var keep = Set<String>()
        for event in events {
            let key = event.shiftID.uuidString
            keep.insert(key)
            let item = existing.first { Self.key(of: $0.url) == key } ?? EKEvent(eventStore: store)
            item.calendar = calendar
            item.title = event.title
            item.startDate = event.start
            item.endDate = event.end
            item.location = event.place.isEmpty ? nil : event.place
            item.url = URL(string: "shifttrack://shift/\(key)")
            try store.save(item, span: .thisEvent, commit: false)
        }
        for old in existing where Self.isOurs(old.url) && !keep.contains(Self.key(of: old.url)) {
            try store.remove(old, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    func clearEvents() throws {
        try syncEvents([])
    }

    func syncReminders(_ reminders: [ShiftMirrorPlan.Reminder]) async throws {
        let calendar = try ownedCalendar(for: .reminder)
        let predicate = store.predicateForReminders(in: [calendar])
        let existing: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { items in
                continuation.resume(returning: items ?? [])
            }
        }
        var keep = Set<String>()
        for reminder in reminders {
            let key = reminder.todoID.uuidString
            keep.insert(key)
            let item = existing.first { Self.key(of: $0.url) == key } ?? EKReminder(eventStore: store)
            item.calendar = calendar
            item.title = reminder.title
            item.isCompleted = reminder.completed
            item.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.due
            )
            item.url = URL(string: "shifttrack://todo/\(key)")
            try store.save(item, commit: false)
        }
        for old in existing where Self.isOurs(old.url) && !keep.contains(Self.key(of: old.url)) {
            try store.remove(old, commit: false)
        }
        try store.commit()
    }

    func clearReminders() async throws {
        try await syncReminders([])
    }

    private func ownedCalendar(for entity: EKEntityType) throws -> EKCalendar {
        if let found = store.calendars(for: entity).first(where: { $0.title == Self.calendarTitle }) {
            return found
        }
        let calendar = EKCalendar(for: entity, eventStore: store)
        calendar.title = Self.calendarTitle
        let source = store.sources.first { $0.sourceType == .local }
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.defaultCalendarForNewEvents?.source
        guard let source else { throw ExternalMirrorError.noSource }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private static func isOurs(_ url: URL?) -> Bool {
        url?.scheme == "shifttrack"
    }

    private static func key(of url: URL?) -> String {
        url?.lastPathComponent ?? ""
    }
}

enum ShiftMirrorRefresh {
    static let calendarKey = "settings.mirrorCalendar"
    static let reminderKey = "settings.mirrorReminders"

    @MainActor
    static func apply(shifts: [WorkShift]) async {
        let defaults = UserDefaults.standard
        let rows = shifts.map { shift -> (ShiftNotice.Input, String, [ShiftTodoCodec.Item]) in
            let span = ShiftNotices.interval(
                day: shift.date,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                calendar: .current
            )
            let input = ShiftNotice.Input(
                id: shift.uuid,
                name: shift.workplace?.name ?? "勤務",
                start: span.start,
                end: span.end
            )
            return (input, shift.workplace?.place ?? "", shift.todos)
        }
        if defaults.bool(forKey: calendarKey),
           EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let events = ShiftMirrorPlan.events(
                rows.map(\.0),
                places: Dictionary(uniqueKeysWithValues: rows.map { ($0.0.id, $0.1) }),
                now: .now
            )
            try? ExternalMirror.shared.syncEvents(events)
        }
        if defaults.bool(forKey: reminderKey),
           EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let items = rows.flatMap { row in
                row.2.map { todo in
                    (id: todo.id, title: todo.title, due: row.0.start, done: todo.done)
                }
            }
            let reminders = ShiftMirrorPlan.reminders(items, now: .now)
            try? await ExternalMirror.shared.syncReminders(reminders)
        }
    }
}
