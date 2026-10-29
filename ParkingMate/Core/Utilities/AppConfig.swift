import Foundation
import CoreLocation

/// Central place for constants so nothing is "magic" elsewhere in the app.
enum AppConfig {
    static let currencyCode = "LKR"
    static let defaultHourlyRate: Double = 200
    /// Radius (metres) of the geofence drawn around a saved car.
    static let geofenceRadius: CLLocationDistance = 75
    /// Free public Overpass (OpenStreetMap) endpoint used for nearby parking facilities.
    static let overpassEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    /// Colombo – used as the map fallback before GPS is available.
    static var fallbackCenter: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612) }
    /// Must match the iCloud container you create in Signing & Capabilities.
    static var cloudKitContainerIdentifier: String {
        "iCloud." + (Bundle.main.bundleIdentifier ?? "com.nibm.parkingmate")
    }
    static let floorOptions = ["Roof", "L3", "L2", "L1", "G", "B1", "B2", "B3", "B4"]
    static let sectionOptions = ["Blue", "Red", "Green", "Yellow", "Orange", "Purple"]
    static let userAgent = "ParkingMate-iOS-Coursework/1.0 (NIBM BSCCOMP25.1P)"
}
