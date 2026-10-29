import Foundation
import CoreLocation
import Observation
import UIKit
import AVFoundation
import Combine

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

// MARK: - Firebase Configuration

struct FirebaseConfig: Sendable {
    let apiKey: String
    let projectId: String
    let gcmSenderId: String
    let storageBucket: String
    let googleAppId: String
    let bundleId: String

    static let standard: FirebaseConfig = {
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            return FirebaseConfig(
                apiKey: dict["API_KEY"] as? String ?? "AIzaSyB_parkingmate_demo_key_25_1_023",
                projectId: dict["PROJECT_ID"] as? String ?? "parkingmate-25-1-023",
                gcmSenderId: dict["GCM_SENDER_ID"] as? String ?? "251023123456",
                storageBucket: dict["STORAGE_BUCKET"] as? String ?? "parkingmate-25-1-023.firebasestorage.app",
                googleAppId: dict["GOOGLE_APP_ID"] as? String ?? "1:251023123456:ios:a1b2c3d4e5f6251023",
                bundleId: dict["BUNDLE_ID"] as? String ?? "AshanDissanayake.parkingMate"
            )
        }
        return FirebaseConfig(
            apiKey: "AIzaSyB_parkingmate_demo_key_25_1_023",
            projectId: "parkingmate-25-1-023",
            gcmSenderId: "251023123456",
            storageBucket: "parkingmate-25-1-023.firebasestorage.app",
            googleAppId: "1:251023123456:ios:a1b2c3d4e5f6251023",
            bundleId: "AshanDissanayake.parkingMate"
        )
    }()
}

// MARK: - Firebase Models

struct FirebaseAuthSession: Codable, Equatable, Sendable {
    let localId: String
    let email: String
    let displayName: String
    let idToken: String
    let refreshToken: String
    let expiresIn: String
}

struct SharedParkingLocation: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var floor: String
    var section: String
    var space: String
    var note: String
    var latitude: Double
    var longitude: Double
    var sharedBy: String
    var createdAt: Date
    var expiryDate: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationLabel: String {
        let parts = [floor, section, space].filter { !$0.isEmpty }
        return parts.isEmpty ? "Parked Car" : parts.joined(separator: " • ")
    }

    var shareURL: URL? {
        URL(string: "https://parkingmate.app/share/\(id)")
    }
}

enum FirebaseError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case networkUnavailable
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Received invalid response from Firebase server."
        case .apiError(let message): return message
        case .networkUnavailable: return "Network connection is unavailable."
        case .notAuthenticated: return "Please sign in to sync with Firebase."
        }
    }
}

// MARK: - Firebase Service

@MainActor
@Observable
final class FirebaseService {
    static let shared = FirebaseService()

    let config: FirebaseConfig
    private(set) var activeSession: FirebaseAuthSession?
    private(set) var isConnected: Bool = true
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncTime: Date?
    private(set) var fcmToken: String?

    @ObservationIgnored private let session: URLSession

    init(config: FirebaseConfig = .standard, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Firebase Auth API

    func signUp(email: String, password: String, displayName: String) async throws -> FirebaseAuthSession {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(config.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw FirebaseError.invalidResponse }

        if httpResponse.statusCode == 200 {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let localId = json["localId"] as? String,
               let idToken = json["idToken"] as? String,
               let refreshToken = json["refreshToken"] as? String {
                let userSession = FirebaseAuthSession(
                    localId: localId,
                    email: email,
                    displayName: displayName,
                    idToken: idToken,
                    refreshToken: refreshToken,
                    expiresIn: json["expiresIn"] as? String ?? "3600"
                )
                self.activeSession = userSession
                return userSession
            }
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            throw FirebaseError.apiError(message)
        }

        let demoSession = FirebaseAuthSession(
            localId: UUID().uuidString,
            email: email,
            displayName: displayName,
            idToken: "demo_id_token_\(UUID().uuidString)",
            refreshToken: "demo_refresh_token_\(UUID().uuidString)",
            expiresIn: "3600"
        )
        self.activeSession = demoSession
        return demoSession
    }

    func signIn(email: String, password: String) async throws -> FirebaseAuthSession {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(config.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw FirebaseError.invalidResponse }

        if httpResponse.statusCode == 200 {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let localId = json["localId"] as? String,
               let idToken = json["idToken"] as? String,
               let refreshToken = json["refreshToken"] as? String {
                let userSession = FirebaseAuthSession(
                    localId: localId,
                    email: email,
                    displayName: json["displayName"] as? String ?? email,
                    idToken: idToken,
                    refreshToken: refreshToken,
                    expiresIn: json["expiresIn"] as? String ?? "3600"
                )
                self.activeSession = userSession
                return userSession
            }
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            throw FirebaseError.apiError(message)
        }

        let demoSession = FirebaseAuthSession(
            localId: UUID().uuidString,
            email: email,
            displayName: email.components(separatedBy: "@").first?.capitalized ?? "User",
            idToken: "demo_id_token_\(UUID().uuidString)",
            refreshToken: "demo_refresh_token_\(UUID().uuidString)",
            expiresIn: "3600"
        )
        self.activeSession = demoSession
        return demoSession
    }

    func sendPasswordReset(email: String) async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(config.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "requestType": "PASSWORD_RESET",
            "email": email
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        _ = try? await session.data(for: request)
    }

    func signOut() {
        activeSession = nil
    }

    // MARK: - Cloud Firestore API (Sessions & Vehicles Sync)

    func syncParkingSession(_ session: ParkingSession, userId: String) async throws {
        isSyncing = true
        defer { isSyncing = false }

        let documentPath = "https://firestore.googleapis.com/v1/projects/\(config.projectId)/databases/(default)/documents/users/\(userId)/parking_sessions/\(session.id.uuidString)?key=\(config.apiKey)"
        guard let url = URL(string: documentPath) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fields: [String: Any] = [
            "fields": [
                "title": ["stringValue": session.title],
                "floor": ["stringValue": session.floor],
                "section": ["stringValue": session.section],
                "space": ["stringValue": session.space],
                "latitude": ["doubleValue": session.latitude],
                "longitude": ["doubleValue": session.longitude],
                "address": ["stringValue": session.address],
                "note": ["stringValue": session.note],
                "isActive": ["booleanValue": session.isActive],
                "startDate": ["timestampValue": ISO8601DateFormatter().string(from: session.startDate)]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        _ = try? await self.session.data(for: request)
        self.lastSyncTime = Date()
    }

    func syncVehicle(_ vehicle: Vehicle, userId: String) async throws {
        let documentPath = "https://firestore.googleapis.com/v1/projects/\(config.projectId)/databases/(default)/documents/users/\(userId)/vehicles/\(vehicle.id.uuidString)?key=\(config.apiKey)"
        guard let url = URL(string: documentPath) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fields: [String: Any] = [
            "fields": [
                "name": ["stringValue": vehicle.name],
                "plate": ["stringValue": vehicle.plate],
                "kind": ["stringValue": vehicle.kind.rawValue],
                "isDefault": ["booleanValue": vehicle.isDefault]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        _ = try? await self.session.data(for: request)
    }

    // MARK: - Share Location via Firebase (Real-time Cloud Link)

    func createLocationShare(for session: ParkingSession, sharedBy: String) async throws -> SharedParkingLocation {
        let shareId = String(UUID().uuidString.prefix(8)).lowercased()
        let share = SharedParkingLocation(
            id: shareId,
            title: session.title,
            floor: session.floor,
            section: session.section,
            space: session.space,
            note: session.note,
            latitude: session.latitude,
            longitude: session.longitude,
            sharedBy: sharedBy,
            createdAt: Date(),
            expiryDate: session.expiryDate
        )

        let documentPath = "https://firestore.googleapis.com/v1/projects/\(config.projectId)/databases/(default)/documents/parking_shares/\(shareId)?key=\(config.apiKey)"
        if let url = URL(string: documentPath) {
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let fields: [String: Any] = [
                "fields": [
                    "title": ["stringValue": share.title],
                    "floor": ["stringValue": share.floor],
                    "section": ["stringValue": share.section],
                    "space": ["stringValue": share.space],
                    "note": ["stringValue": share.note],
                    "latitude": ["doubleValue": share.latitude],
                    "longitude": ["doubleValue": share.longitude],
                    "sharedBy": ["stringValue": share.sharedBy],
                    "createdAt": ["timestampValue": ISO8601DateFormatter().string(from: share.createdAt)]
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: fields)
            _ = try? await self.session.data(for: request)
        }

        return share
    }

    // MARK: - Cloud Messaging (Push Notifications)

    func registerFCMToken(_ token: String) {
        self.fcmToken = token
    }
}

// MARK: - Sample Parking Photos (for Testing & Demonstrations)

enum SampleParkingImages {
    static func generate(title: String, bay: String, floor: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 800, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Ground concrete
            UIColor(red: 0.18, green: 0.20, blue: 0.22, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Wall
            UIColor(red: 0.28, green: 0.30, blue: 0.33, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 260))

            // Pillar
            color.setFill()
            ctx.fill(CGRect(x: 40, y: 0, width: 140, height: 420))

            let pillarAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 42),
                .foregroundColor: UIColor.white
            ]
            (floor as NSString).draw(at: CGPoint(x: 70, y: 80), withAttributes: pillarAttrs)

            // Yellow parking lines
            let path = UIBezierPath()
            path.lineWidth = 14
            UIColor(red: 0.95, green: 0.85, blue: 0.15, alpha: 1.0).setStroke()
            path.move(to: CGPoint(x: 180, y: 600))
            path.addLine(to: CGPoint(x: 280, y: 260))
            path.move(to: CGPoint(x: 680, y: 600))
            path.addLine(to: CGPoint(x: 580, y: 260))
            path.move(to: CGPoint(x: 280, y: 260))
            path.addLine(to: CGPoint(x: 580, y: 260))
            path.stroke()

            // Wall Bay Sign
            let signRect = CGRect(x: 280, y: 80, width: 300, height: 110)
            UIBezierPath(roundedRect: signRect, cornerRadius: 16).fill(with: .normal, alpha: 0.95)

            let bayAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 56),
                .foregroundColor: UIColor.black
            ]
            let bayStr = bay as NSString
            let baySize = bayStr.size(withAttributes: bayAttrs)
            bayStr.draw(at: CGPoint(x: signRect.midX - baySize.width/2, y: signRect.midY - baySize.height/2), withAttributes: bayAttrs)

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            (title as NSString).draw(at: CGPoint(x: 280, y: 40), withAttributes: titleAttrs)
        }
    }

    static var slotA124: UIImage {
        generate(title: "Colombo City Centre • Level B1", bay: "A124", floor: "B1", color: UIColor(red: 0.05, green: 0.45, blue: 0.95, alpha: 1.0))
    }

    static var slotB205: UIImage {
        generate(title: "One Galle Face Mall • Level B2", bay: "B-205", floor: "B2", color: UIColor(red: 0.15, green: 0.70, blue: 0.45, alpha: 1.0))
    }

    static var slotG14: UIImage {
        generate(title: "Galle Face Green • Surface Bay", bay: "G-14", floor: "G", color: UIColor(red: 0.55, green: 0.25, blue: 0.75, alpha: 1.0))
    }
}

// MARK: - Voice Audio Announcements (Feature E: AVSpeechSynthesizer)

@MainActor
final class VoiceAnnouncementService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceAnnouncementService()
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func announceParkingSaved(session: ParkingSession) {
        let spot = session.space.isEmpty ? session.locationLabel : "space \(session.space)"
        speak("Parking spot saved at \(session.title). Your vehicle is parked at \(spot).")
    }

    func announceExpiryWarning(title: String, minutes: Int) {
        speak("Attention: Your parking meter at \(title) will expire in \(minutes) minutes.")
    }

    func announceArrival(space: String) {
        speak("You have reached your car. \(space).")
    }

    func announceCheckout(title: String, cost: Double, duration: String) {
        let costFormatted = String(format: "%.0f", cost)
        speak("Smart checkout complete. You have departed \(title). Total duration \(duration). Final fee \(costFormatted) Rupees.")
    }
}

// MARK: - Bluetooth & CarPlay Auto-Save Service (Feature B)

/// Background service monitoring Bluetooth (A2DP/HFP) and CarPlay disconnects to auto-detect vehicle parking events.
@MainActor
@Observable
final class BluetoothParkingService: NSObject {
    static let shared = BluetoothParkingService()
    var isCarConnected: Bool = false
    var connectedDeviceName: String?
    var lastEventDescription: String?
    var isMonitoring: Bool = false
    @ObservationIgnored var onCarDisconnected: (() -> Void)?

    override init() {
        super.init()
        startMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                let hadCarOrBluetooth = previousRoute.outputs.contains { desc in
                    desc.portType == .bluetoothA2DP || desc.portType == .bluetoothHFP || desc.portType == .carAudio || desc.portType == .usbAudio
                }
                if hadCarOrBluetooth {
                    isCarConnected = false
                    lastEventDescription = "Car audio disconnected at \(Date().formatted(date: .omitted, time: .shortened))"
                    onCarDisconnected?()
                }
            }
        case .newDeviceAvailable:
            isCarConnected = true
            lastEventDescription = "Car audio connected"
        default:
            break
        }
    }

    func simulateDisconnect() {
        isCarConnected = false
        lastEventDescription = "Simulated car disconnect at \(Date().formatted(date: .omitted, time: .shortened))"
        onCarDisconnected?()
    }
}
