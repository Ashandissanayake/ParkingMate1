import Foundation
import CoreData
import CloudKit
import Observation
@MainActor
@Observable
final class CloudSyncMonitor {
    private(set) var isActive: Bool
    private(set) var accountStatus = "Checking…"
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(isActive: Bool) {
        self.isActive = isActive
        accountStatus = isActive ? "Checking…" : "Sync is off"
        if isActive { observe() }
    }

    private func observe() {
        task = Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { continue }
                let end = event.endDate
                let succeeded = event.succeeded
                let message = event.error?.localizedDescription
                self?.apply(end: end, succeeded: succeeded, message: message)
            }
        }
    }

    private func apply(end: Date?, succeeded: Bool, message: String?) {
        isSyncing = end == nil
        guard let end else { return }
        if succeeded { lastSync = end; lastError = nil } else { lastError = message }
    }

    func refreshAccountStatus() async {
        guard isActive else {
            accountStatus = FileManager.default.ubiquityIdentityToken == nil
                ? "Not signed in to iCloud" : "Sync is off"
            return
        }
        do {
            let status = try await CKContainer(identifier: AppConfig.cloudKitContainerIdentifier).accountStatus()
            switch status {
            case .available: accountStatus = "iCloud connected"
            case .noAccount: accountStatus = "No iCloud account"
            case .restricted: accountStatus = "iCloud restricted"
            case .couldNotDetermine: accountStatus = "Couldn't determine status"
            case .temporarilyUnavailable: accountStatus = "iCloud temporarily unavailable"
            @unknown default: accountStatus = "Unknown"
            }
        } catch {
            accountStatus = "iCloud error"
            lastError = error.localizedDescription
        }
    }
}
