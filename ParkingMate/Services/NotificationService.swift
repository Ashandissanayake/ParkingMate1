import Foundation
import UserNotifications

struct PendingReminder: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date?
}

@MainActor
protocol ReminderScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func schedule(for session: ParkingSession, leadMinutes: Int)
    func cancel(sessionID: UUID)
    func pendingReminders() async -> [PendingReminder]
    func notifyNow(id: String, title: String, body: String, userInfo: [String: String])
}

/// UserNotifications: scheduled expiry reminders with an inline "Extend 30 min" action, plus immediate alerts.
@MainActor
final class NotificationService: NSObject, ReminderScheduling, UNUserNotificationCenterDelegate {
    static let expiryCategory = "PARKING_EXPIRY"
    static let extendAction = "EXTEND_30"
    static let openAction = "OPEN_CAR"
    static let savePromptCategory = "PARKING_DETECTED"

    var onExtend: ((UUID, Int) -> Void)?
    var onOpenRoute: ((String) -> Void)?    // "findMyCar" | "saveParking"

    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        center.delegate = self
        let extend = UNNotificationAction(identifier: Self.extendAction, title: "Extend 30 min", options: [])
        let open = UNNotificationAction(identifier: Self.openAction, title: "Find my car", options: [.foreground])
        let expiry = UNNotificationCategory(identifier: Self.expiryCategory, actions: [extend, open],
                                            intentIdentifiers: [], options: [])
        let save = UNNotificationCategory(identifier: Self.savePromptCategory, actions: [],
                                          intentIdentifiers: [], options: [])
        center.setNotificationCategories([expiry, save])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(for session: ParkingSession, leadMinutes: Int) {
        cancel(sessionID: session.id)
        guard let expiry = session.expiryDate else { return }
        let plans = ReminderPlanner.plan(placeLabel: "\(session.title) – \(session.locationLabel)",
                                         expiry: expiry, now: .now, leadMinutes: leadMinutes)
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.categoryIdentifier = Self.expiryCategory
            content.userInfo = ["sessionID": session.id.uuidString]
            content.interruptionLevel = .active
            let interval = max(1, plan.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.identifier(plan.kind, session.id),
                                             content: content, trigger: trigger))
        }
    }

    func cancel(sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.identifier(.warning, sessionID), Self.identifier(.expired, sessionID)
        ])
    }

    func pendingReminders() async -> [PendingReminder] {
        let requests = await center.pendingNotificationRequests()
        return requests
            .filter { $0.content.categoryIdentifier == Self.expiryCategory }
            .map { r in
                let date = (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                return PendingReminder(id: r.identifier, title: r.content.title, body: r.content.body, fireDate: date)
            }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    func notifyNow(id: String, title: String, body: String, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func identifier(_ kind: ReminderPlan.Kind, _ id: UUID) -> String { "\(kind.rawValue)-\(id.uuidString)" }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let sessionID = (info["sessionID"] as? String).flatMap(UUID.init(uuidString:))
        let route = info["route"] as? String
        await MainActor.run {
            switch action {
            case Self.extendAction:
                if let sessionID { self.onExtend?(sessionID, 30) }
            case Self.openAction:
                self.onOpenRoute?("findMyCar")
            default:
                if let route { self.onOpenRoute?(route) }
                else if sessionID != nil { self.onOpenRoute?("findMyCar") }
            }
        }
    }
}
