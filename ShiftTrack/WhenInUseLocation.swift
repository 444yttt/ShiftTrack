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

/// Kept for the life of the process so the system permission dialog can appear.
final class LocationPrompt: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPrompt()
    private let manager = CLLocationManager()
    var onChange: (@MainActor () -> Void)?

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func request() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let change = onChange
        Task { @MainActor in change?() }
    }

    static func label(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return "許可済み"
        case .denied, .restricted:
            return "拒否されています"
        case .notDetermined:
            return "未設定"
        @unknown default:
            return "未設定"
        }
    }
}
