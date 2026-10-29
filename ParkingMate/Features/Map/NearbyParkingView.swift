import SwiftUI
import MapKit

/// Live parking pins from the Overpass API (designs: nearby_parking_map_radar_view, smart search).
struct NearbyParkingView: View {
    let initialCenter: CLLocationCoordinate2D?
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var vm: NearbyParkingViewModel?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedID: String?
    @State private var showList = false
    @State private var visibleCenter: CLLocationCoordinate2D?

    var body: some View {
        Group {
            if let vm { content(vm) } else { ProgressView() }
        }
        .navigationTitle("Nearby Parking")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil {
                container.location.start()
                let start = initialCenter ?? container.location.coordinate ?? AppConfig.fallbackCenter
                let model = NearbyParkingViewModel(provider: container.facilities, center: start)
                vm = model
                position = .region(MKCoordinateRegion(center: start, latitudinalMeters: 1800, longitudinalMeters: 1800))
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
        }
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
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
        position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1800, longitudinalMeters: 1800))
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Map(initialPosition: .region(MKCoordinateRegion(center: facility.coordinate, latitudinalMeters: 400, longitudinalMeters: 400)),
                    interactionModes: []) {
                    Marker(facility.name, systemImage: "p.circle.fill", coordinate: facility.coordinate)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .accessibilityLabel("Map showing \(facility.name)")

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
