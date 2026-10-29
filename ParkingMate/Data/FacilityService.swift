import Foundation
import CoreLocation

// MARK: - HTTP abstraction (so tests can stub the network)

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

// MARK: - Overpass (OpenStreetMap) response mapping

struct OverpassResponse: Decodable {
    struct Element: Decodable {
        struct Center: Decodable { let lat: Double; let lon: Double }
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?
    }
    let elements: [Element]
}

enum OverpassMapper {
    static func facilities(from data: Data) throws -> [ParkingFacility] {
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        return response.elements.compactMap { element in
            let tags = element.tags ?? [:]
            guard let lat = element.lat ?? element.center?.lat,
                  let lon = element.lon ?? element.center?.lon else { return nil }
            // Skip private/customer-only lots – they are no use to a visiting driver.
            if let access = tags["access"], ["private", "no", "permit"].contains(access) { return nil }

            let type = tags["parking"]
            let covered = tags["covered"] == "yes" || ["multi-storey", "underground", "rooftop"].contains(type ?? "")
            let ev = tags["capacity:charging"] != nil || tags["charging_station"] == "yes"
            let free: Bool?
            switch tags["fee"] {
            case "no": free = true
            case "yes": free = false
            default: free = nil
            }
            let name = tags["name"] ?? tags["operator"] ?? "Public parking"

            return ParkingFacility(id: "\(element.type)/\(element.id)", name: name, latitude: lat, longitude: lon,
                                   operatorName: tags["operator"], isFree: free, charge: tags["charge"],
                                   capacity: tags["capacity"].flatMap(Int.init), openingHours: tags["opening_hours"],
                                   isCovered: covered, hasEVCharging: ev, parkingType: type)
        }
    }
}

// MARK: - Cache (offline support)

protocol FacilityCaching {
    func load(key: String) -> [ParkingFacility]?
    func store(_ facilities: [ParkingFacility], key: String)
}

struct DiskFacilityCache: FacilityCaching {
    private var directory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Facilities", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func load(key: String) -> [ParkingFacility]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(key).json")) else { return nil }
        return try? JSONDecoder().decode([ParkingFacility].self, from: data)
    }
    func store(_ facilities: [ParkingFacility], key: String) {
        guard let data = try? JSONEncoder().encode(facilities) else { return }
        try? data.write(to: directory.appendingPathComponent("\(key).json"), options: .atomic)
    }
}

// MARK: - Service

struct FacilityResult {
    let facilities: [ParkingFacility]
    /// true when the network failed and the last saved result for this area is shown instead.
    let isFromCache: Bool
}

enum FacilityError: LocalizedError {
    case badResponse(Int)
    case offlineNoCache
    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "The parking service returned an error (\(code)). Try again shortly."
        case .offlineNoCache: "You're offline and no saved parking data exists for this area yet."
        }
    }
}

protocol FacilityProviding {
    func nearby(to coordinate: CLLocationCoordinate2D, radius: Int) async throws -> FacilityResult
}

/// REST integration (LO3): POSTs an Overpass QL query to the public OpenStreetMap Overpass API and maps
/// the JSON into `ParkingFacility` values. Results are cached per ~1 km tile for offline use.
struct FacilityService: FacilityProviding {
    var client: HTTPClient = URLSessionHTTPClient()
    var cache: FacilityCaching = DiskFacilityCache()
    var endpoint: URL = AppConfig.overpassEndpoint

    static func query(latitude: Double, longitude: Double, radius: Int) -> String {
        """
        [out:json][timeout:25];
        (
          node["amenity"="parking"](around:\(radius),\(latitude),\(longitude));
          way["amenity"="parking"](around:\(radius),\(latitude),\(longitude));
        );
        out center tags 80;
        """
    }

    static func cacheKey(for c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f_%.2f", c.latitude, c.longitude)
    }

    func nearby(to coordinate: CLLocationCoordinate2D, radius: Int = 1200) async throws -> FacilityResult {
        let key = Self.cacheKey(for: coordinate)
        let query = Self.query(latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = Data("data=\(encoded)".utf8)

        do {
            let (data, response) = try await client.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FacilityError.badResponse(http.statusCode)
            }
            let facilities = try OverpassMapper.facilities(from: data)
                .sorted { $0.distance(from: coordinate) < $1.distance(from: coordinate) }
            cache.store(facilities, key: key)
            return FacilityResult(facilities: facilities, isFromCache: false)
        } catch {
            if let cached = cache.load(key: key) { return FacilityResult(facilities: cached, isFromCache: true) }
            if error is URLError { throw FacilityError.offlineNoCache }
            throw error
        }
    }
}
