import Foundation
import CoreLocation
import Observation

/// Walking route + live distance/bearing from the user to the parked car.
@MainActor
@Observable
final class CarLocatorViewModel {
    let session: ParkingSession
    private(set) var route: WalkingRoute?
    private(set) var isLoading = false
    private(set) var routeError: String?
    @ObservationIgnored private let routes: RouteProviding
    @ObservationIgnored private var lastOrigin: CLLocationCoordinate2D?

    static let arrivalThreshold: CLLocationDistance = 15
    static let rerouteThreshold: CLLocationDistance = 40

    init(session: ParkingSession, routes: RouteProviding) {
        self.session = session
        self.routes = routes
    }

    private func sanitize(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // Ensure coordinate is within Sri Lanka bounds
        if coord.latitude < 5.9 || coord.latitude > 9.9 || coord.longitude < 79.5 || coord.longitude > 82.0 {
            return AppConfig.fallbackCenter
        }
        return coord
    }

    var targetCoordinate: CLLocationCoordinate2D {
        sanitize(session.coordinate)
    }

    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        Geo.distance(from: sanitize(origin), to: targetCoordinate)
    }

    func bearing(from origin: CLLocationCoordinate2D) -> Double {
        Geo.bearing(from: sanitize(origin), to: targetCoordinate)
    }

    func hasArrived(from origin: CLLocationCoordinate2D) -> Bool {
        distance(from: origin) <= Self.arrivalThreshold
    }

    /// First step whose end point the user hasn't reached yet.
    func currentStep(from origin: CLLocationCoordinate2D) -> RouteStep? {
        route?.steps.first { Geo.distance(from: sanitize(origin), to: $0.endCoordinate) > 20 }
    }

    func shouldReroute(from origin: CLLocationCoordinate2D) -> Bool {
        guard let lastOrigin else { return true }
        return Geo.distance(from: sanitize(lastOrigin), to: sanitize(origin)) > Self.rerouteThreshold
    }

    /// Fetches a pedestrian route. Indoors / in garages MapKit may have no path – the radar still works then.
    func loadRoute(from origin: CLLocationCoordinate2D) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let cleanOrigin = sanitize(origin)
        let cleanTarget = targetCoordinate
        lastOrigin = cleanOrigin
        do {
            route = try await routes.walkingRoute(from: cleanOrigin, to: cleanTarget)
            routeError = nil
        } catch {
            route = nil
            routeError = "No walking route found – follow the compass arrow instead."
        }
    }
}
