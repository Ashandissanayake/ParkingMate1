import Foundation
import CryptoKit

struct UserProfile: Codable, Equatable {
    var fullName: String
    var email: String
    var phone: String
}

enum AuthError: LocalizedError, Equatable {
    case validation(CredentialValidator.Issue)
    case emailAlreadyRegistered
    case invalidCredentials
    case accountNotFound
    case storage

    var errorDescription: String? {
        switch self {
        case .validation(let issue): issue.errorDescription
        case .emailAlreadyRegistered: "An account with this email already exists."
        case .invalidCredentials: "Incorrect email or password."
        case .accountNotFound: "We couldn't find an account with that email."
        case .storage: "Couldn't save your account securely. Please try again."
        }
    }
}
@MainActor
@Observable
final class AuthService {
    private(set) var currentUser: UserProfile?
    var isSignedIn: Bool { currentUser != nil }

    @ObservationIgnored private let secrets: SecretStoring
    @ObservationIgnored private let defaults: UserDefaults
    private static let sessionKey = "auth.sessionEmail"
    private static let profilePrefix = "auth.profile."

    init(secrets: SecretStoring? = nil, defaults: UserDefaults = .standard) {
        self.secrets = secrets ?? KeychainStore()
        self.defaults = defaults
        if let email = defaults.string(forKey: Self.sessionKey) { currentUser = loadProfile(email: email) }
    }

    func register(fullName: String, email: String, phone: String, password: String, confirm: String) throws {
        if let issue = CredentialValidator.validateRegistration(name: fullName, email: email, phone: phone,
                                                                password: password, confirm: confirm) {
            throw AuthError.validation(issue)
        }
        let key = Self.normalize(email)
        guard secrets.get(key) == nil else { throw AuthError.emailAlreadyRegistered }
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let record = salt + Self.hash(password: password, salt: salt)
        do { try secrets.set(record, for: key) } catch { throw AuthError.storage }
        let profile = UserProfile(fullName: fullName.trimmingCharacters(in: .whitespaces), email: key, phone: phone)
        saveProfile(profile)
        startSession(for: profile)
        Task { [weak self] in
            _ = try? await FirebaseService.shared.signUp(email: key, password: password, displayName: fullName)
        }
    }

    func signIn(email: String, password: String) throws {
        guard CredentialValidator.isValidEmail(email) else { throw AuthError.validation(.invalidEmail) }
        let key = Self.normalize(email)
        guard let record = secrets.get(key), record.count > 16 else { throw AuthError.invalidCredentials }
        let salt = record.prefix(16)
        let stored = record.dropFirst(16)
        guard Self.hash(password: password, salt: Data(salt)) == Data(stored),
              let profile = loadProfile(email: key) else { throw AuthError.invalidCredentials }
        startSession(for: profile)
        Task {
            _ = try? await FirebaseService.shared.signIn(email: key, password: password)
        }
    }
    func signInWithApple(userID: String, fullName: String?, email: String?) {
        let key = Self.normalize(email ?? "\(userID)@privaterelay.appleid.com")
        let profile = loadProfile(email: key)
            ?? UserProfile(fullName: fullName?.isEmpty == false ? fullName! : "Apple User", email: key, phone: "")
        saveProfile(profile)
        startSession(for: profile)
    }

    func signOut() {
        defaults.removeObject(forKey: Self.sessionKey)
        currentUser = nil
        FirebaseService.shared.signOut()
    }
    func requestPasswordReset(email: String) throws {
        guard CredentialValidator.isValidEmail(email) else { throw AuthError.validation(.invalidEmail) }
        guard secrets.get(Self.normalize(email)) != nil else { throw AuthError.accountNotFound }
        Task {
            try? await FirebaseService.shared.sendPasswordReset(email: email)
        }
    }

    func updateProfile(fullName: String, phone: String) throws {
        guard var user = currentUser else { return }
        guard !fullName.trimmingCharacters(in: .whitespaces).isEmpty else { throw AuthError.validation(.emptyName) }
        guard CredentialValidator.isValidPhone(phone) else { throw AuthError.validation(.invalidPhone) }
        user.fullName = fullName; user.phone = phone
        saveProfile(user)
        currentUser = user
    }

    private func startSession(for profile: UserProfile) {
        defaults.set(profile.email, forKey: Self.sessionKey)
        currentUser = profile
    }

    private func saveProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.profilePrefix + profile.email) }
    }

    private func loadProfile(email: String) -> UserProfile? {
        guard let data = defaults.data(forKey: Self.profilePrefix + email) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    nonisolated static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    nonisolated static func hash(password: String, salt: Data) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(password.utf8)))
        for _ in 0..<10_000 { digest = Data(SHA256.hash(data: digest + salt)) }
        return digest
    }
}

