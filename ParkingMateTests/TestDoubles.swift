import Foundation
import CoreLocation
@testable import ParkingMate

// MARK: - In-Memory Secrets (for AuthTests)

final class InMemorySecrets: SecretStoring {
    private var storage: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws {
        storage[key] = data
    }

    func get(_ key: String) -> Data? {
        storage[key]
    }

    func remove(_ key: String) {
        storage.removeValue(forKey: key)
    }
}

// MARK: - Fake Repositories (for StoreTests)

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

// MARK: - Fake Services (for StoreTests)

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

// MARK: - Test Fixtures

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
