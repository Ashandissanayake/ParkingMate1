import CoreData

// MARK: - Mapping between managed objects and domain values

private extension ParkingSessionEntity {
    func toDomain() -> ParkingSession? {
        guard let id, let startDate else { return nil }
        return ParkingSession(id: id, title: title ?? "", latitude: latitude, longitude: longitude,
                              address: address ?? "", floor: floor ?? "", section: section ?? "",
                              space: space ?? "", note: note ?? "", photoData: photoData,
                              voiceNoteFileName: voiceNoteFileName, voiceTranscript: voiceTranscript ?? "",
                              startDate: startDate, expiryDate: expiryDate, endDate: endDate,
                              hourlyRate: hourlyRate, vehicleID: vehicleID)
    }

    func apply(_ s: ParkingSession) {
        id = s.id; title = s.title; latitude = s.latitude; longitude = s.longitude
        address = s.address; floor = s.floor; section = s.section; space = s.space; note = s.note
        photoData = s.photoData; voiceNoteFileName = s.voiceNoteFileName; voiceTranscript = s.voiceTranscript
        startDate = s.startDate; expiryDate = s.expiryDate; endDate = s.endDate
        hourlyRate = s.hourlyRate; vehicleID = s.vehicleID
    }
}

private extension VehicleEntity {
    func toDomain() -> Vehicle? {
        guard let id else { return nil }
        return Vehicle(id: id, kind: Vehicle.Kind(rawValue: kind ?? "car") ?? .car,
                       name: name ?? "", plate: plate ?? "", isDefault: isDefault)
    }
    func apply(_ v: Vehicle) {
        id = v.id; kind = v.kind.rawValue; name = v.name; plate = v.plate; isDefault = v.isDefault
    }
}

private extension FavoriteEntity {
    func toDomain() -> FavoriteLocation? {
        guard let id else { return nil }
        return FavoriteLocation(id: id, name: name ?? "", detail: detail ?? "", latitude: latitude, longitude: longitude)
    }
    func apply(_ f: FavoriteLocation) {
        id = f.id; name = f.name; detail = f.detail; latitude = f.latitude; longitude = f.longitude
    }
}

// MARK: - Shared fetch helpers

private func fetchOne<T: NSManagedObject>(_ type: T.Type, entity: String, id: UUID,
                                          in context: NSManagedObjectContext) throws -> T? {
    let request = NSFetchRequest<T>(entityName: entity)
    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
    request.fetchLimit = 1
    return try context.fetch(request).first
}

// MARK: - Repositories

@MainActor
final class CoreDataParkingRepository: ParkingRepository {
    private let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) { self.context = context }

    func fetchAll() throws -> [ParkingSession] {
        let request = NSFetchRequest<ParkingSessionEntity>(entityName: "ParkingSessionEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return try context.fetch(request).compactMap { $0.toDomain() }
    }

    func upsert(_ session: ParkingSession) throws {
        let entity = try fetchOne(ParkingSessionEntity.self, entity: "ParkingSessionEntity", id: session.id, in: context)
            ?? ParkingSessionEntity(context: context)
        entity.apply(session)
        try context.save()
    }

    func delete(id: UUID) throws {
        if let entity = try fetchOne(ParkingSessionEntity.self, entity: "ParkingSessionEntity", id: id, in: context) {
            context.delete(entity)
            try context.save()
        }
    }
}

@MainActor
final class CoreDataVehicleRepository: VehicleRepository {
    private let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) { self.context = context }

    func fetchAll() throws -> [Vehicle] {
        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request).compactMap { $0.toDomain() }
    }

    func upsert(_ vehicle: Vehicle) throws {
        let entity = try fetchOne(VehicleEntity.self, entity: "VehicleEntity", id: vehicle.id, in: context)
            ?? VehicleEntity(context: context)
        entity.apply(vehicle)
        try context.save()
    }

    func delete(id: UUID) throws {
        if let entity = try fetchOne(VehicleEntity.self, entity: "VehicleEntity", id: id, in: context) {
            context.delete(entity)
            try context.save()
        }
    }
}

@MainActor
final class CoreDataFavoriteRepository: FavoriteRepository {
    private let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) { self.context = context }

    func fetchAll() throws -> [FavoriteLocation] {
        let request = NSFetchRequest<FavoriteEntity>(entityName: "FavoriteEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request).compactMap { $0.toDomain() }
    }

    func upsert(_ favorite: FavoriteLocation) throws {
        let entity = try fetchOne(FavoriteEntity.self, entity: "FavoriteEntity", id: favorite.id, in: context)
            ?? FavoriteEntity(context: context)
        entity.apply(favorite)
        try context.save()
    }

    func delete(id: UUID) throws {
        if let entity = try fetchOne(FavoriteEntity.self, entity: "FavoriteEntity", id: id, in: context) {
            context.delete(entity)
            try context.save()
        }
    }
}
