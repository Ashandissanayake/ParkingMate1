import Foundation
import LocalAuthentication
import SwiftUI

enum BiometricResult: Equatable {
    case success
    case cancelled
    case unavailable(String)
    case failed(String)
}

protocol BiometricAuthenticating {
    var biometryName: String { get }
    func authenticate(reason: String) async -> BiometricResult
}
struct LocalAuthenticator: BiometricAuthenticating {
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func authenticate(reason: String) async -> BiometricResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(error?.localizedDescription ?? "Authentication is not available on this device.")
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .failed("Authentication failed.")
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            default: return .failed(laError.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
@MainActor
@Observable
final class AppLockController {
    private(set) var isLocked = false
    private(set) var showWelcomeBack = false
    private(set) var lastMessage: String?

    @ObservationIgnored private let authenticator: BiometricAuthenticating
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let isSignedIn: () -> Bool

    init(authenticator: BiometricAuthenticating? = nil,
         isEnabled: @escaping () -> Bool,
         isSignedIn: @escaping () -> Bool) {
        self.authenticator = authenticator ?? LocalAuthenticator()
        self.isEnabled = isEnabled
        self.isSignedIn = isSignedIn
    }

    var biometryName: String { authenticator.biometryName }
    func lockIfNeeded() {
        if isEnabled() && isSignedIn() { isLocked = true }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background { lockIfNeeded() }
    }

    func unlock() async {
        lastMessage = nil
        switch await authenticator.authenticate(reason: "Unlock ParkingMate to see your parked car.") {
        case .success:
            isLocked = false
            showWelcomeBack = true
            Haptics.success()
        case .cancelled: break
        case .unavailable(let m), .failed(let m): lastMessage = m
        }
    }

    func dismissWelcome() { showWelcomeBack = false }
    func reset() { isLocked = false; showWelcomeBack = false; lastMessage = nil }
}

