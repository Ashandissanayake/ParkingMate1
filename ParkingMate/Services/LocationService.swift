import Foundation
import CoreLocation
import Observation

enum RegionEvent: Equatable {
    case entered(UUID)
    case exited(UUID)
}

@MainActor
protocol GeofenceManaging: AnyObject {
    func startMonitoring(sessionID: UUID, center: CLLocationCoordinate2D, radius: CLLocationDistance)
    func stopMonitoring(sessionID: UUID)
}
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate, GeofenceManaging {
    private(set) var location: CLLocation?
    private(set) var heading: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored var onRegionEvent: ((RegionEvent) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 3
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var coordinate: CLLocationCoordinate2D? {
        if let coord = location?.coordinate {
            if abs(coord.latitude - 37.33) < 1.5 && abs(coord.longitude - (-122.03)) < 1.5 {
                return AppConfig.fallbackCenter
            }
            return coord
        }
        return AppConfig.fallbackCenter
    }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }
    func requestAlwaysPermission() {
        if authorization == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }

    func start() {
        requestPermission()
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func startMonitoring(sessionID: UUID, center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let r = min(radius, manager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: center, radius: r, identifier: sessionID.uuidString)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(sessionID: UUID) {
        for region in manager.monitoredRegions where region.identifier == sessionID.uuidString {
            manager.stopMonitoring(for: region)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.location = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let id = UUID(uuidString: region.identifier) else { return }
        Task { @MainActor in self.onRegionEvent?(.entered(id)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let id = UUID(uuidString: region.identifier) else { return }
        Task { @MainActor in self.onRegionEvent?(.exited(id)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}

