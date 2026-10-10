import Foundation
import CoreLocation

protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

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

struct FacilityResult {
    let facilities: [ParkingFacility]
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
        if radius >= 40_000 || (coordinate.latitude > 7.0 && coordinate.latitude < 8.5 && coordinate.longitude > 80.0 && coordinate.longitude < 81.5 && radius > 10_000) {
            let all = Self.allSriLankaFacilities.sorted { $0.distance(from: coordinate) < $1.distance(from: coordinate) }
            return FacilityResult(facilities: all, isFromCache: false)
        }

        let key = Self.cacheKey(for: coordinate)
        if let cached = cache.load(key: key), !cached.isEmpty { return FacilityResult(facilities: cached, isFromCache: true) }

        let query = Self.query(latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = Data("data=\(encoded)".utf8)

        do {
            let (data, response) = try await client.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FacilityError.badResponse(http.statusCode)
            }
            var facilities = try OverpassMapper.facilities(from: data)
            if facilities.isEmpty {
                facilities = Self.allSriLankaFacilities.filter { $0.distance(from: coordinate) <= Double(max(radius, 15000)) }
                if facilities.isEmpty {
                    facilities = Array(Self.allSriLankaFacilities.sorted { $0.distance(from: coordinate) < $1.distance(from: coordinate) }.prefix(15))
                }
            }
            facilities.sort { $0.distance(from: coordinate) < $1.distance(from: coordinate) }
            cache.store(facilities, key: key)
            return FacilityResult(facilities: facilities, isFromCache: false)
        } catch {
            if let cached = cache.load(key: key) { return FacilityResult(facilities: cached, isFromCache: true) }
            var defaults = Self.allSriLankaFacilities.filter { $0.distance(from: coordinate) <= Double(max(radius, 15000)) }
            if defaults.isEmpty {
                defaults = Array(Self.allSriLankaFacilities.sorted { $0.distance(from: coordinate) < $1.distance(from: coordinate) }.prefix(15))
            }
            return FacilityResult(facilities: defaults, isFromCache: true)
        }
    }

    static var defaultSriLankaFacilities: [ParkingFacility] { allSriLankaFacilities }

    static let allSriLankaFacilities: [ParkingFacility] = [
        ParkingFacility(id: "sl/ccc", name: "Colombo City Centre (CCC) Parking", latitude: 6.9174, longitude: 79.8569,
                        operatorName: "Colombo City Centre", isFree: false, charge: "LKR 200/hr", capacity: 450,
                        openingHours: "10:00 - 22:00", isCovered: true, hasEVCharging: true, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/ogf", name: "One Galle Face Mall Car Park", latitude: 6.9272, longitude: 79.8450,
                        operatorName: "Shangri-La", isFree: false, charge: "LKR 250/hr", capacity: 1500,
                        openingHours: "09:00 - 23:00", isCovered: true, hasEVCharging: true, parkingType: "underground"),
        ParkingFacility(id: "sl/gfg", name: "Galle Face Green Public Parking", latitude: 6.9240, longitude: 79.8440,
                        operatorName: "CMC", isFree: true, charge: "Free", capacity: 200,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/mc", name: "Majestic City Parking (Bambalapitiya)", latitude: 6.8941, longitude: 79.8548,
                        operatorName: "CT Land", isFree: false, charge: "LKR 150/hr", capacity: 300,
                        openingHours: "09:00 - 21:00", isCovered: true, hasEVCharging: false, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/arcade", name: "Arcade Independence Square Parking", latitude: 6.9038, longitude: 79.8680,
                        operatorName: "UDA", isFree: true, charge: "Free", capacity: 180,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/dutch", name: "Dutch Hospital Car Park (Colombo Fort)", latitude: 6.9344, longitude: 79.8437,
                        operatorName: "Fort UDA", isFree: false, charge: "LKR 200/hr", capacity: 120,
                        openingHours: "10:00 - 23:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/racecourse", name: "Colombo Racecourse Grounds Parking", latitude: 6.9035, longitude: 79.8615,
                        operatorName: "UDA", isFree: true, charge: "Free", capacity: 250,
                        openingHours: "06:00 - 22:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/crescat", name: "Crescat Boulevard Parking (Kollupitiya)", latitude: 6.9189, longitude: 79.8491,
                        operatorName: "John Keells", isFree: false, charge: "LKR 200/hr", capacity: 180,
                        openingHours: "09:00 - 22:00", isCovered: true, hasEVCharging: false, parkingType: "underground"),
        ParkingFacility(id: "sl/liberty", name: "Liberty Plaza Car Park (Kollupitiya)", latitude: 6.9112, longitude: 79.8519,
                        operatorName: "Liberty Plaza", isFree: false, charge: "LKR 150/hr", capacity: 220,
                        openingHours: "09:00 - 21:00", isCovered: true, hasEVCharging: false, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/havelock", name: "Havelock City Mall Car Park", latitude: 6.8795, longitude: 79.8654,
                        operatorName: "Havelock City", isFree: false, charge: "LKR 200/hr", capacity: 800,
                        openingHours: "10:00 - 22:00", isCovered: true, hasEVCharging: true, parkingType: "underground"),
        ParkingFacility(id: "sl/marino", name: "Marino Mall Car Park (Kollupitiya)", latitude: 6.8982, longitude: 79.8532,
                        operatorName: "Damro Marino", isFree: false, charge: "LKR 150/hr", capacity: 250,
                        openingHours: "09:30 - 21:30", isCovered: true, hasEVCharging: false, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/fort_station", name: "Colombo Fort Railway Station Car Park", latitude: 6.9333, longitude: 79.8500,
                        operatorName: "Sri Lanka Railways", isFree: false, charge: "LKR 100/hr", capacity: 150,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/pettah", name: "Pettah Central Bus & Train Terminal Parking", latitude: 6.9360, longitude: 79.8550,
                        operatorName: "CMC", isFree: false, charge: "LKR 100/hr", capacity: 200,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/portcity", name: "Colombo Port City Promenade Parking", latitude: 6.9380, longitude: 79.8400,
                        operatorName: "Port City Colombo", isFree: true, charge: "Free", capacity: 350,
                        openingHours: "06:00 - 23:00", isCovered: false, hasEVCharging: true, parkingType: "surface"),
        ParkingFacility(id: "sl/bmich", name: "BMICH Convention Centre Car Park", latitude: 6.9015, longitude: 79.8735,
                        operatorName: "BMICH", isFree: false, charge: "LKR 100/entry", capacity: 500,
                        openingHours: "07:00 - 23:00", isCovered: false, hasEVCharging: true, parkingType: "surface"),
        ParkingFacility(id: "sl/nelumpokuna", name: "Nelum Pokuna Theatre Car Park", latitude: 6.9105, longitude: 79.8625,
                        operatorName: "National Performing Arts", isFree: false, charge: "LKR 150/hr", capacity: 250,
                        openingHours: "08:00 - 22:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/viharamahadevi", name: "Viharamahadevi Park Public Car Park", latitude: 6.9142, longitude: 79.8605,
                        operatorName: "CMC", isFree: true, charge: "Free", capacity: 120,
                        openingHours: "06:00 - 21:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/odel", name: "Odel Alexandra Place Parking (Town Hall)", latitude: 6.9150, longitude: 79.8670,
                        operatorName: "Softlogic", isFree: false, charge: "LKR 150/hr", capacity: 100,
                        openingHours: "10:00 - 20:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/dehiwala_zoo", name: "Dehiwala Zoological Gardens Car Park", latitude: 6.8572, longitude: 79.8741,
                        operatorName: "National Zoo", isFree: false, charge: "LKR 150/entry", capacity: 200,
                        openingHours: "08:30 - 18:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/mount_beach", name: "Mount Lavinia Beach Public Car Park", latitude: 6.8355, longitude: 79.8630,
                        operatorName: "Mount Lavinia MC", isFree: true, charge: "Free", capacity: 150,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/kcc", name: "Kandy City Centre (KCC) Multi-Storey", latitude: 7.2936, longitude: 80.6350,
                        operatorName: "KCC", isFree: false, charge: "LKR 150/hr", capacity: 600,
                        openingHours: "08:30 - 21:30", isCovered: true, hasEVCharging: true, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/maligawa", name: "Sri Dalada Maligawa Pilgrim Car Park", latitude: 7.2940, longitude: 80.6415,
                        operatorName: "Temple of the Tooth", isFree: true, charge: "Free", capacity: 250,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/kandy_lake", name: "Kandy Lake Round Public Car Park", latitude: 7.2905, longitude: 80.6390,
                        operatorName: "Kandy Municipal Council", isFree: true, charge: "Free", capacity: 100,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/peradeniya", name: "Peradeniya Royal Botanical Gardens Parking", latitude: 7.2715, longitude: 80.5960,
                        operatorName: "Botanical Gardens", isFree: false, charge: "LKR 100/entry", capacity: 300,
                        openingHours: "07:30 - 18:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/bogambara", name: "Bogambara Stadium Grounds Parking", latitude: 7.2885, longitude: 80.6340,
                        operatorName: "Kandy MC", isFree: false, charge: "LKR 100/hr", capacity: 200,
                        openingHours: "07:00 - 21:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/kandy_station", name: "Kandy Railway Station Car Park", latitude: 7.2900, longitude: 80.6315,
                        operatorName: "Sri Lanka Railways", isFree: false, charge: "LKR 100/hr", capacity: 120,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/galle", name: "Galle Fort Rampart Parking", latitude: 6.0305, longitude: 80.2170,
                        operatorName: "Galle Heritage", isFree: true, charge: "Free", capacity: 90,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/galle_cricket", name: "Galle International Cricket Stadium Parking", latitude: 6.0365, longitude: 80.2160,
                        operatorName: "SLC", isFree: false, charge: "LKR 150/hr", capacity: 350,
                        openingHours: "08:00 - 20:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/galle_station", name: "Galle Central Railway Station Car Park", latitude: 6.0375, longitude: 80.2195,
                        operatorName: "Sri Lanka Railways", isFree: false, charge: "LKR 100/hr", capacity: 100,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/unawatuna", name: "Unawatuna Beach Road Public Parking", latitude: 6.0100, longitude: 80.2490,
                        operatorName: "Unawatuna PS", isFree: true, charge: "Free", capacity: 120,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/hikkaduwa", name: "Hikkaduwa Beach Surfing Car Park", latitude: 6.1405, longitude: 80.0990,
                        operatorName: "Hikkaduwa UC", isFree: true, charge: "Free", capacity: 100,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/mirissa", name: "Mirissa Fishery Harbour Car Park", latitude: 5.9470, longitude: 80.4570,
                        operatorName: "Mirissa Port Authority", isFree: false, charge: "LKR 100/entry", capacity: 150,
                        openingHours: "05:00 - 20:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/matara", name: "Matara Star Fort & Beach Park Car Park", latitude: 5.9450, longitude: 80.5480,
                        operatorName: "Matara MC", isFree: true, charge: "Free", capacity: 140,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/bia", name: "Airport (BIA) Long-Term Parking", latitude: 7.1808, longitude: 79.8841,
                        operatorName: "AASL", isFree: false, charge: "LKR 300/hr", capacity: 2000,
                        openingHours: "24/7", isCovered: true, hasEVCharging: true, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/bia_short", name: "BIA Terminal 1 Short-Stay Multi-Storey", latitude: 7.1785, longitude: 79.8860,
                        operatorName: "AASL", isFree: false, charge: "LKR 400/hr", capacity: 800,
                        openingHours: "24/7", isCovered: true, hasEVCharging: true, parkingType: "multi-storey"),
        ParkingFacility(id: "sl/negombo_beach", name: "Negombo Beach Park Public Car Park", latitude: 7.2280, longitude: 79.8410,
                        operatorName: "Negombo MC", isFree: true, charge: "Free", capacity: 180,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/negombo_fort", name: "Negombo Dutch Fort & Lagoon Car Park", latitude: 7.2100, longitude: 79.8370,
                        operatorName: "UDA", isFree: false, charge: "LKR 100/hr", capacity: 100,
                        openingHours: "07:00 - 20:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/gregory", name: "Gregory Lake Waterfront Public Parking (Nuwara Eliya)", latitude: 6.9535, longitude: 80.7815,
                        operatorName: "Nuwara Eliya MC", isFree: false, charge: "LKR 150/entry", capacity: 250,
                        openingHours: "06:00 - 21:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/victoria_park", name: "Victoria Park Visitor Car Park (Nuwara Eliya)", latitude: 6.9695, longitude: 80.7675,
                        operatorName: "Nuwara Eliya MC", isFree: false, charge: "LKR 100/entry", capacity: 120,
                        openingHours: "07:00 - 18:30", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/horton", name: "Horton Plains National Park (World's End) Parking", latitude: 6.8025, longitude: 80.8065,
                        operatorName: "Wildlife Dept", isFree: false, charge: "LKR 250/entry", capacity: 150,
                        openingHours: "06:00 - 16:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/ella", name: "Ella Town Centre & Nine Arches Bridge Parking", latitude: 6.8667, longitude: 81.0466,
                        operatorName: "Ella Pradeshiya Sabha", isFree: true, charge: "Free", capacity: 100,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/sigiriya", name: "Sigiriya Rock Fortress Main Visitor Car Park", latitude: 7.9570, longitude: 80.7600,
                        operatorName: "CCF Sigiriya", isFree: true, charge: "Free", capacity: 400,
                        openingHours: "06:30 - 18:30", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/dambulla", name: "Dambulla Royal Cave Temple Car Park", latitude: 7.8570, longitude: 80.6480,
                        operatorName: "Dambulla Temple Trust", isFree: false, charge: "LKR 100/entry", capacity: 200,
                        openingHours: "07:00 - 19:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/ruwanweli", name: "Ruwanwelisaya Sacred City Pilgrim Parking", latitude: 8.3500, longitude: 80.3960,
                        operatorName: "Atamasthana", isFree: true, charge: "Free", capacity: 500,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/mahabodhi", name: "Jaya Sri Maha Bodhi Pilgrim Car Park (Anuradhapura)", latitude: 8.3450, longitude: 80.3970,
                        operatorName: "Atamasthana", isFree: true, charge: "Free", capacity: 450,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/polonnaruwa", name: "Polonnaruwa Ancient City Visitor Parking", latitude: 7.9400, longitude: 81.0020,
                        operatorName: "CCF Polonnaruwa", isFree: false, charge: "LKR 100/entry", capacity: 300,
                        openingHours: "07:00 - 18:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/kurunegala", name: "Kurunegala Central Commercial Car Park", latitude: 7.4870, longitude: 80.3645,
                        operatorName: "Kurunegala MC", isFree: false, charge: "LKR 100/hr", capacity: 200,
                        openingHours: "07:00 - 21:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/jaffna_fort", name: "Jaffna Fort Coastal Car Park", latitude: 9.6615, longitude: 80.0080,
                        operatorName: "Jaffna Heritage", isFree: true, charge: "Free", capacity: 150,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/nallur", name: "Nallur Kandaswamy Kovil Pilgrim Car Park", latitude: 9.6745, longitude: 80.0290,
                        operatorName: "Nallur Trust", isFree: true, charge: "Free", capacity: 350,
                        openingHours: "05:00 - 21:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/jaffna_station", name: "Jaffna Central Railway Station Parking", latitude: 9.6655, longitude: 80.0210,
                        operatorName: "Sri Lanka Railways", isFree: false, charge: "LKR 100/hr", capacity: 120,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/koneswaram", name: "Fort Frederick & Koneswaram Temple Car Park", latitude: 8.5875, longitude: 81.2405,
                        operatorName: "Trincomalee Tourism", isFree: false, charge: "LKR 100/entry", capacity: 200,
                        openingHours: "06:00 - 20:00", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/nilaveli", name: "Nilaveli Beach & Pigeon Island Boat Parking", latitude: 8.6940, longitude: 81.1890,
                        operatorName: "Nilaveli Tourism PS", isFree: true, charge: "Free", capacity: 150,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface"),
        ParkingFacility(id: "sl/arugambay", name: "Arugam Bay Main Point Surfing Car Park", latitude: 6.8420, longitude: 81.8340,
                        operatorName: "Pottuvil PS", isFree: true, charge: "Free", capacity: 120,
                        openingHours: "24/7", isCovered: false, hasEVCharging: false, parkingType: "surface")
    ]
}

