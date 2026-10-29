import CoreData

/// Owns the Core Data stack. When iCloud sync is enabled (and the user is signed in to iCloud) it uses
/// `NSPersistentCloudKitContainer`, otherwise a plain `NSPersistentContainer`. If the CloudKit store
/// fails to load (e.g. capability not configured) it falls back to local-only storage automatically.
final class PersistenceController {
    static let shared = PersistenceController(cloudKitEnabled: AppSettings.storedICloudPreference())

    let container: NSPersistentContainer
    let isCloudKitActive: Bool
    private(set) var startupWarning: String?

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false, cloudKitEnabled: Bool = false) {
        let wantsCloud = cloudKitEnabled && !inMemory && FileManager.default.ubiquityIdentityToken != nil
        var result = PersistenceController.build(cloud: wantsCloud, inMemory: inMemory)
        var warning: String?
        var cloudActive = wantsCloud

        if wantsCloud, result.error != nil {
            warning = "iCloud sync could not start (\(result.error?.localizedDescription ?? "unknown")). Using local storage."
            result = PersistenceController.build(cloud: false, inMemory: inMemory)
            cloudActive = false
        } else if PersistenceController.cloudEnabledButSignedOut(cloudKitEnabled, inMemory) {
            warning = "Sign in to iCloud in Settings to sync across devices."
        }

        container = result.container
        isCloudKitActive = cloudActive
        startupWarning = warning ?? result.error.map { "Local store error: \($0.localizedDescription)" }
    }

    private static func cloudEnabledButSignedOut(_ enabled: Bool, _ inMemory: Bool) -> Bool {
        enabled && !inMemory && FileManager.default.ubiquityIdentityToken == nil
    }

    private static func build(cloud: Bool, inMemory: Bool) -> (container: NSPersistentContainer, error: Error?) {
        let model = CoreDataModelFactory.makeModel()
        let container: NSPersistentContainer = cloud
            ? NSPersistentCloudKitContainer(name: "ParkingMate", managedObjectModel: model)
            : NSPersistentContainer(name: "ParkingMate", managedObjectModel: model)

        if let description = container.persistentStoreDescriptions.first {
            if inMemory { description.url = URL(fileURLWithPath: "/dev/null") }
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.cloudKitContainerOptions = cloud
                ? NSPersistentCloudKitContainerOptions(containerIdentifier: AppConfig.cloudKitContainerIdentifier)
                : nil
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return (container, loadError)
    }
}
