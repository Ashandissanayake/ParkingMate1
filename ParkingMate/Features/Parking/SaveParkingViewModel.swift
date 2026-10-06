import Foundation
import CoreLocation
import UIKit
import Observation

enum SaveParkingError: LocalizedError, Equatable {
    case noLocation
    case invalidRate
    var errorDescription: String? {
        switch self {
        case .noLocation: "Still waiting for a GPS fix. Move near a window or open sky and try again."
        case .invalidRate: "Enter a valid hourly rate."
        }
    }
}
@MainActor
@Observable
final class SaveParkingViewModel {
    var title = "My parked car"
    var address = ""
    var floor = "G"
    var section = "Blue"
    var space = ""
    var note = ""
    var photoData: Data?
    var voiceNoteFileName: String?
    var voiceTranscript = ""
    var vehicleID: UUID?
    var timerEnabled = true
    var durationMinutes = 120
    var hourlyRate: Double
    var errorMessage: String?

    init(prefill: ParkingPrefill, defaultRate: Double, defaultVehicleID: UUID?, hint: DetectionHint?) {
        hourlyRate = defaultRate
        vehicleID = defaultVehicleID
        if let facility = prefill.facility { title = facility.name }
        if let floor = prefill.floorHint ?? hint?.floor { self.floor = floor }
    }

    func applyScannedNumber(_ number: String) { space = number }

    func setPhoto(_ image: UIImage) { photoData = ImageCompressor.jpeg(from: image) }
    func resolvePlace(for location: CLLocation) async {
        guard address.isEmpty else { return }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = placemarks?.first else { return }
        address = [p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: ", ")
        if title == "My parked car", let name = p.name, !name.isEmpty { title = name }
    }

    func buildSession(coordinate: CLLocationCoordinate2D?, now: Date = Date()) throws -> ParkingSession {
        guard let coordinate else { throw SaveParkingError.noLocation }
        guard hourlyRate >= 0 else { throw SaveParkingError.invalidRate }
        return ParkingSession(
            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "My parked car" : title,
            latitude: coordinate.latitude, longitude: coordinate.longitude, address: address,
            floor: floor, section: section, space: space.trimmingCharacters(in: .whitespaces).uppercased(),
            note: note, photoData: photoData, voiceNoteFileName: voiceNoteFileName,
            voiceTranscript: voiceTranscript, startDate: now,
            expiryDate: timerEnabled ? now.addingTimeInterval(Double(durationMinutes) * 60) : nil,
            endDate: nil, hourlyRate: hourlyRate, vehicleID: vehicleID)
    }
}

enum ImageCompressor {
    static func jpeg(from image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.6) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
