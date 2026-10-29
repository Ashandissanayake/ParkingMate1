import Foundation
import CoreLocation
import MapKit

/// Small, pure geometry helpers (unit-tested).
enum Geo {
    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Initial great-circle bearing from `a` to `b`, in degrees (0 ..< 360, 0 = north).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Wraps any angle into -180 ... 180.
    static func normalized(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a < -180 { a += 360 }
        return a
    }

    static func compassPoint(for bearing: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return points[max(0, min(points.count - 1, index))]
    }
}

extension MKMultiPoint {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

/// A Hashable wrapper so coordinates can travel inside navigation routes.
struct GeoPoint: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    init(_ c: CLLocationCoordinate2D) { latitude = c.latitude; longitude = c.longitude }
}

extension Geo {
    /// Spoken-style direction of the car relative to where the phone is pointing.
    /// `relativeBearing` = bearing to car − device heading (any angle).
    static func directionPhrase(relativeBearing: Double) -> String {
        let a = normalized(relativeBearing)
        switch abs(a) {
        case ..<20: return "straight ahead"
        case ..<70: return a > 0 ? "ahead and to your right" : "ahead and to your left"
        case ..<110: return a > 0 ? "to your right" : "to your left"
        case ..<160: return a > 0 ? "behind you to the right" : "behind you to the left"
        default: return "behind you"
        }
    }
}
