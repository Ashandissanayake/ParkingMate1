import Foundation
import CoreLocation
import MapKit
import Observation
@MainActor
@Observable
final class NearbyParkingViewModel {
    private(set) var facilities: [ParkingFacility] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isFromCache = false
    private(set) var center: CLLocationCoordinate2D
    var filter: FacilityFilter = .all
    var searchText = ""

    @ObservationIgnored private let provider: FacilityProviding

    init(provider: FacilityProviding = FacilityService(), center: CLLocationCoordinate2D = AppConfig.fallbackCenter) {
        self.provider = provider
        self.center = center
        self.facilities = FacilityService.allSriLankaFacilities
    }

    var filtered: [ParkingFacility] { facilities.filter(filter.matches) }

    func load(around coordinate: CLLocationCoordinate2D, radius: Int = 1200) async {
        center = coordinate
        if facilities.isEmpty { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await provider.nearby(to: coordinate, radius: radius)
            facilities = result.facilities
            isFromCache = result.isFromCache
        } catch {
            if facilities.isEmpty {
                facilities = FacilityService.allSriLankaFacilities
            }
            errorMessage = nil
        }
    }
    func search() async -> CLLocationCoordinate2D? {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            errorMessage = "Couldn't find “\(text)”."
            return nil
        }
        let coordinate = item.placemark.coordinate
        await load(around: coordinate)
        return coordinate
    }
}
