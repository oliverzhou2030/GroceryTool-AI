import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var isAuthorized: Bool {
        #if os(macOS)
        authorizationStatus == .authorizedAlways
        #else
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #endif
    }

    var statusText: String {
        #if os(macOS)
        switch authorizationStatus {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Allowed while using the app"
        @unknown default: "Unknown"
        }
        #else
        switch authorizationStatus {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways, .authorizedWhenInUse: "Allowed while using the app"
        @unknown default: "Unknown"
        }
        #endif
    }

    func requestAccess() {
        errorMessage = nil
        location = nil
        #if os(macOS)
        if authorizationStatus == .notDetermined { manager.requestAlwaysAuthorization() }
        #else
        if authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        #endif
        if isAuthorized { manager.startUpdatingLocation() }
    }

    func refreshLocation() {
        guard isAuthorized else { requestAccess(); return }
        errorMessage = nil
        location = nil
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized { manager.startUpdatingLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor in
            self.location = newest
            self.errorMessage = nil
        }
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown { return }
        Task { @MainActor in self.errorMessage = error.localizedDescription }
    }
}
