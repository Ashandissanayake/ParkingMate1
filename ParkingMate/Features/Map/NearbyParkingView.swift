import SwiftUI
import MapKit

/// Live parking pins from the Overpass API (designs: nearby_parking_map_radar_view, smart search).
struct NearbyParkingView: View {
    let initialCenter: CLLocationCoordinate2D?
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var vm: NearbyParkingViewModel?
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(center: AppConfig.fallbackCenter, latitudinalMeters: 5000, longitudinalMeters: 5000))
    @State private var selectedID: String?
    @State private var showList = false
    @State private var visibleCenter: CLLocationCoordinate2D?
    @State private var navigationRoute: WalkingRoute?

    var body: some View {
        Group {
            if let vm { content(vm) } else { ProgressView() }
        }
        .navigationTitle("Nearby Parking (Sri Lanka)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                container.location.start()
                let start = initialCenter ?? container.location.coordinate ?? AppConfig.fallbackCenter
                let model = NearbyParkingViewModel(provider: container.facilities, center: start)
                vm = model
                position = .region(MKCoordinateRegion(center: start, latitudinalMeters: 5000, longitudinalMeters: 5000))
                await model.load(around: start)
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: NearbyParkingViewModel) -> some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                VStack(spacing: 0) { header(vm); facilityList(vm) }.frame(width: 380)
                Divider()
                mapView(vm)
            }
        } else {
            ZStack(alignment: .bottom) {
                if showList {
                    VStack(spacing: 0) { header(vm); facilityList(vm) }
                } else {
                    mapView(vm)
                    VStack(spacing: 8) {
                        header(vm).background(.ultraThinMaterial)
                        Spacer()
                        if let facility = vm.filtered.first(where: { $0.id == selectedID }) {
                            FacilityCard(facility: facility, origin: container.location.coordinate ?? vm.center)
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("View", selection: $showList) {
                        Text("Map").tag(false); Text("List").tag(true)
                    }.pickerStyle(.segmented).frame(width: 140)
                }
            }
        }
    }

    private func header(_ vm: NearbyParkingViewModel) -> some View {
        let model = Bindable(vm)
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                TextField("Search area, e.g. Galle Road", text: model.searchText)
                    .submitLabel(.search)
                    .onSubmit { Task { if let c = await vm.search() { move(to: c) } } }
                if vm.isLoading { ProgressView() }
            }
            .padding(12)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    cityButton(name: "🇱🇰 Colombo", coord: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612), span: 5000, vm: vm)
                    cityButton(name: "🏔️ Kandy", coord: CLLocationCoordinate2D(latitude: 7.2906, longitude: 80.6337), span: 5000, vm: vm)
                    cityButton(name: "🏰 Galle", coord: CLLocationCoordinate2D(latitude: 6.0535, longitude: 80.2210), span: 5000, vm: vm)
                    cityButton(name: "✈️ Airport", coord: CLLocationCoordinate2D(latitude: 7.1808, longitude: 79.8841), span: 5000, vm: vm)
                    cityButton(name: "🗺️ All Sri Lanka", coord: CLLocationCoordinate2D(latitude: 7.8731, longitude: 80.7718), span: 350000, vm: vm)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(FacilityFilter.allCases) { f in
                        Chip(title: f.rawValue, systemImage: f.symbol, isSelected: vm.filter == f) { vm.filter = f }
                    }
                }
            }
            if let error = vm.errorMessage {
                ErrorBanner(message: error) { Task { await vm.load(around: vm.center) } }
            } else if vm.isFromCache {
                Label("Offline – showing saved results", systemImage: "wifi.slash").font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(12)
    }

    private func mapView(_ vm: NearbyParkingViewModel) -> some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(vm.filtered) { facility in
                Marker(facility.name, systemImage: facility.hasEVCharging ? "bolt.fill" : "p.circle.fill",
                       coordinate: facility.coordinate)
                    .tint(facility.isFree == true ? Theme.success : Theme.primary)
                    .tag(facility.id)
            }
            if let car = container.store.activeSession {
                Annotation("My car", coordinate: car.coordinate) {
                    Image(systemName: "car.fill").foregroundStyle(.white).padding(6).background(Theme.danger, in: Circle())
                }
            }
            if let route = navigationRoute {
                MapPolyline(route.polyline)
                    .stroke(Theme.primary, lineWidth: 6)
            }
        }
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
        .onChange(of: selectedID) { _, newID in
            guard let newID, let facility = vm.filtered.first(where: { $0.id == newID }) else {
                navigationRoute = nil
                return
            }
            let origin = container.location.coordinate ?? AppConfig.fallbackCenter
            Task {
                let route = try? await container.routes.walkingRoute(from: origin, to: facility.coordinate)
                navigationRoute = route
                if let rect = route?.polyline.boundingMapRect {
                    withAnimation {
                        position = .rect(rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35))
                    }
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in visibleCenter = context.region.center }
        .overlay(alignment: .top) {
            if let visibleCenter, vm.facilities.isEmpty == false || vm.errorMessage != nil {
                Button { Task { await vm.load(around: visibleCenter) } } label: {
                    Label("Search this area", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary).frame(width: 220).padding(.top, sizeClass == .regular ? 8 : 150)
            }
        }
    }

    private func facilityList(_ vm: NearbyParkingViewModel) -> some View {
        List {
            if vm.filtered.isEmpty && !vm.isLoading {
                EmptyStateView(systemImage: "parkingsign.circle", title: "No parking found",
                               message: "Try another filter or search a different area.")
                    .listRowBackground(Color.clear)
            }
            ForEach(vm.filtered) { facility in
                NavigationLink(value: AppRoute.facility(facility)) {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: facility.hasEVCharging ? "bolt.car.fill" : "parkingsign")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(facility.name).font(.subheadline.weight(.semibold))
                            Text("\(facility.feeSummary)\(facility.isCovered ? " • Covered" : "")")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(Formatters.distance(facility.distance(from: container.location.coordinate ?? vm.center)))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.plain)
    }

    private func move(to coordinate: CLLocationCoordinate2D) {
        position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000))
    }

    private func cityButton(name: String, coord: CLLocationCoordinate2D, span: CLLocationDistance, vm: NearbyParkingViewModel) -> some View {
        Button {
            position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: span, longitudinalMeters: span))
            Task { await vm.load(around: coord) }
        } label: {
            Text(name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.card, in: Capsule())
                .foregroundStyle(Theme.textPrimary)
                .overlay(Capsule().stroke(Theme.outline, lineWidth: 1))
        }
    }
}

/// Bottom card for the selected pin.
struct FacilityCard: View {
    let facility: ParkingFacility
    let origin: CLLocationCoordinate2D

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(facility.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(Formatters.distance(facility.distance(from: origin))).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }
            HStack(spacing: 8) {
                badge(facility.feeSummary, "tag.fill")
                if let capacity = facility.capacity { badge("\(capacity) spaces", "car.2.fill") }
                if facility.isCovered { badge("Covered", "building.2.fill") }
                if facility.hasEVCharging { badge("EV", "bolt.fill") }
            }
            HStack(spacing: 10) {
                NavigationLink(value: AppRoute.facility(facility)) { Text("Details") }.buttonStyle(.secondary)
                Button("Directions") { openInMaps() }.buttonStyle(.primary)
            }
        }
        .cardStyle()
    }

    private func badge(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.primarySoft, in: Capsule())
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: facility.coordinate))
        item.name = facility.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

// MARK: - Facility details (design: location_details_parking_facility)

struct FacilityDetailView: View {
    let facility: ParkingFacility
    @Environment(AppContainer.self) private var container
    @State private var route: WalkingRoute?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Map(position: $position) {
                    UserAnnotation()
                    Marker(facility.name, systemImage: "p.circle.fill", coordinate: facility.coordinate)
                    if let route {
                        MapPolyline(route.polyline)
                            .stroke(Theme.primary, lineWidth: 5)
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .accessibilityLabel("Map showing \(facility.name)")
                .task {
                    let origin = container.location.coordinate ?? AppConfig.fallbackCenter
                    route = try? await container.routes.walkingRoute(from: origin, to: facility.coordinate)
                    if let rect = route?.polyline.boundingMapRect {
                        position = .rect(rect.insetBy(dx: -rect.width * 0.3, dy: -rect.height * 0.3))
                    } else {
                        position = .region(MKCoordinateRegion(center: facility.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(facility.name).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    SectionTitle("Facility Information")
                    InfoRow(systemImage: "ruler", title: "Distance",
                            value: Formatters.distance(facility.distance(from: container.location.coordinate ?? AppConfig.fallbackCenter)))
                    InfoRow(systemImage: "banknote", title: "Parking Fee", value: facility.feeSummary)
                    if let capacity = facility.capacity { InfoRow(systemImage: "car.2.fill", title: "Total Spaces", value: "\(capacity)") }
                    if let type = facility.parkingType { InfoRow(systemImage: "building.2", title: "Type", value: type.capitalized) }
                    if let hours = facility.openingHours { InfoRow(systemImage: "clock", title: "Hours", value: hours) }
                    if let op = facility.operatorName { InfoRow(systemImage: "person.2", title: "Operator", value: op) }
                    InfoRow(systemImage: "bolt.car", title: "EV charging", value: facility.hasEVCharging ? "Yes" : "No / unknown")
                    Text("Data © OpenStreetMap contributors").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                Button { openInMaps() } label: { Label("Directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    .buttonStyle(.primary)
                NavigationLink(value: AppRoute.saveParking(ParkingPrefill(facility: facility))) {
                    Label("Park Here", systemImage: "parkingsign.circle")
                }.buttonStyle(.secondary)
                Button { addFavorite() } label: { Label("Add to Favourites", systemImage: "star") }.buttonStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Parking Facility")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: facility.coordinate))
        item.name = facility.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func addFavorite() {
        container.store.addFavorite(FavoriteLocation(name: facility.name, detail: facility.feeSummary,
                                                     latitude: facility.latitude, longitude: facility.longitude))
        Haptics.success()
    }
}
