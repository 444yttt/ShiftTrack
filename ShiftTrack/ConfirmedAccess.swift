import CoreLocation
import EventKit
import Foundation
import UserNotifications

/// Symbol names tied to one screen. Where a symbol sits on that screen is not
/// part of the finding, except the hours-stock control, which is the close mark.
enum ConfirmedSymbols {
    static let aboutChevron = "chevron.right"
    static let aboutArrow = "arrow.up.right"
    static let planner = "briefcase.fill"
    static let hoursStockClose = "xmark"

    /// An unchecked todo uses `circle`. A checked item is not an SF Symbol name.
    static func todoMark(done: Bool) -> String? {
        done ? nil : "circle"
    }
}

enum SettingsAccess {
    /// Bit 1, 2, and 4. The settings call passes this set as the value 7.
    static let notificationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

    static var notificationOptionBits: Int {
        Int(notificationOptions.rawValue)
    }

    @MainActor
    static func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: notificationOptions)) ?? false
    }

    /// Separate from the notification request. Does not read or write events.
    @MainActor
    static func requestFullCalendar() async -> Bool {
        let store = EKEventStore()
        return await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum ImportReverseGeocode {
    struct Parts: Equatable {
        var administrativeArea: String?
        var locality: String?
        var subLocality: String?
        var thoroughfare: String?
        var subThoroughfare: String?
    }

    static func address(from parts: Parts) -> String {
        [parts.administrativeArea, parts.locality, parts.subLocality, parts.thoroughfare, parts.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
    }

    /// A filled or hand-edited address stays. An empty unread field can be filled.
    static func shouldFill(current: String, edited: Bool) -> Bool {
        !edited && current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func line(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let line = address(from: Parts(
            administrativeArea: mark.administrativeArea,
            locality: mark.locality,
            subLocality: mark.subLocality,
            thoroughfare: mark.thoroughfare,
            subThoroughfare: mark.subThoroughfare
        ))
        return line.isEmpty ? nil : line
    }
}
