import Testing
import Foundation
@testable import ParkingMate

@Suite("Credential validation")
struct CredentialValidatorTests {
    @Test(arguments: ["a@b.co", "john.doe+tag@example.com"])
    func validEmails(email: String) { #expect(CredentialValidator.isValidEmail(email)) }

    @Test(arguments: ["", "plain", "a@b", "@x.com", "a b@c.com"])
    func invalidEmails(email: String) { #expect(!CredentialValidator.isValidEmail(email)) }

    @Test func passwordStrength() {
        #expect(CredentialValidator.isStrongPassword("abc12345"))
        #expect(!CredentialValidator.isStrongPassword("short1"))
        #expect(!CredentialValidator.isStrongPassword("allletters"))
        #expect(!CredentialValidator.isStrongPassword("12345678"))
    }
    @Test func registrationIssuesInOrder() {
        #expect(CredentialValidator.validateRegistration(name: " ", email: "x", phone: "", password: "", confirm: "") == .emptyName)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "x", phone: "", password: "", confirm: "") == .invalidEmail)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "12", password: "", confirm: "") == .invalidPhone)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "", password: "weak", confirm: "weak") == .weakPassword)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "x") == .passwordMismatch)
        #expect(CredentialValidator.validateRegistration(name: "A", email: "a@b.com", phone: "0771234567", password: "abc12345", confirm: "abc12345") == nil)
    }
}

@MainActor
@Suite("AuthService")
struct AuthServiceTests {
    private func makeService() -> AuthService {
        let defaults = UserDefaults(suiteName: "auth-tests-\(UUID().uuidString)")!
        return AuthService(secrets: InMemorySecrets(), defaults: defaults)
    }

    @Test func registerSignsInAndStoresNoPlaintext() throws {
        let secrets = InMemorySecrets()
        let service = AuthService(secrets: secrets, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try service.register(fullName: "Ashan D", email: "Ashan@Gmail.com", phone: "", password: "abc12345", confirm: "abc12345")
        #expect(service.isSignedIn)
        #expect(service.currentUser?.email == "ashan@gmail.com")
        let stored = try #require(secrets.get("ashan@gmail.com"))
        #expect(String(data: stored, encoding: .utf8)?.contains("abc12345") != true)
    }

    @Test func duplicateEmailRejected() throws {
        let s = makeService()
        try s.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        s.signOut()
        #expect(throws: AuthError.emailAlreadyRegistered) {
            try s.register(fullName: "B", email: "A@B.com", phone: "", password: "abc12345", confirm: "abc12345")
        }
    }

    @Test func signInChecksPassword() throws {
        let s = makeService()
        try s.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        s.signOut()
        #expect(!s.isSignedIn)
        #expect(throws: AuthError.invalidCredentials) { try s.signIn(email: "a@b.com", password: "wrong") }
        try s.signIn(email: "a@b.com", password: "abc12345")
        #expect(s.isSignedIn)
    }

    @Test func passwordResetNeedsKnownAccount() throws {
        let s = makeService()
        #expect(throws: AuthError.accountNotFound) { try s.requestPasswordReset(email: "nobody@x.com") }
        try s.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        try s.requestPasswordReset(email: "a@b.com")
    }

    @Test func sessionSurvivesRelaunch() throws {
        let secrets = InMemorySecrets()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AuthService(secrets: secrets, defaults: defaults)
        try first.register(fullName: "A", email: "a@b.com", phone: "", password: "abc12345", confirm: "abc12345")
        let second = AuthService(secrets: secrets, defaults: defaults)
        #expect(second.currentUser?.fullName == "A")
    }
}
