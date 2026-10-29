import Foundation
import CoreLocation
import CoreData
import Observation

/// Hint captured when Core Motion thinks the user just parked.
struct DetectionHint: Equatable {
    var floor: String?
    var detectedAt: Date
}

/// Composition root. Builds every service once and wires them together (manual dependency injection).
@MainActor
@Observable
final class AppContainer {
    let settings: AppSettings
    let persistence: PersistenceController
    let auth: AuthService
    let lock: AppLockController
    let store: ParkingStore
    let location: LocationService
    let notifications: NotificationService
    let facilities: FacilityProviding
    let routes: RouteProviding
    let sync: CloudSyncMonitor
    let motion: MotionActivityService
    let altitude: AltitudeService
    let voice: VoiceNoteService

    var pendingRoute: AppRoute?
    var detectionHint: DetectionHint?

    @ObservationIgnored private var remoteChangeTask: Task<Void, Never>?

    init(settings: AppSettings? = nil,
         persistence: PersistenceController? = nil,
         auth: AuthService? = nil,
         facilities: FacilityProviding? = nil,
         routes: RouteProviding? = nil) {
        let settings = settings ?? AppSettings()
        let persistence = persistence ?? PersistenceController.shared
        let auth = auth ?? AuthService()
        self.settings = settings
        self.persistence = persistence
        self.auth = auth
        self.facilities = facilities ?? FacilityService()
        self.routes = routes ?? MapKitRouteProvider()

        let location = LocationService()
        let notifications = NotificationService()
        self.location = location
        self.notifications = notifications
        self.sync = CloudSyncMonitor(isActive: persistence.isCloudKitActive)
        self.motion = MotionActivityService()
        self.altitude = AltitudeService()
        self.voice = VoiceNoteService()
        self.lock = AppLockController(isEnabled: { [settings] in settings.biometricLockEnabled },
                                      isSignedIn: { [auth] in auth.isSignedIn })

        let context = persistence.viewContext
        self.store = ParkingStore(parking: CoreDataParkingRepository(context: context),
                                  vehicles: CoreDataVehicleRepository(context: context),
                                  favorites: CoreDataFavoriteRepository(context: context),
                                  reminders: notifications, geofence: location, settings: settings)
        wire()
    }

    private func wire() {
        notifications.onExtend = { [weak self] id, minutes in _ = self?.store.extend(sessionID: id, byMinutes: minutes) }
        notifications.onOpenRoute = { [weak self] key in self?.pendingRoute = AppRoute(deepLinkKey: key) }
        location.onRegionEvent = { [weak self] event in self?.handle(event) }
        motion.onParked = { [weak self] in self?.handleParkingDetected() }

        // Pick up changes that arrive from iCloud / other processes (App Intents).
        remoteChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.store.reload()
            }
        }
    }

    /// Start sensors once the user is signed in.
    func startServices() {
        location.start()
        altitude.start()
        if settings.autoDetectParking { motion.start() }
        store.reload()
    }

    func applyAutoDetectSetting() {
        if settings.autoDetectParking { motion.start() } else { motion.stop() }
    }

    // MARK: Event handling

    private func handle(_ event: RegionEvent) {
        switch event {
        case .entered(let id):
            guard let session = store.session(id: id), session.isActive else { return }
            notifications.notifyNow(id: "near-\(id)", title: "You're near your car",
                                    body: "\(session.title) – \(session.locationLabel)", userInfo: ["route": "findMyCar"])
        case .exited(let id):
            guard let session = store.session(id: id), session.isActive else { return }
            var body = "\(session.locationLabel) is saved."
            if let left = session.remaining(at: .now) { body += " \(Formatters.duration(left)) left on your meter." }
            notifications.notifyNow(id: "left-\(id)", title: "You've left your parked car", body: body,
                                    userInfo: ["route": "timer"])
        }
    }

    private func handleParkingDetected() {
        detectionHint = DetectionHint(floor: altitude.estimatedFloor, detectedAt: .now)
        notifications.notifyNow(id: "parking-detected", title: "Did you just park?",
                                body: "Tap to save your spot in one step.", userInfo: ["route": "saveParking"])
        Haptics.success()
    }
}
