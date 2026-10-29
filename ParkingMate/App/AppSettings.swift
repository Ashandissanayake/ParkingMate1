import SwiftUI
import Combine

/// User preferences, persisted in UserDefaults. (`ObservableObject` + `@Published` so property observers
/// reliably write through to UserDefaults.)
final class AppSettings: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum Key {
        static let appearance = "settings.appearance"
        static let biometricLock = "settings.biometricLock"
        static let reminders = "settings.reminders"
        static let reminderLead = "settings.reminderLeadMinutes"
        static let iCloud = "settings.iCloudSync"
        static let autoDetect = "settings.autoDetectParking"
        static let geofence = "settings.geofenceAlerts"
        static let hourlyRate = "settings.defaultHourlyRate"
        static let largerText = "settings.largerText"
        static let contrast = "settings.increaseContrast"
        static let reduceMotion = "settings.reduceMotion"
        static let boldText = "settings.boldText"
        static let buttonShapes = "settings.buttonShapes"
    }

    private let defaults: UserDefaults

    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    @Published var biometricLockEnabled: Bool { didSet { defaults.set(biometricLockEnabled, forKey: Key.biometricLock) } }
    @Published var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: Key.reminders) } }
    @Published var reminderLeadMinutes: Int { didSet { defaults.set(reminderLeadMinutes, forKey: Key.reminderLead) } }
    @Published var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Key.iCloud) } }
    @Published var autoDetectParking: Bool { didSet { defaults.set(autoDetectParking, forKey: Key.autoDetect) } }
    @Published var geofenceAlertsEnabled: Bool { didSet { defaults.set(geofenceAlertsEnabled, forKey: Key.geofence) } }
    @Published var defaultHourlyRate: Double { didSet { defaults.set(defaultHourlyRate, forKey: Key.hourlyRate) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Haptics.enabledKey) } }
    // Accessibility
    @Published var largerText: Bool { didSet { defaults.set(largerText, forKey: Key.largerText) } }
    @Published var increaseContrast: Bool { didSet { defaults.set(increaseContrast, forKey: Key.contrast) } }
    @Published var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: Key.reduceMotion) } }
    @Published var boldText: Bool { didSet { defaults.set(boldText, forKey: Key.boldText) } }
    @Published var buttonShapes: Bool { didSet { defaults.set(buttonShapes, forKey: Key.buttonShapes) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        biometricLockEnabled = defaults.object(forKey: Key.biometricLock) as? Bool ?? false
        remindersEnabled = defaults.object(forKey: Key.reminders) as? Bool ?? true
        reminderLeadMinutes = defaults.object(forKey: Key.reminderLead) as? Int ?? 15
        iCloudSyncEnabled = defaults.object(forKey: Key.iCloud) as? Bool ?? false
        autoDetectParking = defaults.object(forKey: Key.autoDetect) as? Bool ?? false
        geofenceAlertsEnabled = defaults.object(forKey: Key.geofence) as? Bool ?? true
        defaultHourlyRate = defaults.object(forKey: Key.hourlyRate) as? Double ?? AppConfig.defaultHourlyRate
        hapticsEnabled = defaults.object(forKey: Haptics.enabledKey) as? Bool ?? true
        largerText = defaults.bool(forKey: Key.largerText)
        increaseContrast = defaults.bool(forKey: Key.contrast)
        reduceMotion = defaults.bool(forKey: Key.reduceMotion)
        boldText = defaults.bool(forKey: Key.boldText)
        buttonShapes = defaults.bool(forKey: Key.buttonShapes)
    }

    /// Read *before* the Core Data stack is created (the store type depends on it).
    static func storedICloudPreference(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.iCloud) as? Bool ?? false
    }
}

/// What the store needs to know about preferences (lets tests inject a plain struct).
protocol StoreSettings {
    var remindersEnabled: Bool { get }
    var reminderLeadMinutes: Int { get }
    var geofenceAlertsEnabled: Bool { get }
}
extension AppSettings: StoreSettings {}
