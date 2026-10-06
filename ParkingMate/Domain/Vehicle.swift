import Foundation

struct Vehicle: Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case car, motorcycle, van, other
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .car: "car.fill"
            case .motorcycle: "motorcycle.fill"
            case .van: "truck.box.fill"
            case .other: "car.side.fill"
            }
        }
    }
    var id = UUID()
    var kind: Kind = .car
    var name: String
    var plate: String
    var isDefault = false
}

struct FavoriteLocation: Identifiable, Equatable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
    var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}
