import Testing
import Foundation
import CoreLocation
@testable import parkingMate

// ==============================================================================
// MARK: - TEST DOUBLES & MOCKS (In-Memory Fakes for Unit Testing)
// ==============================================================================

/// In-Memory fake secret store to test AuthService without touching macOS/iOS Keychain.
final class InMemorySecrets: SecretStoring {
    private var storage: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws { storage[key] = data }
    func get(_ key: String) -> Data? { storage[key] }
    func remove(_ key: String) { storage.removeValue(forKey: key) }
}

enum FakeError: LocalizedError {
    case simulatedFailure
    var errorDescription: String? { "Simulated test failure" }
}

@MainActor
final class FakeParkingRepository: ParkingRepository {
    var shouldFail: Bool = false
    private var list: [ParkingSession] = []

    func fetchAll() throws -> [ParkingSession] {
        if shouldFail { throw FakeError.simulatedFailure }
        return list
    }

    func upsert(_ session: ParkingSession) throws {
        if shouldFail { throw FakeError.simulatedFailure }
        if let idx = list.firstIndex(where: { $0.id == session.id }) {
            list[idx] = session
        } else {
            list.append(session)
        }
    }

    func delete(id: UUID) throws {
        if shouldFail { throw FakeError.simulatedFailure }
        list.removeAll { $0.id == id }
    }
}

@MainActor
final class FakeVehicleRepository: VehicleRepository {
    var shouldFail: Bool = false
    private var list: [Vehicle] = []

    func fetchAll() throws -> [Vehicle] {
        if shouldFail { throw FakeError.simulatedFailure }
        return list
    }

    func upsert(_ vehicle: Vehicle) throws {
        if shouldFail { throw FakeError.simulatedFailure }
        if let idx = list.firstIndex(where: { $0.id == vehicle.id }) {
            list[idx] = vehicle
        } else {
            list.append(vehicle)
        }
    }

    func delete(id: UUID) throws {
        if shouldFail { throw FakeError.simulatedFailure }
        list.removeAll { $0.id == id }
    }
}

@MainActor
final class FakeFavoriteRepository: FavoriteRepository {
    var shouldFail: Bool = false
    private var list: [FavoriteLocation] = []

    func fetchAll() throws -> [FavoriteLocation] {
        if shouldFail { throw FakeError.simulatedFailure }
        return list
    }

    func upsert(_ favorite: FavoriteLocation) throws {
        if shouldFail { throw FakeError.simulatedFailure }
        if let idx = list.firstIndex(where: { $0.id == favorite.id }) {
            list[idx] = favorite
        } else {
            list.append(favorite)
        }
    }

    func delete(id: UUID) throws {
        if shouldFail { throw FakeError.simulatedFailure }
        list.removeAll { $0.id == id }
    }
}

@MainActor
final class FakeReminders: ReminderScheduling {
    var scheduled: [UUID: Date] = [:]

    func requestAuthorization() async -> Bool { true }

    func schedule(for session: ParkingSession, leadMinutes: Int) {
        if let expiry = session.expiryDate {
            scheduled[session.id] = expiry
        }
    }

    func cancel(sessionID: UUID) {
        scheduled.removeValue(forKey: sessionID)
    }

    func pendingReminders() async -> [PendingReminder] { [] }
    func notifyNow(id: String, title: String, body: String, userInfo: [String: String]) {}
}

@MainActor
final class FakeGeofence: GeofenceManaging {
    var monitored: Set<UUID> = []

    func startMonitoring(sessionID: UUID, center: CLLocationCoordinate2D, radius: CLLocationDistance) {
        monitored.insert(sessionID)
    }

    func stopMonitoring(sessionID: UUID) {
        monitored.remove(sessionID)
    }
}

struct FakeSettings: StoreSettings {
    var remindersEnabled: Bool = true
    var reminderLeadMinutes: Int = 15
    var geofenceAlertsEnabled: Bool = true
}

enum Fixtures {
    static let colombo = CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612)

    static func session(start: Date, minutes: Int? = 60) -> ParkingSession {
        ParkingSession(
            id: UUID(),
            title: "Colombo City Center",
            latitude: colombo.latitude,
            longitude: colombo.longitude,
            address: "Sir James Pieris Mawatha, Colombo 02",
            floor: "B1",
            section: "Blue",
            space: "A12",
            startDate: start,
            expiryDate: minutes.map { start.addingTimeInterval(Double($0) * 60) },
            endDate: nil,
            hourlyRate: 200
        )
    }
}

// ==============================================================================
// MARK: - SUITE 1: AUTHENTICATION & CREDENTIAL VALIDATION
// ==============================================================================

@Suite("CredentialValidator")
struct CredentialValidatorTests {
    @Test(arguments: ["a@b.co", "john.doe+tag@example.com", "ashan@gmail.com"])
    func validEmails(email: String) { #expect(CredentialValidator.isValidEmail(email)) }

    @Test(arguments: ["", "plain", "a@b", "@x.com", "a b@c.com"])
    func invalidEmails(email: String) { #expect(!CredentialValidator.isValidEmail(email)) }

    @Test func passwordStrength() {
        #expect(CredentialValidator.isStrongPassword("abc12345"))
        #expect(!CredentialValidator.isStrongPassword("short1"))
        #expect(!CredentialValidator.isStrongPassword("allletters"))
        #expect(!CredentialValidator.isStrongPassword("12345678"))
    }

    @Test func registrationIssuesInOrder() {
        #expect(CredentialValidator.validateRegistration(name: " ", email: "x", phone: "", password: "", confirm: "") == .emptyName)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "x", phone: "", password: "", confirm: "") == .invalidEmail)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "12", password: "", confirm: "") == .invalidPhone)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "", password: "weak", confirm: "weak") == .weakPassword)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "x") == .passwordMismatch)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "0771234567", password: "abc12345", confirm: "abc12345") == nil)
    }
}

@MainActor
@Suite("AuthService")
struct AuthServiceTests {
    private func makeService() -> AuthService {
        let defaults = UserDefaults(suiteName: "auth-tests-\(UUID().uuidString)")!
        return AuthService(secrets: InMemorySecrets(), defaults: defaults)
    }

    @Test func registerSignsInAndStoresNoPlaintext() throws {
        let secrets = InMemorySecrets()
        let service = AuthService(secrets: secrets, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try service.register(fullName: "Ashan D", email: "Ashan@Gmail.com", phone: "", password: "abc12345", confirm: "abc12345")
        #expect(service.isSignedIn)
        #expect(service.currentUser?.email == "ashan@gmail.com")
        let stored = try #require(secrets.get("ashan@gmail.com"))
        #expect(String(data: stored, encoding: .utf8)?.contains("abc12345") != true)
    }

    @Test func duplicateEmailRejected() throws {
        let s = makeService()
        try s.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        s.signOut()
        #expect(throws: AuthError.emailAlreadyRegistered) {
            try s.register(fullName: "B", email: "A@B.com", phone: "", password: "abc12345", confirm: "abc12345")
        }
    }

    @Test func signInChecksPassword() throws {
        let s = makeService()
        try s.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        s.signOut()
        #expect(!s.isSignedIn)
        #expect(throws: AuthError.invalidCredentials) { try s.signIn(email: "a@b.com", password: "wrong") }
        try s.signIn(email: "a@b.com", password: "abc12345")
        #expect(s.isSignedIn)
    }

    @Test func passwordResetNeedsKnownAccount() throws {
        let s = makeService()
        #expect(throws: AuthError.accountNotFound) { try s.requestPasswordReset(email: "nobody@x.com") }
        try s.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        try s.requestPasswordReset(email: "a@b.com")
    }

    @Test func sessionSurvivesRelaunch() throws {
        let secrets = InMemorySecrets()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AuthService(secrets: secrets, defaults: defaults)
        try first.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        let second = AuthService(secrets: secrets, defaults: defaults)
        #expect(second.currentUser?.fullName == "A")
    }
}

// ==============================================================================
// MARK: - SUITE 2: PARKING STORE MANAGEMENT
// ==============================================================================

@MainActor
@Suite("ParkingStore")
struct ParkingStoreTests {
    @MainActor final class Env {
        let parking = FakeParkingRepository()
        let vehicles = FakeVehicleRepository()
        let favorites = FakeFavoriteRepository()
        let reminders = FakeReminders()
        let geofence = FakeGeofence()
        var now = Date(timeIntervalSince1970: 1_000_000)
        lazy var store = ParkingStore(parking: parking, vehicles: vehicles, favorites: favorites,
                                      reminders: reminders, geofence: geofence, settings: FakeSettings(),
                                      clock: { [unowned self] in self.now })
    }

    @Test func startSessionPersistsAndSchedulesSideEffects() {
        let env = Env()
        let s = Fixtures.session(start: env.now)
        #expect(env.store.startSession(s))
        #expect(env.store.activeSession?.id == s.id)
        #expect(env.reminders.scheduled[s.id] == s.expiryDate)
        #expect(env.geofence.monitored.contains(s.id))
    }

    @Test func onlyOneActiveSession() {
        let env = Env()
        let first = Fixtures.session(start: env.now)
        var second = Fixtures.session(start: env.now.addingTimeInterval(60)); second.title = "Airport"
        _ = env.store.startSession(first)
        env.now = env.now.addingTimeInterval(120)
        _ = env.store.startSession(second)
        #expect(env.store.activeSession?.title == "Airport")
        #expect(env.store.history.count == 1)
        #expect(env.store.history.first?.endDate == env.now)
        #expect(!env.geofence.monitored.contains(first.id))
    }

    @Test func endActiveSessionMovesToHistoryAndCancelsAlerts() {
        let env = Env()
        let s = Fixtures.session(start: env.now)
        _ = env.store.startSession(s)
        env.now = env.now.addingTimeInterval(3600)
        let ended = env.store.endActiveSession()
        #expect(ended?.endDate == env.now)
        #expect(env.store.activeSession == nil)
        #expect(env.reminders.scheduled[s.id] == nil)
        #expect(!env.geofence.monitored.contains(s.id))
    }

    @Test func extendAddsTimeToFutureExpiry() throws {
        let env = Env()
        let s = Fixtures.session(start: env.now, minutes: 60)
        _ = env.store.startSession(s)
        let updated = try #require(env.store.extend(sessionID: s.id, byMinutes: 30))
        #expect(updated.expiryDate == s.expiryDate!.addingTimeInterval(30 * 60))
        #expect(env.reminders.scheduled[s.id] == updated.expiryDate)
    }

    @Test func extendAfterExpiryCountsFromNow() throws {
        let env = Env()
        let s = Fixtures.session(start: env.now, minutes: 60)
        _ = env.store.startSession(s)
        env.now = env.now.addingTimeInterval(3 * 3600)
        let updated = try #require(env.store.extend(sessionID: s.id, byMinutes: 60))
        #expect(updated.expiryDate == env.now.addingTimeInterval(3600))
    }

    @Test func extendRejectsInvalidInput() {
        let env = Env()
        let s = Fixtures.session(start: env.now)
        _ = env.store.startSession(s)
        #expect(env.store.extend(sessionID: s.id, byMinutes: 0) == nil)
        #expect(env.store.extend(sessionID: UUID(), byMinutes: 30) == nil)
    }

    @Test func persistenceFailureSurfacesError() {
        let env = Env()
        env.parking.shouldFail = true
        #expect(env.store.startSession(Fixtures.session(start: env.now)) == false)
        #expect(env.store.lastError != nil)
        #expect(env.store.activeSession == nil)
    }

    @Test func firstVehicleBecomesDefaultAndDefaultMoves() {
        let env = Env()
        let a = Vehicle(name: "Corolla", plate: "ABC 1234")
        let b = Vehicle(kind: .motorcycle, name: "Dio", plate: "BDR 5678")
        env.store.addVehicle(a)
        env.store.addVehicle(b)
        #expect(env.store.defaultVehicle?.id == a.id)
        env.store.setDefaultVehicle(id: b.id)
        #expect(env.store.defaultVehicle?.id == b.id)
        #expect(env.store.vehicles.filter(\.isDefault).count == 1)
    }

    @Test func deletingDefaultVehiclePromotesAnother() {
        let env = Env()
        let a = Vehicle(name: "Corolla", plate: "A"), b = Vehicle(name: "Dio", plate: "B")
        env.store.addVehicle(a); env.store.addVehicle(b)
        env.store.deleteVehicle(id: a.id)
        #expect(env.store.defaultVehicle?.id == b.id)
    }

    @Test func favouritesAddAndRemove() {
        let env = Env()
        let fav = FavoriteLocation(name: "Airport", detail: "P3 - Red - C56", latitude: 7.18, longitude: 79.88)
        env.store.addFavorite(fav)
        #expect(env.store.favorites.count == 1)
        env.store.deleteFavorite(id: fav.id)
        #expect(env.store.favorites.isEmpty)
    }
}

// ==============================================================================
// MARK: - SUITE 3: SAVE PARKING VIEW MODEL
// ==============================================================================

@MainActor
@Suite("SaveParkingViewModel")
struct SaveParkingViewModelTests {
    private func makeVM(prefill: ParkingPrefill = ParkingPrefill()) -> SaveParkingViewModel {
        SaveParkingViewModel(prefill: prefill, defaultRate: 200, defaultVehicleID: nil, hint: nil)
    }

    @Test func requiresLocation() {
        #expect(throws: SaveParkingError.noLocation) { try makeVM().buildSession(coordinate: nil) }
    }

    @Test func buildsSessionWithTimer() throws {
        let vm = makeVM()
        vm.floor = "B2"; vm.section = "Blue"; vm.space = " a124 "; vm.durationMinutes = 90
        let now = Date(timeIntervalSince1970: 5_000)
        let s = try vm.buildSession(coordinate: Fixtures.colombo, now: now)
        #expect(s.space == "A124")
        #expect(s.expiryDate == now.addingTimeInterval(90 * 60))
        #expect(s.hourlyRate == 200)
        #expect(s.isActive)
    }

    @Test func timerCanBeDisabled() throws {
        let vm = makeVM(); vm.timerEnabled = false
        #expect(try vm.buildSession(coordinate: Fixtures.colombo).expiryDate == nil)
    }

    @Test func scannedNumberFillsSpace() {
        let vm = makeVM(); vm.applyScannedNumber("A124")
        #expect(vm.space == "A124")
    }

    @Test func detectionHintPrefillsFloor() {
        let vm = SaveParkingViewModel(prefill: ParkingPrefill(), defaultRate: 100, defaultVehicleID: nil,
                                      hint: DetectionHint(floor: "B3", detectedAt: Date()))
        #expect(vm.floor == "B3")
    }

    @Test func facilityPrefillSetsTitle() {
        let f = ParkingFacility(id: "node/1", name: "Galle Face Parking", latitude: 1, longitude: 2, operatorName: nil,
                                isFree: nil, charge: nil, capacity: nil, openingHours: nil, isCovered: false,
                                hasEVCharging: false, parkingType: nil)
        #expect(makeVM(prefill: ParkingPrefill(facility: f)).title == "Galle Face Parking")
    }
}

// ==============================================================================
// MARK: - SUITE 4: PARKING COST CALCULATOR (Coursework LO1 & LO2)
// ==============================================================================

@Suite("ParkingCostCalculator")
struct ParkingCostCalculatorTests {
    @Test func standardHourlyCost() {
        let cost = ParkingCostCalculator.cost(hourlyRate: 200, duration: 7200, graceMinutes: 0, incrementMinutes: 60)
        #expect(cost == 400)
    }

    @Test func fifteenMinuteBillingBlocks() {
        // 2h 15m (8100s) at LKR 200/hr in 15-min increments = LKR 450
        let cost = ParkingCostCalculator.cost(hourlyRate: 200, duration: 8100, graceMinutes: 0, incrementMinutes: 15)
        #expect(cost == 450)
    }

    @Test func partialBlockRoundsUp() {
        // 1h 2m (3720s) rounds up to 1h 15m = LKR 250
        let cost = ParkingCostCalculator.cost(hourlyRate: 200, duration: 3720, graceMinutes: 0, incrementMinutes: 15)
        #expect(cost == 250)
    }

    @Test func gracePeriodDeduction() {
        // 15-minute stay with 15-minute free grace period is LKR 0
        let cost = ParkingCostCalculator.cost(hourlyRate: 200, duration: 900, graceMinutes: 15, incrementMinutes: 15)
        #expect(cost == 0)
    }

    @Test func freeParkingAlwaysZero() {
        let cost = ParkingCostCalculator.cost(hourlyRate: 0, duration: 7200)
        #expect(cost == 0)
    }

    @Test func zeroOrNegativeDurationReturnsZero() {
        #expect(ParkingCostCalculator.cost(hourlyRate: 200, duration: 0) == 0)
        #expect(ParkingCostCalculator.cost(hourlyRate: 200, duration: -100) == 0)
    }
}

// ==============================================================================
// MARK: - SUITE 5: PARKING SESSION LOGIC
// ==============================================================================

@Suite("ParkingSessionLogic")
struct ParkingSessionLogicTests {
    @Test func activeStatusDependsOnEndDate() {
        var s = Fixtures.session(start: Date())
        #expect(s.isActive == true)
        s.endDate = Date()
        #expect(s.isActive == false)
    }

    @Test func locationLabelCombinesFloorSectionSpace() {
        var s = Fixtures.session(start: Date())
        s.floor = "B1"; s.section = "Blue"; s.space = "A124"
        #expect(s.locationLabel == "B1 • Blue • A124")
        s.section = ""
        #expect(s.locationLabel == "B1 • A124")
    }

    @Test func elapsedDurationIncreasesOverTime() {
        let start = Date(timeIntervalSince1970: 10_000)
        let s = Fixtures.session(start: start)
        #expect(s.elapsed(at: start.addingTimeInterval(3600)) == 3600)
    }

    @Test func remainingTimeAndExpiry() {
        let start = Date(timeIntervalSince1970: 10_000)
        let s = Fixtures.session(start: start, minutes: 60)
        let halfTime = start.addingTimeInterval(1800)
        let expiredTime = start.addingTimeInterval(3700)

        #expect(s.remaining(at: halfTime) == 1800)
        #expect(s.isExpired(at: halfTime) == false)
        #expect(s.isExpired(at: expiredTime) == true)
    }

    @Test func progressRatioCalculation() {
        let start = Date(timeIntervalSince1970: 10_000)
        let s = Fixtures.session(start: start, minutes: 60)
        let quarter = start.addingTimeInterval(15 * 60)
        let prog = s.progress(at: quarter)
        #expect(prog != nil)
        #expect(abs(prog! - 0.75) < 0.01)
    }
}

// ==============================================================================
// MARK: - SUITE 6: DISPLAY FORMATTERS
// ==============================================================================

@Suite("Formatters")
struct FormattersTests {
    @Test func distanceFormattingMetersAndKilometers() {
        #expect(Formatters.distance(85) == "85 m")
        #expect(Formatters.distance(450.4) == "450 m")
        #expect(Formatters.distance(1200) == "1.2 km")
        #expect(Formatters.distance(2540) == "2.5 km")
    }

    @Test func durationFormatting() {
        #expect(Formatters.duration(45 * 60) == "45m")
        #expect(Formatters.duration(60 * 60) == "1h")
        #expect(Formatters.duration(135 * 60) == "2h 15m")
    }

    @Test func clockFormattingHHMMSS() {
        #expect(Formatters.clock(3665) == "1:01:05")
        #expect(Formatters.clock(300) == "0:05:00")
    }

    @Test func currencyFormattingSriLankanRupees() {
        #expect(Formatters.currency(200) == "LKR 200")
        #expect(Formatters.currency(250.50) == "LKR 250.50")
    }
}

// ==============================================================================
// MARK: - SUITE 7: GEOMETRY & COMPASS
// ==============================================================================

@Suite("Geo")
struct GeoTests {
    @Test func compassPointsMatchCardinalBearings() {
        #expect(Geo.compassPoint(for: 0) == "N")
        #expect(Geo.compassPoint(for: 45) == "NE")
        #expect(Geo.compassPoint(for: 90) == "E")
        #expect(Geo.compassPoint(for: 135) == "SE")
        #expect(Geo.compassPoint(for: 180) == "S")
        #expect(Geo.compassPoint(for: 225) == "SW")
        #expect(Geo.compassPoint(for: 270) == "W")
        #expect(Geo.compassPoint(for: 315) == "NW")
        #expect(Geo.compassPoint(for: 358) == "N")
    }

    @Test func angleNormalization() {
        #expect(Geo.normalized(0) == 0)
        #expect(Geo.normalized(360) == 0)
        #expect(Geo.normalized(190) == -170)
        #expect(Geo.normalized(-200) == 160)
    }

    @Test func distanceBetweenColomboLandmarks() {
        let ccc = CLLocationCoordinate2D(latitude: 6.9174, longitude: 79.8569)
        let ogf = CLLocationCoordinate2D(latitude: 6.9272, longitude: 79.8450)
        let d = Geo.distance(from: ccc, to: ogf)
        #expect(d > 1400 && d < 2000)
    }
}

// ==============================================================================
// MARK: - SUITE 8: HISTORY SEARCH & FILTERING
// ==============================================================================

@Suite("SessionSearch")
struct SessionSearchTests {
    private func makeSessions() -> ([ParkingSession], [Vehicle]) {
        let car = Vehicle(name: "Toyota Corolla", plate: "CAB 1234")
        let bike = Vehicle(kind: .motorcycle, name: "Honda Dio", plate: "BDE 5678")
        let s1 = ParkingSession(id: UUID(), title: "Colombo City Centre", latitude: 6.9174, longitude: 79.8569,
                                address: "Sir James Pieris Mawatha", floor: "B1", section: "Blue", space: "A124",
                                note: "Near lift lobby", startDate: Date(timeIntervalSince1970: 1_000_000), vehicleID: car.id)
        let s2 = ParkingSession(id: UUID(), title: "One Galle Face", latitude: 6.9272, longitude: 79.8450,
                                address: "Galle Road", floor: "B2", section: "Green", space: "B205",
                                note: "Food court exit", startDate: Date(timeIntervalSince1970: 2_000_000), vehicleID: bike.id)
        return ([s1, s2], [car, bike])
    }

    @Test func searchByLocationNoteOrSpace() {
        let (sessions, vehicles) = makeSessions()
        let results = SessionSearch.filter(sessions, query: "A124", scope: .location, vehicles: vehicles)
        #expect(results.count == 1)
        #expect(results.first?.title == "Colombo City Centre")

        let lobbyResults = SessionSearch.filter(sessions, query: "lobby", scope: .location, vehicles: vehicles)
        #expect(lobbyResults.count == 1)
    }

    @Test func searchByFacilityTitle() {
        let (sessions, vehicles) = makeSessions()
        let results = SessionSearch.filter(sessions, query: "Galle Face", scope: .facility, vehicles: vehicles)
        #expect(results.count == 1)
        #expect(results.first?.title == "One Galle Face")
    }

    @Test func searchByVehiclePlateOrName() {
        let (sessions, vehicles) = makeSessions()
        let byPlate = SessionSearch.filter(sessions, query: "CAB 1234", scope: .vehicle, vehicles: vehicles)
        #expect(byPlate.count == 1)

        let byName = SessionSearch.filter(sessions, query: "Dio", scope: .vehicle, vehicles: vehicles)
        #expect(byName.count == 1)
        #expect(byName.first?.title == "One Galle Face")
    }

    @Test func emptyQueryReturnsAll() {
        let (sessions, vehicles) = makeSessions()
        let all = SessionSearch.filter(sessions, query: "", scope: .location, vehicles: vehicles)
        #expect(all.count == 2)
    }
}

// ==============================================================================
// MARK: - SUITE 9: SRI LANKA FACILITIES CATALOG
// ==============================================================================

@Suite("SriLankaFacilities")
struct SriLankaFacilitiesTests {
    @Test func catalogHasComprehensiveCoverage() {
        #expect(FacilityService.allSriLankaFacilities.count >= 30)
    }

    @Test func allFacilitiesWithinSriLankaBounds() {
        for f in FacilityService.allSriLankaFacilities {
            #expect(f.latitude >= 5.8 && f.latitude <= 9.9, "Latitude \(f.latitude) outside Sri Lanka for \(f.name)")
            #expect(f.longitude >= 79.5 && f.longitude <= 82.0, "Longitude \(f.longitude) outside Sri Lanka for \(f.name)")
            #expect(!f.name.isEmpty)
        }
    }

    @Test func facilityFiltersMatchCorrectly() {
        let free = ParkingFacility(id: "1", name: "Free Park", latitude: 6.9, longitude: 79.8,
                                   isFree: true, isCovered: false, hasEVCharging: false)
        let evCovered = ParkingFacility(id: "2", name: "EV Hub", latitude: 6.9, longitude: 79.8,
                                       isFree: false, isCovered: true, hasEVCharging: true)

        #expect(FacilityFilter.all.matches(free) == true)
        #expect(FacilityFilter.all.matches(evCovered) == true)
        #expect(FacilityFilter.free.matches(free) == true)
        #expect(FacilityFilter.free.matches(evCovered) == false)
        #expect(FacilityFilter.ev.matches(evCovered) == true)
        #expect(FacilityFilter.ev.matches(free) == false)
        #expect(FacilityFilter.covered.matches(evCovered) == true)
        #expect(FacilityFilter.covered.matches(free) == false)
    }
}

// ==============================================================================
// MARK: - SUITE 10: SMART BLUETOOTH AUTO-SAVE (Feature B)
// ==============================================================================

@MainActor
@Suite("BluetoothAutoSave")
struct BluetoothAutoSaveTests {
    @Test func simulatedDisconnectFiresCallback() {
        let bluetooth = BluetoothParkingService.shared
        var callbackFired = false
        bluetooth.onCarDisconnected = { callbackFired = true }

        bluetooth.simulateDisconnect()
        #expect(callbackFired == true)
        #expect(bluetooth.isCarConnected == false)
        #expect(bluetooth.lastEventDescription != nil)
    }

    @Test func startAndStopMonitoringTogglesState() {
        let bluetooth = BluetoothParkingService.shared
        bluetooth.startMonitoring()
        #expect(bluetooth.isMonitoring == true)
        bluetooth.stopMonitoring()
        #expect(bluetooth.isMonitoring == false)
        bluetooth.startMonitoring()
    }
}
