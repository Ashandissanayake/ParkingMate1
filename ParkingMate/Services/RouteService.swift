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

/// MapKit directions provider with smart fallbacks (Walking -> Driving -> Direct Navigation Path).
struct MapKitRouteProvider: RouteProviding {
    func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> WalkingRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        // 1. Try MapKit pedestrian walking directions
        if let response = try? await MKDirections(request: request).calculate(),
           let route = response.routes.first {
            let steps = route.steps.compactMap { step -> RouteStep? in
                guard !step.instructions.isEmpty, let end = step.polyline.coordinates.last else { return nil }
                return RouteStep(instructions: step.instructions, distance: step.distance, endCoordinate: end)
            }
            return WalkingRoute(polyline: route.polyline, distance: route.distance,
                                expectedTravelTime: route.expectedTravelTime, steps: steps)
        }

        // 2. Try driving road network if pedestrian sidewalks aren't mapped in this region
        request.transportType = .automobile
        if let response = try? await MKDirections(request: request).calculate(),
           let route = response.routes.first {
            let steps = route.steps.compactMap { step -> RouteStep? in
                guard !step.instructions.isEmpty, let end = step.polyline.coordinates.last else { return nil }
                return RouteStep(instructions: step.instructions, distance: step.distance, endCoordinate: end)
            }
            return WalkingRoute(polyline: route.polyline, distance: route.distance,
                                expectedTravelTime: route.expectedTravelTime * 2.5, steps: steps)
        }

        // 3. Fallback direct path between coordinates so the line ALWAYS displays on map!
        var coordinates = [from, to]
        let polyline = MKPolyline(coordinates: &coordinates, count: 2)
        let distance = Geo.distance(from: from, to: to)
        let travelTime = max(60, distance / 1.3)
        let step = RouteStep(instructions: "Follow the direct path towards your car", distance: distance, endCoordinate: to)
        return WalkingRoute(polyline: polyline, distance: distance, expectedTravelTime: travelTime, steps: [step])
    }
}
