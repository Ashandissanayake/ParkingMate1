import Foundation

enum ParkingNumberParser {
    static func bestCandidate(from strings: [String]) -> String? {
        let pattern = #"(?<![A-Za-z0-9])([A-Za-z]{1,2})[\s\-]?(\d{1,3})(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var best: (value: String, digits: Int)?
        for raw in strings {
            let text = raw.uppercased()
            if text.contains("LEVEL") || text.contains("FLOOR") { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let letters = Range(match.range(at: 1), in: text),
                      let digits = Range(match.range(at: 2), in: text) else { continue }
                let candidate = String(text[letters]) + String(text[digits])
                let count = text[digits].count
                if best == nil || count > best!.digits { best = (candidate, count) }
            }
        }
        return best?.value
    }
}

enum FloorEstimator {
    static func label(relativeAltitude: Double, floorHeight: Double = 3.0) -> String {
        guard floorHeight > 0 else { return "G" }
        let index = Int((relativeAltitude / floorHeight).rounded())
        switch index {
        case 0: return "G"
        case 1...: return "L\(index)"
        default: return "B\(-index)"
        }
    }
}

struct ReminderPlan: Equatable {
    enum Kind: String { case warning, expired }
    let kind: Kind
    let fireDate: Date
    let title: String
    let body: String
}

enum ReminderPlanner {
    static func plan(placeLabel: String, expiry: Date, now: Date, leadMinutes: Int) -> [ReminderPlan] {
        var plans: [ReminderPlan] = []
        let warningDate = expiry.addingTimeInterval(-Double(leadMinutes) * 60)
        if leadMinutes > 0, warningDate > now {
            plans.append(ReminderPlan(kind: .warning, fireDate: warningDate,
                                      title: "Parking expires in \(leadMinutes) min",
                                      body: "\(placeLabel) – extend now or head back to your car."))
        }
        if expiry > now {
            plans.append(ReminderPlan(kind: .expired, fireDate: expiry,
                                      title: "Parking time is up",
                                      body: "\(placeLabel) – your parking time has expired."))
        }
        return plans
    }
}

struct ActivitySample: Equatable {
    enum Confidence: Int { case low = 0, medium, high }
    var automotive = false
    var walking = false
    var running = false
    var stationary = false
    var confidence: Confidence = .medium
}
struct ParkingDetectionStateMachine {
    private(set) var wasDriving = false
    mutating func ingest(_ sample: ActivitySample) -> Bool {
        guard sample.confidence != .low else { return false }
        if sample.automotive {
            wasDriving = true
            return false
        }
        if wasDriving && (sample.walking || sample.running) {
            wasDriving = false
            return true
        }
        return false
    }

    mutating func reset() { wasDriving = false }
}

enum CredentialValidator {
    enum Issue: Equatable, LocalizedError {
        case emptyName, invalidEmail, weakPassword, passwordMismatch, invalidPhone
        var errorDescription: String? {
            switch self {
            case .emptyName: "Please enter your full name."
            case .invalidEmail: "Enter a valid email address."
            case .weakPassword: "Password must be at least 8 characters and include a letter and a number."
            case .passwordMismatch: "Passwords do not match."
            case .invalidPhone: "Enter a valid phone number."
            }
        }
    }

    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.trimmingCharacters(in: .whitespaces).range(of: pattern, options: .regularExpression) != nil
    }

    static func isStrongPassword(_ password: String) -> Bool {
        password.count >= 8
            && password.rangeOfCharacter(from: .letters) != nil
            && password.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.filter(\.isNumber)
        return phone.isEmpty || (digits.count >= 9 && digits.count <= 15)
    }

    static func validateRegistration(name: String, email: String, phone: String,
                                     password: String, confirm: String) -> Issue? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return .emptyName }
        if !isValidEmail(email) { return .invalidEmail }
        if !isValidPhone(phone) { return .invalidPhone }
        if !isStrongPassword(password) { return .weakPassword }
        if password != confirm { return .passwordMismatch }
        return nil
    }
}

enum HistoryScope: String, CaseIterable, Identifiable {
    case location = "Location", date = "Date", vehicle = "Vehicle", facility = "Facility"
    var id: String { rawValue }
}

enum SessionSearch {
    static func filter(_ sessions: [ParkingSession], query: String, scope: HistoryScope,
                       vehicles: [Vehicle]) -> [ParkingSession] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sessions }
        return sessions.filter { s in
            switch scope {
            case .location:
                return [s.address, s.floor, s.section, s.space, s.note].contains { $0.lowercased().contains(q) }
            case .facility:
                return s.title.lowercased().contains(q)
            case .date:
                let text = s.startDate.formatted(.dateTime.day().month(.wide).year()).lowercased()
                return text.contains(q)
            case .vehicle:
                guard let id = s.vehicleID, let v = vehicles.first(where: { $0.id == id }) else { return false }
                return v.name.lowercased().contains(q) || v.plate.lowercased().contains(q)
            }
        }
    }
}
