import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation? = nil
    @Published var lastError: Error? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5 // meters
        authorizationStatus = manager.authorizationStatus
        if let loc = manager.location { lastLocation = loc }
    }

    /// Request 'when in use' authorization.
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Start a single location update (will update lastLocation when delegate fires)
    func requestLocation() {
        manager.requestLocation()
    }

    /// Helper to compute distance in meters between last known location and a coordinate
    func distanceTo(lat: Double, lon: Double) -> Double? {
        guard let loc = lastLocation else { return nil }
        let target = CLLocation(latitude: lat, longitude: lon)
        return loc.distance(from: target) // meters
    }

    /// Returns whether the last known location is within the given radius (meters). Also returns current accuracy in meters if available.
    func isWithinGeofence(lat: Double, lon: Double, radiusMeters: Double, maxAccuracyMeters: Double) -> (inside: Bool, distance: Double?, accuracy: Double?) {
        guard let loc = lastLocation else { return (false, nil, nil) }
        let dist = CLLocation(latitude: lat, longitude: lon).distance(from: loc)
        let acc = loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil
        let accuracyOk = (acc != nil) ? (acc! <= maxAccuracyMeters) : false
        return (dist <= radiusMeters && accuracyOk, dist, acc)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                // proactively request a location once authorized
                self.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = l
            self.lastError = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error
        }
    }
}
