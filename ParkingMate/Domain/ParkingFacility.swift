import Foundation
import CoreLocation

/// A public parking facility returned by the external OpenStreetMap / Overpass REST API.
struct ParkingFacility: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var operatorName: String?
    /// true = free, false = paid, nil = unknown
    var isFree: Bool?
    var charge: String?
    var capacity: Int?
    var openingHours: String?
    var isCovered: Bool
    var hasEVCharging: Bool
    var parkingType: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        Geo.distance(from: origin, to: coordinate)
    }

    var feeSummary: String {
        if let charge, !charge.isEmpty { return charge }
        switch isFree {
        case true?: return "Free"
        case false?: return "Paid"
        default: return "Fee unknown"
        }
    }
}

/// Filters shown as chips on the nearby-parking screen ("All", "Free", "Covered", "EV Charging").
enum FacilityFilter: String, CaseIterable, Identifiable {
    case all = "All", free = "Free", covered = "Covered", ev = "EV Charging"
    var id: String { rawValue }
    var symbol: String? {
        switch self {
        case .all: nil
        case .free: "tag.fill"
        case .covered: "building.2.fill"
        case .ev: "bolt.car.fill"
        }
    }
    func matches(_ f: ParkingFacility) -> Bool {
        switch self {
        case .all: true
        case .free: f.isFree == true
        case .covered: f.isCovered
        case .ev: f.hasEVCharging
        }
    }
}
