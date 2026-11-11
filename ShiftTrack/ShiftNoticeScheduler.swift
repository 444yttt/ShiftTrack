import Foundation
import UserNotifications

enum ShiftNoticeScheduler {
    static func replace(_ notices: [ShiftNotice]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ShiftNotice.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            var calendar = Calendar.current
            calendar.timeZone = .current
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notice.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

enum ShiftNoticeRefresh {
    static let beforeKey = "settings.notifyBeforeShift"
    static let endKey = "settings.notifyAtEnd"

    @MainActor
    static func apply(shifts: [WorkShift]) async {
        let defaults = UserDefaults.standard
        let before = defaults.bool(forKey: beforeKey)
        let atEnd = defaults.bool(forKey: endKey)
        let calendar = Calendar.current
        let rows = shifts.map { shift in
            let span = ShiftNotices.interval(
                day: shift.date,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                calendar: calendar
            )
            return ShiftNotice.Input(
                id: shift.uuid,
                name: shift.workplace?.name ?? "勤務",
                start: span.start,
                end: span.end
            )
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        let plan = allowed ? ShiftNotices.plan(rows, now: .now, before: before, atEnd: atEnd) : []
        await ShiftNoticeScheduler.replace(plan)
    }
}
