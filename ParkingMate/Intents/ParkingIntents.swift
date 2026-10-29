import AppIntents
import Foundation

/// Siri / Shortcuts: "Where is my car in ParkingMate?" (App Intents – advanced iOS SDK feature).
struct WhereIsMyCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Where is my car?"
    static let description = IntentDescription("Tells you where your car is parked and how long is left on the meter.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = CoreDataParkingRepository(context: PersistenceController.shared.viewContext)
        guard let active = try repo.fetchAll().first(where: \.isActive) else {
            return .result(dialog: "You don't have a saved parking spot right now.")
        }
        var text = "Your car is at \(active.title), \(active.locationLabel)."
        if let left = active.remaining(at: Date()) {
            text += left > 0 ? " You have \(Formatters.duration(left)) left on the meter." : " Your meter has expired."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct ParkingTimeLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "How much parking time is left?"
    static let description = IntentDescription("Reads out the time remaining on your parking meter.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = CoreDataParkingRepository(context: PersistenceController.shared.viewContext)
        guard let active = try repo.fetchAll().first(where: \.isActive), let left = active.remaining(at: Date()) else {
            return .result(dialog: "There is no running parking timer.")
        }
        return .result(dialog: IntentDialog(stringLiteral: left > 0
            ? "\(Formatters.duration(left)) left at \(active.title)."
            : "Your parking time at \(active.title) has expired."))
    }
}

struct ParkingMateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhereIsMyCarIntent(),
                    phrases: ["Where is my car in \(.applicationName)", "Find my car with \(.applicationName)"],
                    shortTitle: "Find my car", systemImageName: "car.fill")
        AppShortcut(intent: ParkingTimeLeftIntent(),
                    phrases: ["How much parking time is left in \(.applicationName)", "Check my \(.applicationName) timer"],
                    shortTitle: "Time left", systemImageName: "timer")
    }
}
