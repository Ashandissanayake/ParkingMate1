import Foundation
import CoreLocation
import Observation
@MainActor
@Observable
final class ParkingStore {
    private(set) var sessions: [ParkingSession] = []
    private(set) var vehicles: [Vehicle] = []
    private(set) var favorites: [FavoriteLocation] = []
    var lastError: String?

    @ObservationIgnored private let parkingRepo: ParkingRepository
    @ObservationIgnored private let vehicleRepo: VehicleRepository
    @ObservationIgnored private let favoriteRepo: FavoriteRepository
    @ObservationIgnored private let reminders: ReminderScheduling
    @ObservationIgnored private let geofence: GeofenceManaging
    @ObservationIgnored private let settings: StoreSettings
    @ObservationIgnored private let clock: () -> Date

    init(parking: ParkingRepository, vehicles: VehicleRepository, favorites: FavoriteRepository,
         reminders: ReminderScheduling, geofence: GeofenceManaging, settings: StoreSettings,
         clock: @escaping () -> Date = { Date() }) {
        self.parkingRepo = parking
        self.vehicleRepo = vehicles
        self.favoriteRepo = favorites
        self.reminders = reminders
        self.geofence = geofence
        self.settings = settings
        self.clock = clock
        reload()
    }

    var activeSession: ParkingSession? { sessions.first(where: \.isActive) }
    var history: [ParkingSession] { sessions.filter { !$0.isActive } }
    var defaultVehicle: Vehicle? { vehicles.first(where: \.isDefault) ?? vehicles.first }

    func session(id: UUID) -> ParkingSession? { sessions.first { $0.id == id } }
    func vehicle(id: UUID?) -> Vehicle? { id.flatMap { id in vehicles.first { $0.id == id } } }

    func reload() {
        do {
            sessions = try parkingRepo.fetchAll()
            vehicles = try vehicleRepo.fetchAll()
            favorites = try favoriteRepo.fetchAll()
        } catch {
            lastError = "Couldn't load your data: \(error.localizedDescription)"
        }
    }
    @discardableResult
    func startSession(_ session: ParkingSession) -> Bool {
        for var other in sessions where other.isActive && other.id != session.id {
            other.endDate = clock()
            _ = persist { try parkingRepo.upsert(other) }
            stopSideEffects(for: other.id)
        }
        guard persist({ try parkingRepo.upsert(session) }) else { return false }
        reload()
        startSideEffects(for: session)
        return true
    }

    @discardableResult
    func endActiveSession() -> ParkingSession? {
        guard var session = activeSession else { return nil }
        session.endDate = clock()
        guard persist({ try parkingRepo.upsert(session) }) else { return nil }
        stopSideEffects(for: session.id)
        reload()
        return session
    }
    @discardableResult
    func extend(sessionID: UUID, byMinutes minutes: Int) -> ParkingSession? {
        guard minutes > 0, var target = self.session(id: sessionID), target.isActive else { return nil }
        let base = max(target.expiryDate ?? clock(), clock())
        target.expiryDate = base.addingTimeInterval(Double(minutes) * 60)
        let updated = target
        guard persist({ try parkingRepo.upsert(updated) }) else { return nil }
        reload()
        scheduleReminders(for: updated)
        return updated
    }

    func update(_ session: ParkingSession) {
        guard persist({ try parkingRepo.upsert(session) }) else { return }
        reload()
        if session.isActive { scheduleReminders(for: session) }
    }

    func delete(_ session: ParkingSession) {
        guard persist({ try parkingRepo.delete(id: session.id) }) else { return }
        if let file = session.voiceNoteFileName {
            try? FileManager.default.removeItem(at: VoiceNoteStorage.url(for: file))
        }
        stopSideEffects(for: session.id)
        reload()
    }
    func refreshReminders() {
        guard let active = activeSession else { return }
        scheduleReminders(for: active)
    }

    func addVehicle(_ vehicle: Vehicle) {
        var v = vehicle
        if vehicles.isEmpty { v.isDefault = true }
        guard persist({ try vehicleRepo.upsert(v) }) else { return }
        reload()
        Task {
            try? await FirebaseService.shared.syncVehicle(v, userId: "user")
        }
    }

    func setDefaultVehicle(id: UUID) {
        for var v in vehicles {
            let shouldBeDefault = v.id == id
            if v.isDefault != shouldBeDefault {
                v.isDefault = shouldBeDefault
                _ = persist { try vehicleRepo.upsert(v) }
            }
        }
        reload()
    }

    func deleteVehicle(id: UUID) {
        let wasDefault = vehicles.first { $0.id == id }?.isDefault ?? false
        guard persist({ try vehicleRepo.delete(id: id) }) else { return }
        reload()
        if wasDefault, let first = vehicles.first { setDefaultVehicle(id: first.id) }
    }

    func addFavorite(_ favorite: FavoriteLocation) {
        guard persist({ try favoriteRepo.upsert(favorite) }) else { return }
        reload()
    }

    func deleteFavorite(id: UUID) {
        guard persist({ try favoriteRepo.delete(id: id) }) else { return }
        reload()
    }

    private func startSideEffects(for session: ParkingSession) {
        scheduleReminders(for: session)
        if settings.geofenceAlertsEnabled {
            geofence.startMonitoring(sessionID: session.id, center: session.coordinate, radius: AppConfig.geofenceRadius)
        }
        Task {
            try? await FirebaseService.shared.syncParkingSession(session, userId: "user")
        }
    }

    private func stopSideEffects(for id: UUID) {
        reminders.cancel(sessionID: id)
        geofence.stopMonitoring(sessionID: id)
    }

    private func scheduleReminders(for session: ParkingSession) {
        if settings.remindersEnabled {
            reminders.schedule(for: session, leadMinutes: settings.reminderLeadMinutes)
        } else {
            reminders.cancel(sessionID: session.id)
        }
    }

    @discardableResult
    private func persist(_ work: () throws -> Void) -> Bool {
        do { try work(); return true }
        catch { lastError = "Couldn't save: \(error.localizedDescription)"; return false }
    }
}

