import SwiftUI

struct ProfileView: View {
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.profileEdit) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.primary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(container.auth.currentUser?.fullName ?? "Driver").font(.headline)
                            Text(container.auth.currentUser?.email ?? "").font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            Section {
                link("My Vehicles", "car.fill", .vehicles)
                link("Favourite Locations", "star.fill", .favorites)
                link("Smart Parking Detection", "sensor.tag.radiowaves.forward.fill", .smartDetection)
            }
            Section {
                NavigationLink(value: AppRoute.security) {
                    HStack { Label("Face ID & Passcode", systemImage: "faceid"); Spacer()
                        Text(settings.biometricLockEnabled ? "On" : "Off").foregroundStyle(Theme.textSecondary) }
                }
                link("Notifications", "bell.fill", .reminders)
                link("Accessibility", "accessibility", .accessibility)
                link("iCloud Sync", "icloud.fill", .iCloud)
                Picker(selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
                } label: { Label("Appearance", systemImage: "moon.fill") }
            }
            Section {
                link("Help & Support", "questionmark.circle.fill", .help)
                link("About ParkingMate", "info.circle.fill", .about)
            }
            Section {
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        }
        .navigationTitle("Profile")
        .confirmationDialog("Log out of ParkingMate?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { container.auth.signOut() }
        }
    }

    private func link(_ title: String, _ symbol: String, _ route: AppRoute) -> some View {
        NavigationLink(value: route) { Label(title, systemImage: symbol) }
    }
}

struct EditProfileView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Name") { TextField("Full name", text: $name).textContentType(.name) }
            Section("Phone") { TextField("Phone number", text: $phone).keyboardType(.phonePad) }
            Section("Email") { Text(container.auth.currentUser?.email ?? "").foregroundStyle(Theme.textSecondary) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(Theme.danger) } }
        }
        .navigationTitle("My Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do { try container.auth.updateProfile(fullName: name, phone: phone); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .onAppear {
            name = container.auth.currentUser?.fullName ?? ""
            phone = container.auth.currentUser?.phone ?? ""
        }
    }
}

struct AccessibilitySettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityShowButtonShapes) private var systemShapes

    var body: some View {
        Form {
            Section {
                Toggle("Larger Text", isOn: $settings.largerText)
                Toggle("Increase Contrast", isOn: $settings.increaseContrast)
                Toggle("Bold Text", isOn: $settings.boldText)
                Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                Toggle("Button Shapes", isOn: $settings.buttonShapes)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
            } footer: {
                Text("ParkingMate also follows your iOS Dynamic Type, Bold Text, Reduce Motion and Increase Contrast settings automatically.")
            }
            Section("Detected from iOS") {
                LabeledContent("VoiceOver", value: voiceOver ? "On" : "Off")
                LabeledContent("Button Shapes", value: systemShapes ? "On" : "Off")
                Button("Open iOS Accessibility settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section("Preview") {
                Text("Parked at B2 • Blue • A124").font(.headline)
                Text("Your meter has 1h 45m left.").font(.subheadline)
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SecuritySettingsView: View {
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { settings.biometricLockEnabled }, set: { setLock($0) })) {
                    Label("Require \(container.lock.biometryName)", systemImage: "faceid")
                }
            } footer: {
                Text("When on, ParkingMate locks every time it goes to the background and asks for \(container.lock.biometryName) or your device passcode.")
            }
            if let message { Section { Text(message).foregroundStyle(Theme.danger) } }
        }
        .navigationTitle("Face ID & Security")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func setLock(_ on: Bool) {
        guard on else { settings.biometricLockEnabled = false; container.lock.reset(); return }
        Task {
            let result = await LocalAuthenticator().authenticate(reason: "Confirm to turn on app lock.")
            switch result {
            case .success: settings.biometricLockEnabled = true; message = nil
            case .cancelled: break
            case .unavailable(let m), .failed(let m): message = m
            }
        }
    }
}

struct ICloudSyncView: View {
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let sync = container.sync
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.fill").font(.system(size: 56)).foregroundStyle(Theme.primary)
                    Text("Sync your data across your Apple devices.").font(.headline).multilineTextAlignment(.center)
                    Text("Parking records, vehicles and favourites are kept up to date on every device signed in to your iCloud account.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            Section {
                Toggle("iCloud Sync", isOn: $settings.iCloudSyncEnabled)
                Label("Parking Records", systemImage: "car.fill")
                Label("Vehicles", systemImage: "car.side")
                Label("Favourites", systemImage: "star")
            } footer: {
                Text("Changing this takes effect the next time you open the app (the data store is set up at launch).")
            }
            Section("Status") {
                LabeledContent("Account", value: sync.accountStatus)
                LabeledContent("Last synced", value: sync.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                if sync.isSyncing { ProgressView("Syncing…") }
                if let error = sync.lastError { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                if let warning = container.persistence.startupWarning { Text(warning).font(.footnote).foregroundStyle(Theme.warning) }
                Button("Check iCloud status") { Task { await sync.refreshAccountStatus() } }
            }
            Section("Firebase Cloud Backend") {
                LabeledContent("Project ID", value: container.firebase.config.projectId)
                LabeledContent("Firebase Auth", value: container.auth.isSignedIn ? "Signed In" : "Local / Ready")
                LabeledContent("Cloud Firestore", value: container.firebase.isSyncing ? "Syncing..." : "Connected")
                LabeledContent("FCM Push Service", value: "Ready")
                if let lastSync = container.firebase.lastSyncTime {
                    LabeledContent("Last Cloud Sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.refreshAccountStatus() }
    }
}

struct HelpSupportView: View {
    private let faqs: [(String, String)] = [
        ("How do I save my parking spot?", "Tap Save Parking on the dashboard, choose floor/section, scan or type the bay number, then tap Save Parking Spot."),
        ("How does the bay-number scanner work?", "ParkingMate uses your camera and on-device text recognition to read signs like “A124”. Nothing leaves your phone."),
        ("Why didn't I get an expiry alert?", "Check Profile > Notifications, make sure notifications are allowed for ParkingMate, and that your meter timer was turned on when saving."),
        ("How accurate is the floor detection?", "Floor is estimated from the barometer (about 3 m per level). Always double-check in tall or sealed car parks.")
    ]
    var body: some View {
        List(faqs, id: \.0) { faq in
            DisclosureGroup(faq.0) { Text(faq.1).foregroundStyle(Theme.textSecondary) }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) { LogoMark(size: 72); BrandTitle(); Text("Smart Parking Assistant").foregroundStyle(Theme.textSecondary) }
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Module", value: "iOS Application Development")
                LabeledContent("Batch", value: "BSCCOMP25.1P")
            }
            Section("Credits") {
                Text("Parking facility data © OpenStreetMap contributors (Overpass API).")
                Text("Design: ParkingMate Figma prototype.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

