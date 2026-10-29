import SwiftUI
import MapKit

// MARK: - Favourites (design: favorite_locations)

struct FavoriteLocationsView: View {
    @Environment(AppContainer.self) private var container
    @State private var showAdd = false
    @State private var name = ""

    var body: some View {
        List {
            if container.store.favorites.isEmpty {
                EmptyStateView(systemImage: "star", title: "No favourites yet",
                               message: "Add the malls, airports and offices you park at most.")
                    .listRowBackground(Color.clear)
            }
            ForEach(container.store.favorites) { fav in
                NavigationLink(value: AppRoute.nearby(fav.point)) {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "mappin.circle.fill")
                        VStack(alignment: .leading) {
                            Text(fav.name).font(.subheadline.weight(.semibold))
                            if !fav.detail.isEmpty { Text(fav.detail).font(.footnote).foregroundStyle(Theme.textSecondary) }
                        }
                        Spacer()
                        Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favourite")
                    }
                }
                .swipeActions { Button(role: .destructive) { container.store.deleteFavorite(id: fav.id) } label: { Label("Remove", systemImage: "trash") } }
            }
        }
        .navigationTitle("Favourite Locations")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { name = container.store.activeSession?.title ?? ""; showAdd = true } label: { Label("Add Favourite", systemImage: "plus") }
                .buttonStyle(.primary).padding()
        }
        .alert("Add favourite", isPresented: $showAdd) {
            TextField("Name", text: $name)
            Button("Save") { add() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saves your current location (or your parked car) as a favourite.") }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let session = container.store.activeSession
        guard let coordinate = container.location.coordinate ?? session?.coordinate else { return }
        container.store.addFavorite(FavoriteLocation(name: trimmed,
                                                     detail: session?.locationLabel.replacingOccurrences(of: " • ", with: " - ") ?? "",
                                                     latitude: coordinate.latitude, longitude: coordinate.longitude))
        Haptics.success()
    }
}

// MARK: - Vehicles (design: my_vehicles)

struct VehiclesView: View {
    @Environment(AppContainer.self) private var container
    @State private var showAdd = false

    var body: some View {
        List {
            if container.store.vehicles.isEmpty {
                EmptyStateView(systemImage: "car.side", title: "No vehicles", message: "Add your car so history and reminders know which vehicle you used.")
                    .listRowBackground(Color.clear)
            }
            ForEach(container.store.vehicles) { v in
                Button { container.store.setDefaultVehicle(id: v.id) } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: v.kind.symbol)
                        VStack(alignment: .leading) {
                            Text(v.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("\(v.name) • \(v.plate)").font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: v.isDefault ? "largecircle.fill.circle" : "circle").foregroundStyle(Theme.primary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(v.isDefault ? .isSelected : [])
                .accessibilityHint("Sets as default vehicle")
                .swipeActions { Button(role: .destructive) { container.store.deleteVehicle(id: v.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
        .navigationTitle("My Vehicles")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { showAdd = true } label: { Label("Add Vehicle", systemImage: "plus") }.buttonStyle(.secondary).padding()
        }
        .sheet(isPresented: $showAdd) { AddVehicleSheet() }
    }
}

struct AddVehicleSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Vehicle.Kind = .car
    @State private var name = ""
    @State private var plate = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) { ForEach(Vehicle.Kind.allCases) { Text($0.title).tag($0) } }
                TextField("Make & model (e.g. Toyota Corolla)", text: $name)
                TextField("Plate (e.g. ABC 1234)", text: $plate).textInputAutocapitalization(.characters)
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        container.store.addVehicle(Vehicle(kind: kind, name: name, plate: plate.uppercased()))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || plate.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Share location (design: location_sharing)

struct ShareLocationView: View {
    @Environment(AppContainer.self) private var container
    @State private var copied = false
    @State private var cloudShare: SharedParkingLocation?
    @State private var isSharingCloud = false

    var body: some View {
        VStack(spacing: 20) {
            if let s = container.store.activeSession {
                let url = MapLinks.url(for: s.coordinate, name: s.title)
                Image(systemName: "square.and.arrow.up.circle.fill").font(.system(size: 80)).foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                Text("Share your parked location with family or friends.").font(.headline).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(s.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Label("Firebase Cloud", systemImage: "icloud.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.primary.opacity(0.12), in: Capsule())
                    }
                    Text(s.locationLabel).foregroundStyle(Theme.textSecondary)
                    if !s.note.isEmpty { Text(s.note).font(.footnote).foregroundStyle(Theme.textSecondary) }
                    if let cloud = cloudShare {
                        Divider().padding(.vertical, 4)
                        HStack {
                            Image(systemName: "link.circle.fill").foregroundStyle(Theme.primary)
                            Text("Cloud Share ID: \(cloud.id.uppercased())")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).cardStyle()
                Spacer()
                ShareLink(item: url, subject: Text("My parked car"),
                          message: Text("I parked at \(s.title) – \(s.locationLabel). \(s.note)")) {
                    Label("Share Location", systemImage: "square.and.arrow.up")
                }.buttonStyle(.primary)
                Button {
                    Task {
                        isSharingCloud = true
                        let user = container.auth.currentUser?.fullName ?? "ParkingMate User"
                        cloudShare = try? await container.firebase.createLocationShare(for: s, sharedBy: user)
                        isSharingCloud = false
                        UIPasteboard.general.url = cloudShare?.shareURL ?? url
                        copied = true
                        Haptics.success()
                    }
                } label: {
                    Label(copied ? "Cloud Link Copied!" : (isSharingCloud ? "Generating..." : "Copy Cloud Share Link"),
                          systemImage: copied ? "checkmark" : "bolt.horizontal.icloud.fill")
                }.buttonStyle(.secondary)
            } else {
                EmptyStateView(systemImage: "mappin.slash", title: "Nothing to share", message: "Save your parking spot first.")
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Share Location")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let s = container.store.activeSession, cloudShare == nil {
                let user = container.auth.currentUser?.fullName ?? "ParkingMate User"
                cloudShare = try? await container.firebase.createLocationShare(for: s, sharedBy: user)
            }
        }
    }
}

// MARK: - Smart parking detection (designs: smart_parking_detection_*, parking_zone_detection)

struct SmartDetectionView: View {
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.appMotionReduced) private var reduced
    @State private var pulse = false
    @State private var voiceTested = false
    @State private var carSimulated = false

    var body: some View {
        let motion = container.motion
        let altitude = container.altitude
        let location = container.location.location
        let bluetooth = container.bluetooth

        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    ForEach(0..<3) { i in
                        Circle().stroke(Theme.primary.opacity(0.25), lineWidth: 1.5)
                            .frame(width: 80 + CGFloat(i) * 55, height: 80 + CGFloat(i) * 55)
                            .scaleEffect(pulse && !reduced ? 1.08 : 1)
                    }
                    Image(systemName: "car.fill").font(.title).foregroundStyle(.white).padding(18).background(Theme.primary, in: Circle())
                }
                .frame(height: 200)
                .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true } }
                .accessibilityHidden(true)

                Label(motion.isRunning ? motion.status : "Smart Sensors Active",
                      systemImage: motion.isRunning ? "dot.radiowaves.left.and.right" : "waveform.path")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.primarySoft, in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)

                // 1. CoreMotion Walk Detection
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(get: { settings.autoDetectParking }, set: { settings.autoDetectParking = $0; container.applyAutoDetectSetting() })) {
                        Label("Detect when I park", systemImage: "figure.walk.motion")
                    }
                    if !motion.isAvailable {
                        Text("Motion activity isn't available on this device.").font(.footnote).foregroundStyle(Theme.danger)
                    }
                    Text("When you stop driving and start walking, ParkingMate offers to save your spot. Keep the app open or recently used for best results.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .cardStyle()

                // 2. Feature B: Bluetooth & CarPlay Disconnect Auto-Save
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(get: { settings.bluetoothAutoSaveEnabled }, set: { settings.bluetoothAutoSaveEnabled = $0; container.applyBluetoothSetting() })) {
                        Label("Bluetooth & CarPlay Auto-Save", systemImage: "car.side.fill")
                    }
                    Text("Automatically records and saves your parking location the moment your car Bluetooth or CarPlay audio disconnects.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)

                    Divider().padding(.vertical, 2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Car Audio Status").font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text(bluetooth.lastEventDescription ?? (bluetooth.isCarConnected ? "Connected to vehicle" : "Monitoring audio route"))
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button {
                            carSimulated = true
                            bluetooth.simulateDisconnect()
                            Haptics.success()
                        } label: {
                            Label("Simulate Disconnect", systemImage: "bolt.badge.clock.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.secondary)
                    }
                }
                .cardStyle()

                // 3. Feature E: Siri Voice Audio Announcements
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.voiceAnnouncementsEnabled) {
                        Label("Siri Voice Announcements", systemImage: "speaker.wave.3.fill")
                    }
                    Text("Speaks parking spot details, walking navigation directions, and checkout reminders out loud.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)

                    Divider().padding(.vertical, 2)

                    HStack {
                        Text("Voice Feedback").font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button {
                            voiceTested = true
                            container.voiceAnnouncement.speak("ParkingMate Smart Voice is active. Ready to guide you to your vehicle in Colombo.")
                            Haptics.success()
                        } label: {
                            Label("Test Voice", systemImage: "play.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.secondary)
                    }
                }
                .cardStyle()

                // 4. Feature F: Geofence Auto-Checkout
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.autoCheckoutEnabled) {
                        Label("Geofence Smart Auto-Checkout", systemImage: "flag.checkered.circle.fill")
                    }
                    Text("When you depart your parked vehicle beyond the 75m geofence, ParkingMate automatically ends the session, calculates duration and final fee, and speaks a checkout confirmation.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .cardStyle()

                // 5. Detected location & altitude details
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Detected location details")
                    InfoRow(systemImage: "square.stack.3d.up", title: "Floor (barometer)",
                            value: altitude.estimatedFloor ?? "Level G (Default)")
                    if let rel = altitude.relativeAltitude {
                        InfoRow(systemImage: "arrow.up.and.down", title: "Relative altitude", value: String(format: "%+.1f m", rel))
                    }
                    InfoRow(systemImage: "scope", title: "GPS precision",
                            value: location.map { "± \(Int($0.horizontalAccuracy)) m" } ?? "Waiting…")
                    Button("Set here as ground level") { altitude.recalibrate() }.buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading).cardStyle()

                NavigationLink(value: AppRoute.saveParking(ParkingPrefill(floorHint: altitude.estimatedFloor))) {
                    Label("Confirm & Save Parking Spot", systemImage: "checkmark")
                }.buttonStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Auto Detect Location")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            container.location.start()
            container.altitude.start()
            if settings.bluetoothAutoSaveEnabled { container.bluetooth.startMonitoring() }
        }
    }
}
