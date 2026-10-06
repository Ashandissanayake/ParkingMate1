import Foundation
import CoreLocation
import CoreData
import Observation
struct DetectionHint: Equatable {
    var floor: String?
    var detectedAt: Date
}
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
    let firebase: FirebaseService
    let voiceAnnouncement: VoiceAnnouncementService
    let bluetooth: BluetoothParkingService

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
        self.firebase = FirebaseService.shared
        self.voiceAnnouncement = VoiceAnnouncementService.shared
        self.bluetooth = BluetoothParkingService.shared
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
        bluetooth.onCarDisconnected = { [weak self] in self?.handleCarDisconnected() }
        remoteChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.store.reload()
            }
        }
    }
    func startServices() {
        location.start()
        altitude.start()
        if settings.autoDetectParking { motion.start() }
        if settings.bluetoothAutoSaveEnabled { bluetooth.startMonitoring() }
        store.reload()
    }

    func applyAutoDetectSetting() {
        if settings.autoDetectParking { motion.start() } else { motion.stop() }
    }

    func applyBluetoothSetting() {
        if settings.bluetoothAutoSaveEnabled { bluetooth.startMonitoring() } else { bluetooth.stopMonitoring() }
    }

    private func handle(_ event: RegionEvent) {
        switch event {
        case .entered(let id):
            guard let session = store.session(id: id), session.isActive else { return }
            notifications.notifyNow(id: "near-\(id)", title: "You're near your car",
                                    body: "\(session.title) – \(session.locationLabel)", userInfo: ["route": "findMyCar"])
        case .exited(let id):
            guard let session = store.session(id: id), session.isActive else { return }
            if settings.autoCheckoutEnabled {
                let duration = Date().timeIntervalSince(session.startDate)
                let cost = session.cost(at: .now)
                let costFormatted = Formatters.currency(cost)
                let durationFormatted = Formatters.duration(duration)
                _ = store.endActiveSession()
                notifications.notifyNow(id: "auto-checkout-\(id)",
                                        title: "🏁 Smart Checkout Complete",
                                        body: "Departed \(session.title). Duration: \(durationFormatted), Total: \(costFormatted).",
                                        userInfo: ["route": "history"])
                if settings.voiceAnnouncementsEnabled {
                    voiceAnnouncement.announceCheckout(title: session.title, cost: cost, duration: durationFormatted)
                }
                Haptics.success()
                return
            }

            var body = "\(session.locationLabel) is saved."
            if let left = session.remaining(at: .now) { body += " \(Formatters.duration(left)) left on your meter." }
            notifications.notifyNow(id: "left-\(id)", title: "You've left your parked car", body: body,
                                    userInfo: ["route": "timer"])
        }
    }

    private func handleCarDisconnected() {
        guard settings.bluetoothAutoSaveEnabled else { return }
        guard store.activeSession == nil else { return }

        var coord = location.coordinate ?? AppConfig.fallbackCenter
        if coord.latitude < 5.9 || coord.latitude > 9.9 || coord.longitude < 79.5 || coord.longitude > 82.0 {
            coord = AppConfig.fallbackCenter
        }

        let vehicle = store.defaultVehicle ?? store.vehicles.first
        let session = ParkingSession(
            id: UUID(),
            title: "Auto-Saved (Car Disconnected)",
            latitude: coord.latitude,
            longitude: coord.longitude,
            address: "Colombo, Sri Lanka",
            floor: altitude.estimatedFloor ?? "G",
            section: "Blue",
            space: "Auto Bay",
            note: "Automatically saved when car Bluetooth or CarPlay disconnected.",
            photoData: nil,
            voiceNoteFileName: nil,
            voiceTranscript: "",
            startDate: .now,
            expiryDate: Date().addingTimeInterval(7200),
            endDate: nil,
            hourlyRate: settings.defaultHourlyRate,
            vehicleID: vehicle?.id
        )

        if store.startSession(session) {
            notifications.notifyNow(
                id: "bluetooth-auto-saved",
                title: "🚗 Car Disconnected — Spot Saved!",
                body: "Your parking location was automatically saved at \(session.locationLabel).",
                userInfo: ["route": "findMyCar"]
            )
            if settings.voiceAnnouncementsEnabled {
                voiceAnnouncement.announceParkingSaved(session: session)
            }
            Haptics.success()
        }
    }

    private func handleParkingDetected() {
        detectionHint = DetectionHint(floor: altitude.estimatedFloor, detectedAt: .now)
        notifications.notifyNow(id: "parking-detected", title: "Did you just park?",
                                body: "Tap to save your spot in one step.", userInfo: ["route": "saveParking"])
        Haptics.success()
    }
}
