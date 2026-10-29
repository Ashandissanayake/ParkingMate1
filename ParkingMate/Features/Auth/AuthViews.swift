import SwiftUI
import AuthenticationServices

// MARK: - Splash (design: parkingmate_splash_screen)

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                LogoMark(size: 112, onDark: true)
                BrandTitle(onDark: true)
                Text("Smart Parking Assistant").foregroundStyle(.white.opacity(0.8))
            }
            VStack {
                Spacer()
                Text("Never forget\nwhere you parked.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 48)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ParkingMate. Never forget where you parked.")
    }
}

// MARK: - Auth flow container

enum AuthRoute: Hashable { case createAccount, forgotPassword, checkEmail }

struct AuthFlowView: View {
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            SignInView(path: $path)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .createAccount: CreateAccountView(path: $path)
                    case .forgotPassword: ForgotPasswordView(path: $path)
                    case .checkEmail: CheckEmailView(path: $path)
                    }
                }
        }
    }
}

private struct AuthHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(spacing: 8) {
            LogoMark(size: 80)
            BrandTitle()
            Text("Smart Parking Assistant").font(.footnote).foregroundStyle(Theme.textSecondary)
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.textPrimary).padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Sign in (design: parkingmate_sign_in)

struct SignInView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme
    @Binding var path: [AuthRoute]
    @AppStorage("auth.rememberedEmail") private var rememberedEmail = ""
    @State private var email = ""
    @State private var password = ""
    @State private var remember = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeader(title: "Welcome Back", subtitle: "Sign in to your account")
                VStack(spacing: 12) {
                    IconField(title: "Email", systemImage: "envelope", text: $email,
                              keyboard: .emailAddress, contentType: .username)
                    IconField(title: "Password", systemImage: "lock", text: $password,
                              isSecure: true, contentType: .password)
                }
                HStack {
                    Button { remember.toggle() } label: {
                        Label("Remember me", systemImage: remember ? "checkmark.square.fill" : "square")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(minHeight: 44)
                    .accessibilityAddTraits(remember ? .isSelected : [])
                    Spacer()
                    Button("Forgot password?") { path.append(.forgotPassword) }.buttonStyle(.link)
                }
                .font(.subheadline)

                if let errorMessage { ErrorBanner(message: errorMessage) }

                Button("Sign In", action: signIn).buttonStyle(.primary)

                HStack { Rectangle().fill(Theme.outline).frame(height: 1); Text("or").font(.footnote)
                    .foregroundStyle(Theme.textSecondary); Rectangle().fill(Theme.outline).frame(height: 1) }
                    .accessibilityHidden(true)

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))

                HStack(spacing: 4) {
                    Text("Don't have an account?").foregroundStyle(Theme.textSecondary)
                    Button("Sign Up") { path.append(.createAccount) }.buttonStyle(.link)
                }
                .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: 480)               // keeps the form readable on iPad
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear { email = rememberedEmail }
    }

    private func signIn() {
        do {
            try container.auth.signIn(email: email, password: password)
            rememberedEmail = remember ? email : ""
            container.lock.reset()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            var name = ""
            if let components = credential.fullName { name = PersonNameComponentsFormatter().string(from: components) }
            container.auth.signInWithApple(userID: credential.user, fullName: name, email: credential.email)
        case .failure:
            errorMessage = "Sign in with Apple isn't available for this build. Use email and password."
        }
    }
}

// MARK: - Create account (design: parkingmate_create_account)

struct CreateAccountView: View {
    @Environment(AppContainer.self) private var container
    @Binding var path: [AuthRoute]
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeader(title: "Create Account", subtitle: "Join ParkingMate and never lose your parking spot again.")
                VStack(spacing: 12) {
                    IconField(title: "Full Name", systemImage: "person", text: $name,
                              contentType: .name, capitalization: .words)
                    IconField(title: "Email Address", systemImage: "envelope", text: $email,
                              keyboard: .emailAddress, contentType: .emailAddress)
                    IconField(title: "Phone Number", systemImage: "phone", text: $phone,
                              keyboard: .phonePad, contentType: .telephoneNumber)
                    IconField(title: "Password", systemImage: "lock", text: $password,
                              isSecure: true, contentType: .newPassword)
                    IconField(title: "Confirm Password", systemImage: "lock", text: $confirm,
                              isSecure: true, contentType: .newPassword)
                }
                if let errorMessage { ErrorBanner(message: errorMessage) }
                Button("Create Account", action: create).buttonStyle(.primary)
                HStack(spacing: 4) {
                    Text("Already have an account?").foregroundStyle(Theme.textSecondary)
                    Button("Sign In") { path.removeAll() }.buttonStyle(.link)
                }
                .font(.subheadline)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() {
        do {
            try container.auth.register(fullName: name, email: email, phone: phone, password: password, confirm: confirm)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: - Forgot password + check email

struct ForgotPasswordView: View {
    @Environment(AppContainer.self) private var container
    @Binding var path: [AuthRoute]
    @State private var email = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeader(title: "Forgot Password?",
                           subtitle: "Enter your email address and we'll send you a reset link.")
                IconField(title: "Email Address", systemImage: "envelope", text: $email,
                          keyboard: .emailAddress, contentType: .emailAddress)
                if let errorMessage { ErrorBanner(message: errorMessage) }
                Button("Send Reset Link") {
                    do { try container.auth.requestPasswordReset(email: email); path.append(.checkEmail) }
                    catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.primary)
                Button("Back to Login") { path.removeAll() }.buttonStyle(.link)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(false)
    }
}

struct CheckEmailView: View {
    @Binding var path: [AuthRoute]
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack(alignment: .topTrailing) {
                Image(systemName: "envelope.fill").font(.system(size: 72)).foregroundStyle(Theme.primary)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.success)
                    .background(Circle().fill(Theme.card)).offset(x: 12, y: -10)
            }
            .accessibilityHidden(true)
            Text("Check Your Email").font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text("We've sent a password reset link to your email address.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
            Text("If you don't see it, check your spam folder.").font(.footnote).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Back to Login") { path.removeAll() }.buttonStyle(.primary)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Face ID lock (design: parkingmate_face_id_authentication) + welcome back

struct BiometricLockView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                LogoMark(size: 84, onDark: true)
                BrandTitle(onDark: true)
                Spacer()
                Image(systemName: container.lock.biometryName == "Face ID" ? "faceid" : "lock.shield")
                    .font(.system(size: 72, weight: .thin)).foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text(container.lock.biometryName).font(.title2.weight(.semibold)).foregroundStyle(.white)
                Text("Use \(container.lock.biometryName) to unlock ParkingMate")
                    .foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                if let message = container.lock.lastMessage {
                    Text(message).font(.footnote).foregroundStyle(.white).padding(10)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                Button("Unlock") { Task { await container.lock.unlock() } }.buttonStyle(.primary)
                Button("Sign out") { container.auth.signOut() }
                    .foregroundStyle(.white.opacity(0.85)).frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 480)
        }
        .task { await container.lock.unlock() }          // prompt immediately, like the design
    }
}

struct WelcomeBackView: View {
    @Environment(AppContainer.self) private var container
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 96)).foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Text("Welcome Back").font(.title.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text("You have successfully signed in with \(container.lock.biometryName).")
                .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Continue") { container.lock.dismissWelcome() }.buttonStyle(.primary)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            container.lock.dismissWelcome()
        }
    }
}
