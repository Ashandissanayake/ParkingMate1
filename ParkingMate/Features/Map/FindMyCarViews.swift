import SwiftUI
import MapKit
import Combine

private struct NoCarView: View {
    var body: some View {
        EmptyStateView(systemImage: "car.side.lock", title: "No parked car",
                       message: "Save your parking spot first and it will appear here.")
            .frame(maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Find My Car (designs: find_my_car, find_my_car_map_view, find_my_car_colombo_city_mall)

struct FindMyCarView: View {
    @Environment(AppContainer.self) private var container
    var body: some View {
        if let session = container.store.activeSession {
            FindMyCarContent(session: session, routes: container.routes)
                .navigationTitle("Find My Car")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            NoCarView().navigationTitle("Find My Car")
        }
    }
}

private struct FindMyCarContent: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var vm: CarLocatorViewModel
    @State private var position: MapCameraPosition = .automatic
    @StateObject private var voicePlayer = VoicePlaybackModel()

    init(session: ParkingSession, routes: RouteProviding) {
        _vm = State(initialValue: CarLocatorViewModel(session: session, routes: routes))
    }

    var body: some View {
        let session = vm.session
        let layout = sizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(spacing: 16))
        ScrollView {
            layout {
                VStack(spacing: 16) {
                    infoCard(session)
                    map(session).frame(minHeight: 300, maxHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                }
                VStack(spacing: 16) {
                    radarCard(session)
                    memoryCard(session)
                    NavigationLink(value: AppRoute.navigateToCar) { Label("Start Walking Navigation", systemImage: "figure.walk") }
                        .buttonStyle(.primary)
                    if let error = vm.routeError { ErrorBanner(message: error) }
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await trackUser() }
    }

    private func trackUser() async {
        container.location.start()
        let initial = container.location.coordinate ?? AppConfig.fallbackCenter
        await vm.loadRoute(from: initial)
        while !Task.isCancelled {
            if let origin = container.location.coordinate, vm.shouldReroute(from: origin) {
                await vm.loadRoute(from: origin)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func infoCard(_ s: ParkingSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your car is here!", systemImage: "car.fill").font(.headline).foregroundStyle(Theme.primary)
            Text(s.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            HStack { InfoRow(systemImage: "square.stack.3d.up", title: "Floor", value: s.floor.isEmpty ? "–" : s.floor) }
            InfoRow(systemImage: "square.grid.2x2", title: "Section", value: s.section.isEmpty ? "–" : s.section)
            InfoRow(systemImage: "car.side", title: "Space", value: s.space.isEmpty ? "–" : s.space)
            InfoRow(systemImage: "clock", title: "Saved", value: s.startDate.formatted(date: .abbreviated, time: .shortened))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func map(_ s: ParkingSession) -> some View {
        Map(position: $position) {
            UserAnnotation()
            Annotation("My car", coordinate: s.coordinate) {
                Image(systemName: "car.fill").foregroundStyle(.white).padding(8)
                    .background(Theme.danger, in: Circle())
                    .accessibilityLabel("Your parked car, \(s.locationLabel)")
            }
            MapCircle(center: s.coordinate, radius: AppConfig.geofenceRadius)
                .foregroundStyle(Theme.primary.opacity(0.12)).stroke(Theme.primary.opacity(0.5), lineWidth: 1)
            if let route = vm.route {
                MapPolyline(route.polyline).stroke(Theme.primary, lineWidth: 6)
            }
        }
        .mapControls { MapUserLocationButton(); MapCompass() }
        .onChange(of: vm.route?.distance) { _, _ in
            if let rect = vm.route?.polyline.boundingMapRect {
                position = .rect(rect.insetBy(dx: -rect.width * 0.3, dy: -rect.height * 0.3))
            }
        }
        .onAppear { position = .region(MKCoordinateRegion(center: s.coordinate, latitudinalMeters: 300, longitudinalMeters: 300)) }
    }

    private func radarCard(_ s: ParkingSession) -> some View {
        let origin = container.location.coordinate
        let distance = origin.map { vm.distance(from: $0) }
        let bearing = origin.map { vm.bearing(from: $0) }
        let relative = (bearing ?? 0) - (container.location.heading ?? 0)
        return VStack(spacing: 12) {
            CarRadarView(relativeBearing: relative, hasFix: origin != nil && container.location.heading != nil)
                .frame(width: 180, height: 180)
            if let distance, let bearing {
                Text(Formatters.distance(distance)).font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Heading \(Int(bearing))° \(Geo.compassPoint(for: bearing))")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                if let route = vm.route {
                    Label("\(Int((route.expectedTravelTime / 60).rounded(.up))) min walk", systemImage: "figure.walk")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("Waiting for your location…").foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(distance.map {
            "Your car is \(Formatters.distance($0)) away, \(Geo.directionPhrase(relativeBearing: relative))"
        } ?? "Waiting for your location")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func memoryCard(_ s: ParkingSession) -> some View {
        if s.photoData != nil || s.voiceNoteFileName != nil || !s.note.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Visual & Audio Memory")
                if let data = s.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .accessibilityLabel("Photo of your parking spot")
                }
                if !s.note.isEmpty { Label(s.note, systemImage: "note.text").foregroundStyle(Theme.textPrimary) }
                if let file = s.voiceNoteFileName {
                    Button { voicePlayer.toggle(file) } label: {
                        Label(voicePlayer.isPlaying ? "Stop voice note" : "Play voice note",
                              systemImage: voicePlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    }.buttonStyle(.secondary)
                    if !s.voiceTranscript.isEmpty { Text("“\(s.voiceTranscript)”").font(.footnote).foregroundStyle(Theme.textSecondary) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}

/// Tiny playback helper (AVAudioPlayer) for the saved voice note.
@MainActor
final class VoicePlaybackModel: ObservableObject {
    @Published var isPlaying = false
    private let service = VoiceNoteService()
    private var poll: Task<Void, Never>?

    func toggle(_ fileName: String) {
        if service.isPlaying { service.stopPlayback(); isPlaying = false; poll?.cancel(); return }
        service.play(fileName: fileName)
        isPlaying = true
        poll = Task { [weak self] in
            while let self, self.service.isPlaying, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(300)) }
            self?.isPlaying = false
        }
    }
}

// MARK: - Radar (magnetometer heading + bearing to car)

struct CarRadarView: View {
    let relativeBearing: Double
    let hasFix: Bool
    @Environment(\.appMotionReduced) private var reduced

    var body: some View {
        ZStack {
            ForEach([1.0, 0.66, 0.33], id: \.self) { scale in
                Circle().stroke(Theme.primary.opacity(0.25), lineWidth: 1).scaleEffect(scale)
            }
            Circle().fill(Theme.primarySoft)
            Image(systemName: "location.north.fill")
                .font(.system(size: 52)).foregroundStyle(hasFix ? Theme.primary : Theme.outline)
                .rotationEffect(.degrees(relativeBearing))
                .animation(reduced ? nil : .easeOut(duration: 0.2), value: relativeBearing)
            Circle().fill(Theme.primary).frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Turn-by-turn style navigation (design: navigation_to_car)

struct NavigateToCarView: View {
    @Environment(AppContainer.self) private var container
    var body: some View {
        if let session = container.store.activeSession {
            NavigationContent(session: session, routes: container.routes)
                .navigationTitle("Navigate")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            NoCarView().navigationTitle("Navigate")
        }
    }
}

private struct NavigationContent: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CarLocatorViewModel
    @State private var lastAnnounced: String?

    init(session: ParkingSession, routes: RouteProviding) {
        _vm = State(initialValue: CarLocatorViewModel(session: session, routes: routes))
    }

    var body: some View {
        let origin = container.location.coordinate
        let arrived = origin.map { vm.hasArrived(from: $0) } ?? false
        ZStack(alignment: .bottom) {
            Map(initialPosition: .userLocation(followsHeading: true, fallback: .automatic)) {
                UserAnnotation()
                Annotation("My car", coordinate: vm.session.coordinate) {
                    Image(systemName: "car.fill").foregroundStyle(.white).padding(8).background(Theme.danger, in: Circle())
                }
                if let route = vm.route { MapPolyline(route.polyline).stroke(Theme.primary, lineWidth: 7) }
            }
            .mapControls { MapCompass() }
            .ignoresSafeArea(edges: .bottom)

            VStack {
                banner(origin: origin, arrived: arrived)
                Spacer()
                bottomCard(origin: origin, arrived: arrived)
            }
            .padding(12)
        }
        .task { await follow() }
        .onChange(of: arrived) { _, now in
            if now { Haptics.success(); AccessibilityNotification.Announcement("You have arrived at your car").post() }
        }
    }

    private func follow() async {
        container.location.start()
        let initial = container.location.coordinate ?? AppConfig.fallbackCenter
        await vm.loadRoute(from: initial)
        while !Task.isCancelled {
            if let origin = container.location.coordinate, vm.shouldReroute(from: origin) { await vm.loadRoute(from: origin) }
            if let origin = container.location.coordinate, let step = vm.currentStep(from: origin),
               step.instructions != lastAnnounced {
                lastAnnounced = step.instructions
                AccessibilityNotification.Announcement(step.instructions).post()
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func banner(origin: CLLocationCoordinate2D?, arrived: Bool) -> some View {
        let step = origin.flatMap { vm.currentStep(from: $0) }
        let text = arrived ? "You've arrived at your car" : (step?.instructions ?? "Head to your car")
        let distance = origin.map { Formatters.distance(vm.distance(from: $0)) } ?? "–"
        return HStack(spacing: 12) {
            Image(systemName: arrived ? "checkmark.circle.fill" : "arrow.up").font(.title2).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.headline).foregroundStyle(.white)
                Text(distance).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.heroTop, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func bottomCard(origin: CLLocationCoordinate2D?, arrived: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let route = vm.route {
                    Text("\(max(1, Int((route.expectedTravelTime / 60).rounded(.up)))) min").font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text(origin.map { Formatters.distance(vm.distance(from: $0)) } ?? "–").font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("Arrive at \(vm.session.space.isEmpty ? vm.session.locationLabel : vm.session.space)")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Group {
                if arrived {
                    Button("I've Reached My Car") { dismiss() }.buttonStyle(.primary)
                } else {
                    Button("End") { dismiss() }.buttonStyle(.destructive)
                }
            }
            .frame(maxWidth: 200)
        }
        .cardStyle()
    }
}
