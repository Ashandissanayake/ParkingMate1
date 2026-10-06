import SwiftUI
import PhotosUI
#if canImport(ConfettiSwiftUI)
import ConfettiSwiftUI
#endif
struct SaveParkingView: View {
    let prefill: ParkingPrefill
    var body: some View { SaveParkingForm(prefill: prefill) }
}

private struct SaveParkingForm: View {
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let prefill: ParkingPrefill
    @State private var vm: SaveParkingViewModel?
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showVoice = false
    @State private var photoItem: PhotosPickerItem?
    @State private var saved: ParkingSession?

    var body: some View {
        Group {
            if let vm { form(vm) } else { ProgressView() }
        }
        .navigationTitle("Save My Parking")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background.ignoresSafeArea())
        .task {
            if vm == nil {
                let model = SaveParkingViewModel(prefill: prefill, defaultRate: settings.defaultHourlyRate,
                                                 defaultVehicleID: container.store.defaultVehicle?.id,
                                                 hint: container.detectionHint)
                vm = model
                container.detectionHint = nil
                container.location.start()
                switch prefill.startAction {
                case .scan: showScanner = true
                case .voice: showVoice = true
                case .photo: showCamera = CameraPicker.isAvailable
                case nil: break
                }
            }
            if let location = container.location.location { await vm?.resolvePlace(for: location) }
        }
        .fullScreenCover(item: $saved) { session in
            ParkingSavedView(session: session) { viewMap in
                saved = nil
                dismiss()
                if viewMap {
                    Task { try? await Task.sleep(for: .milliseconds(400)); container.pendingRoute = .findMyCar }
                }
            }
        }
    }

    @ViewBuilder
    private func form(_ vm: SaveParkingViewModel) -> some View {
        let bind = Bindable(vm)
        ScrollView {
            VStack(spacing: 16) {
                locationCard(vm)
                photoCard(vm)

                VStack(spacing: 0) {
                    pickerRow("Floor", systemImage: "square.stack.3d.up", selection: bind.floor, options: AppConfig.floorOptions)
                    Divider()
                    pickerRow("Section", systemImage: "square.grid.2x2", selection: bind.section, options: AppConfig.sectionOptions)
                    Divider()
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "car.side")
                        Text("Space").foregroundStyle(Theme.textPrimary)
                        TextField("A124", text: bind.space).multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    .frame(minHeight: 56)
                }
                .cardStyle(padding: 12)

                HStack(spacing: 12) {
                    Button { showScanner = true } label: { Label("Scan Number", systemImage: "viewfinder") }
                        .buttonStyle(.primary)
                    Button { autoDetectFloor(vm) } label: { Label("Auto Floor", systemImage: "barometer") }
                        .buttonStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Add a note (optional)")
                    TextField("e.g. Near the elevator", text: bind.note, axis: .vertical).lineLimit(1...3)
                        .padding(12).background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    voiceRow(vm)
                }

                if !container.store.vehicles.isEmpty {
                    HStack {
                        IconBadge(systemImage: "car.fill")
                        Picker("Vehicle", selection: bind.vehicleID) {
                            ForEach(container.store.vehicles) { v in Text("\(v.name) • \(v.plate)").tag(Optional(v.id)) }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                    }
                    .cardStyle(padding: 12)
                }

                timerCard(vm)

                if let message = vm.errorMessage { ErrorBanner(message: message) }

                Button { save(vm) } label: { Label("Save Parking Spot", systemImage: "mappin.and.ellipse") }
                    .buttonStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.always)
        .fullScreenCover(isPresented: $showScanner) { ParkingNumberScannerSheet { vm.applyScannedNumber($0) } }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: { vm.setPhoto($0); showCamera = false }, onCancel: { showCamera = false })
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showVoice) {
            VoiceNoteSheet { file, text in vm.voiceNoteFileName = file; vm.voiceTranscript = text }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    vm.setPhoto(image)
                }
            }
        }
    }

    private func locationCard(_ vm: SaveParkingViewModel) -> some View {
        let location = container.location.location
        return HStack(spacing: 12) {
            IconBadge(systemImage: location == nil ? "location.slash" : "location.fill",
                      tint: location == nil ? Theme.warning : Theme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.address.isEmpty ? (location == nil ? "Waiting for GPS…" : "Current location") : vm.address)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                if let location {
                    Text("GPS accuracy ± \(Int(location.horizontalAccuracy)) m").font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Allow location access to save your spot").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if container.location.authorization == .denied {
                Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    .buttonStyle(.link)
            }
        }
        .cardStyle(padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func photoCard(_ vm: SaveParkingViewModel) -> some View {
        VStack(spacing: 10) {
            if let data = vm.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 160).clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .accessibilityLabel("Photo of your parking spot")
            }
            HStack(spacing: 12) {
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: { Label(vm.photoData == nil ? "Add Photo" : "Retake", systemImage: "camera") }
                        .buttonStyle(.secondary)
                }
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Library", systemImage: "photo") }
                    .buttonStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Sample:").font(.caption).foregroundStyle(Theme.textSecondary)
                Button("Slot A124") {
                    vm.setPhoto(SampleParkingImages.slotA124)
                    vm.floor = "B1"
                    vm.section = "Blue"
                    vm.space = "A124"
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))

                Button("Slot B-205") {
                    vm.setPhoto(SampleParkingImages.slotB205)
                    vm.floor = "B2"
                    vm.section = "Green"
                    vm.space = "B-205"
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))

                Button("Slot G-14") {
                    vm.setPhoto(SampleParkingImages.slotG14)
                    vm.floor = "G"
                    vm.section = "Purple"
                    vm.space = "G-14"
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
            }
        }
    }

    private func voiceRow(_ vm: SaveParkingViewModel) -> some View {
        Button { showVoice = true } label: {
            HStack {
                Image(systemName: "mic.fill")
                Text(vm.voiceNoteFileName == nil ? "Add Voice Note" : (vm.voiceTranscript.isEmpty ? "Voice note added" : vm.voiceTranscript))
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer()
                if vm.voiceNoteFileName != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }
            }
        }
        .buttonStyle(.secondary)
    }

    private func timerCard(_ vm: SaveParkingViewModel) -> some View {
        let bind = Bindable(vm)
        return VStack(alignment: .leading, spacing: 12) {
            ToggleRow(systemImage: "timer", title: "Set meter reminder",
                      subtitle: settings.remindersEnabled ? "Alert \(settings.reminderLeadMinutes) min before it expires" : "Reminders are off",
                      isOn: bind.timerEnabled)
            if vm.timerEnabled {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach([60, 120, 180, 240], id: \.self) { minutes in
                            Chip(title: "\(minutes / 60) Hour\(minutes == 60 ? "" : "s")", isSelected: vm.durationMinutes == minutes) {
                                vm.durationMinutes = minutes
                            }
                        }
                    }
                }
                Stepper("Duration: \(Formatters.duration(Double(vm.durationMinutes) * 60))",
                        value: bind.durationMinutes, in: 15...720, step: 15)
                Stepper("Rate: \(Formatters.currency(vm.hourlyRate)) / hour", value: bind.hourlyRate, in: 0...5000, step: 10)
            }
        }
        .cardStyle(padding: 12)
    }

    private func pickerRow(_ title: String, systemImage: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: systemImage)
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            Picker(title, selection: selection) { ForEach(options, id: \.self) { Text($0).tag($0) } }
                .pickerStyle(.menu)
        }
        .frame(minHeight: 56)
    }

    private func autoDetectFloor(_ vm: SaveParkingViewModel) {
        if let floor = container.altitude.estimatedFloor {
            vm.floor = floor
            vm.errorMessage = nil
            Haptics.success()
        } else {
            #if targetEnvironment(simulator)
            let simulatedFloors = ["B1", "B2", "L1", "L2", "G"]
            let current = vm.floor
            let next = simulatedFloors.first { $0 != current } ?? "B1"
            vm.floor = next
            vm.errorMessage = nil
            Haptics.success()
            #else
            vm.errorMessage = "Barometer data isn't available on this device – choose the floor manually."
            #endif
        }
    }

    private func save(_ vm: SaveParkingViewModel) {
        do {
            var coord = container.location.coordinate ?? prefill.facility?.coordinate ?? AppConfig.fallbackCenter
            if coord.latitude < 5.9 || coord.latitude > 9.9 || coord.longitude < 79.5 || coord.longitude > 82.0 {
                coord = AppConfig.fallbackCenter
            }
            let session = try vm.buildSession(coordinate: coord)
            if container.store.startSession(session) {
                Haptics.success()
                container.location.requestAlwaysPermission()
                if container.settings.voiceAnnouncementsEnabled {
                    container.voiceAnnouncement.announceParkingSaved(session: session)
                }
                saved = session
            } else {
                vm.errorMessage = container.store.lastError
            }
        } catch {
            vm.errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}

extension ParkingSession: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct ParkingSavedView: View {
    let session: ParkingSession
    var finish: (_ viewOnMap: Bool) -> Void
    @Environment(\.appMotionReduced) private var reduced
    @State private var appeared = false
    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            Theme.primaryStrong.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 88)).foregroundStyle(.white)
                    .scaleEffect(appeared || reduced ? 1 : 0.4)
                    .accessibilityHidden(true)
                    #if canImport(ConfettiSwiftUI)
                    .confettiCannon(counter: $confettiTrigger, num: 40, openingAngle: Angle(degrees: 60), closingAngle: Angle(degrees: 120), radius: 220)
                    #endif
                Text("Parking Saved!").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Text("Your parking location has been saved successfully.").foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 10) {
                    Label(session.locationLabel, systemImage: "mappin.circle.fill").font(.headline)
                    if let data = session.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Saved photo")
                    }
                    if !session.note.isEmpty { Label("Note: \(session.note)", systemImage: "note.text") }
                    if let expiry = session.expiryDate { Label("Meter until \(Formatters.time(expiry))", systemImage: "timer") }
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusXL))
                Spacer()
                Button("View on Map") { finish(true) }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: Theme.radiusMedium)).foregroundStyle(Theme.primaryStrong)
                Button("Done") { finish(false) }.foregroundStyle(.white).frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .onAppear {
            withAnimation(.spring) { appeared = true }
            #if canImport(ConfettiSwiftUI)
            confettiTrigger += 1
            #endif
        }
    }
}
