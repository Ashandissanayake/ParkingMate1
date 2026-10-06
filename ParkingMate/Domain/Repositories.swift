import Foundation

@MainActor
protocol ParkingRepository: AnyObject {
    func fetchAll() throws -> [ParkingSession]
    func upsert(_ session: ParkingSession) throws
    func delete(id: UUID) throws
}

@MainActor
protocol VehicleRepository: AnyObject {
    func fetchAll() throws -> [Vehicle]
    func upsert(_ vehicle: Vehicle) throws
    func delete(id: UUID) throws
}

@MainActor
protocol FavoriteRepository: AnyObject {
    func fetchAll() throws -> [FavoriteLocation]
    func upsert(_ favorite: FavoriteLocation) throws
    func delete(id: UUID) throws
}
