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

    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        Geo.distance(from: origin, to: session.coordinate)
    }

    func bearing(from origin: CLLocationCoordinate2D) -> Double {
        Geo.bearing(from: origin, to: session.coordinate)
    }

    func hasArrived(from origin: CLLocationCoordinate2D) -> Bool {
        distance(from: origin) <= Self.arrivalThreshold
    }

    /// First step whose end point the user hasn't reached yet.
    func currentStep(from origin: CLLocationCoordinate2D) -> RouteStep? {
        route?.steps.first { Geo.distance(from: origin, to: $0.endCoordinate) > 20 }
    }

    func shouldReroute(from origin: CLLocationCoordinate2D) -> Bool {
        guard let lastOrigin else { return true }
        return Geo.distance(from: lastOrigin, to: origin) > Self.rerouteThreshold
    }

    /// Fetches a pedestrian route. Indoors / in garages MapKit may have no path – the radar still works then.
    func loadRoute(from origin: CLLocationCoordinate2D) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        lastOrigin = origin
        do {
            route = try await routes.walkingRoute(from: origin, to: session.coordinate)
            routeError = nil
        } catch {
            route = nil
            routeError = "No walking route found – follow the compass arrow instead."
        }
    }
}
