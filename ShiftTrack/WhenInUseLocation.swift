import CoreLocation
import Foundation

/// The location picker asks for when-in-use only when its flag is nonzero.
/// A function that is not a screen uses the same gate.
enum WhenInUseLocation {
    static func shouldRequest(flag: Int) -> Bool {
        flag != 0
    }

    @MainActor
    static func requestWhenInUse(flag: Int, manager: CLLocationManager = CLLocationManager()) {
        guard shouldRequest(flag: flag) else { return }
        manager.requestWhenInUseAuthorization()
    }
}
