import CoreLocation
import Foundation

/// One location fix for “現在地から住所を入れる”. Asks for when-in-use
/// permission only at that moment, then reverse-geocodes on the device.
@MainActor
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    static let shared = CurrentLocation()

    private let manager = CLLocationManager()
    private var fix: CheckedContinuation<CLLocation?, Never>?
    private var decision: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    enum Outcome: Equatable {
        case address(String, latitude: Double, longitude: Double)
        case notAllowed
        case notFound
    }

    func addressHere() async -> Outcome {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                decision = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return .notAllowed }
        let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            fix?.resume(returning: nil)
            fix = continuation
            manager.requestLocation()
        }
        guard let location else { return .notFound }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        guard let line = await ImportReverseGeocode.line(latitude: latitude, longitude: longitude) else { return .notFound }
        return .address(line, latitude: latitude, longitude: longitude)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let decided = manager.authorizationStatus != .notDetermined
        Task { @MainActor in
            guard decided else { return }
            self.decision?.resume()
            self.decision = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            self.fix?.resume(returning: latest)
            self.fix = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.fix?.resume(returning: nil)
            self.fix = nil
        }
    }
}
