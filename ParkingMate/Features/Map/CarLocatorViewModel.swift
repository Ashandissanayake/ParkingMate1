import Foundation
import CoreLocation
import Observation
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
        if coord.latitude < 5.9 || coord.latitude > 9.9 || coord.longitude < 79.5 || coord.longitude > 82.0 {
            return AppConfig.fallbackCenter
        }
        return coord
    }

    var targetCoordinate: CLLocationCoordinate2D {
        sanitize(session.coordinate)
    }

    var walkerCoordinate: CLLocationCoordinate2D?

    func effectiveOrigin(from origin: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let clean = sanitize(origin)
        if Geo.distance(from: clean, to: targetCoordinate) < 40 {
            return CLLocationCoordinate2D(latitude: targetCoordinate.latitude + 0.0018, longitude: targetCoordinate.longitude + 0.0018)
        }
        return clean
    }

    var currentPosition: CLLocationCoordinate2D {
        walkerCoordinate ?? effectiveOrigin(from: lastOrigin ?? AppConfig.fallbackCenter)
    }

    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        Geo.distance(from: currentPosition, to: targetCoordinate)
    }

    func bearing(from origin: CLLocationCoordinate2D) -> Double {
        Geo.bearing(from: currentPosition, to: targetCoordinate)
    }

    func hasArrived(from origin: CLLocationCoordinate2D) -> Bool {
        distance(from: origin) <= Self.arrivalThreshold
    }
    func currentStep(from origin: CLLocationCoordinate2D) -> RouteStep? {
        route?.steps.first { Geo.distance(from: currentPosition, to: $0.endCoordinate) > 20 }
            ?? route?.steps.last
    }

    func shouldReroute(from origin: CLLocationCoordinate2D) -> Bool {
        guard let lastOrigin else { return true }
        return Geo.distance(from: sanitize(lastOrigin), to: sanitize(origin)) > Self.rerouteThreshold
    }
    func stepForward() {
        let current = currentPosition
        let target = targetCoordinate
        let d = Geo.distance(from: current, to: target)
        if d <= Self.arrivalThreshold { return }

        let ratio: Double = d > 60 ? 0.35 : 0.85
        let newLat = current.latitude + (target.latitude - current.latitude) * ratio
        let newLon = current.longitude + (target.longitude - current.longitude) * ratio
        walkerCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }
    func loadRoute(from origin: CLLocationCoordinate2D) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let cleanStart = effectiveOrigin(from: origin)
        let cleanTarget = targetCoordinate
        lastOrigin = cleanStart
        if walkerCoordinate == nil {
            walkerCoordinate = cleanStart
        }
        do {
            route = try await routes.walkingRoute(from: cleanStart, to: cleanTarget)
            routeError = nil
        } catch {
            route = nil
            routeError = "No walking route found – follow the compass arrow instead."
        }
    }
}

