import Foundation
import MapKit

struct RouteStep: Equatable {
    let instructions: String
    let distance: CLLocationDistance
    let endCoordinate: CLLocationCoordinate2D

    static func == (l: RouteStep, r: RouteStep) -> Bool {
        l.instructions == r.instructions && l.distance == r.distance
            && l.endCoordinate.latitude == r.endCoordinate.latitude
            && l.endCoordinate.longitude == r.endCoordinate.longitude
    }
}

struct WalkingRoute {
    let polyline: MKPolyline
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let steps: [RouteStep]
}

protocol RouteProviding {
    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkingRoute
}

/// MapKit pedestrian directions (MKDirections) from the user to the parked car.
struct MapKitRouteProvider: RouteProviding {
    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkingRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw URLError(.resourceUnavailable) }
        let steps = route.steps.compactMap { step -> RouteStep? in
            guard !step.instructions.isEmpty, let end = step.polyline.coordinates.last else { return nil }
            return RouteStep(instructions: step.instructions, distance: step.distance, endCoordinate: end)
        }
        return WalkingRoute(polyline: route.polyline, distance: route.distance,
                            expectedTravelTime: route.expectedTravelTime, steps: steps)
    }
}
