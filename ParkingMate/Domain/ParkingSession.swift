import Foundation
import CoreLocation
struct ParkingSession: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var latitude: Double
    var longitude: Double
    var address: String = ""
    var floor: String = ""
    var section: String = ""
    var space: String = ""
    var note: String = ""
    var photoData: Data?
    var voiceNoteFileName: String?
    var voiceTranscript: String = ""
    var startDate: Date
    var expiryDate: Date?
    var endDate: Date?
    var hourlyRate: Double = 0
    var vehicleID: UUID?
}

extension ParkingSession {
    var isActive: Bool { endDate == nil }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var locationLabel: String {
        let parts = [floor, section, space].filter { !$0.isEmpty }
        return parts.isEmpty ? "Location saved" : parts.joined(separator: " • ")
    }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, (endDate ?? now).timeIntervalSince(startDate))
    }
    func remaining(at now: Date) -> TimeInterval? {
        guard let expiryDate else { return nil }
        return max(0, expiryDate.timeIntervalSince(now))
    }
    func progress(at now: Date) -> Double? {
        guard let expiryDate else { return nil }
        let total = expiryDate.timeIntervalSince(startDate)
        guard total > 0 else { return 0 }
        return min(1, max(0, expiryDate.timeIntervalSince(now) / total))
    }

    func isExpired(at now: Date) -> Bool {
        guard let expiryDate else { return false }
        return isActive && now >= expiryDate
    }

    func cost(at now: Date) -> Double {
        ParkingCostCalculator.cost(hourlyRate: hourlyRate, duration: elapsed(at: now))
    }
}
enum ParkingCostCalculator {
    static func cost(hourlyRate: Double,
                     duration: TimeInterval,
                     graceMinutes: Double = 0,
                     incrementMinutes: Double = 15) -> Double {
        guard hourlyRate > 0, incrementMinutes > 0 else { return 0 }
        let billable = max(0, duration - graceMinutes * 60)
        guard billable > 0 else { return 0 }
        let increment = incrementMinutes * 60
        let blocks = (billable / increment).rounded(.up)
        return blocks * (increment / 3600) * hourlyRate
    }
}
enum VoiceNoteStorage {
    static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }
}
