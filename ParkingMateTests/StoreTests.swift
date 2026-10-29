import Testing
import Foundation
import CoreLocation
@testable import ParkingMate

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
        env.now = env.now.addingTimeInterval(3 * 3600)       // meter ran out two hours ago
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
