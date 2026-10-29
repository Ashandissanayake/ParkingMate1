import CoreData

// The Core Data model is defined in code (no .xcdatamodeld) so the project builds from plain source files.
// All attributes are optional or have defaults, which keeps the schema CloudKit-compatible.

@objc(ParkingSessionEntity)
final class ParkingSessionEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var address: String?
    @NSManaged var floor: String?
    @NSManaged var section: String?
    @NSManaged var space: String?
    @NSManaged var note: String?
    @NSManaged var photoData: Data?
    @NSManaged var voiceNoteFileName: String?
    @NSManaged var voiceTranscript: String?
    @NSManaged var startDate: Date?
    @NSManaged var expiryDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var hourlyRate: Double
    @NSManaged var vehicleID: UUID?
}

@objc(VehicleEntity)
final class VehicleEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var kind: String?
    @NSManaged var name: String?
    @NSManaged var plate: String?
    @NSManaged var isDefault: Bool
}

@objc(FavoriteEntity)
final class FavoriteEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var detail: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
}

enum CoreDataModelFactory {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            entity("ParkingSessionEntity", ParkingSessionEntity.self, [
                attr("id", .UUIDAttributeType), attr("title", .stringAttributeType, ""),
                attr("latitude", .doubleAttributeType, 0.0), attr("longitude", .doubleAttributeType, 0.0),
                attr("address", .stringAttributeType, ""), attr("floor", .stringAttributeType, ""),
                attr("section", .stringAttributeType, ""), attr("space", .stringAttributeType, ""),
                attr("note", .stringAttributeType, ""),
                attr("photoData", .binaryDataAttributeType, external: true),
                attr("voiceNoteFileName", .stringAttributeType),
                attr("voiceTranscript", .stringAttributeType, ""),
                attr("startDate", .dateAttributeType), attr("expiryDate", .dateAttributeType),
                attr("endDate", .dateAttributeType),
                attr("hourlyRate", .doubleAttributeType, 0.0), attr("vehicleID", .UUIDAttributeType)
            ]),
            entity("VehicleEntity", VehicleEntity.self, [
                attr("id", .UUIDAttributeType), attr("kind", .stringAttributeType, "car"),
                attr("name", .stringAttributeType, ""), attr("plate", .stringAttributeType, ""),
                attr("isDefault", .booleanAttributeType, false)
            ]),
            entity("FavoriteEntity", FavoriteEntity.self, [
                attr("id", .UUIDAttributeType), attr("name", .stringAttributeType, ""),
                attr("detail", .stringAttributeType, ""),
                attr("latitude", .doubleAttributeType, 0.0), attr("longitude", .doubleAttributeType, 0.0)
            ])
        ]
        return model
    }

    private static func entity(_ name: String, _ cls: AnyClass, _ props: [NSAttributeDescription]) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        e.managedObjectClassName = NSStringFromClass(cls)
        e.properties = props
        return e
    }

    private static func attr(_ name: String, _ type: NSAttributeType,
                             _ defaultValue: Any? = nil, external: Bool = false) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = true
        a.defaultValue = defaultValue
        a.allowsExternalBinaryDataStorage = external
        return a
    }
}
