import SwiftUI
import MapKit

struct HistoryView: View {
    @Environment(AppContainer.self) private var container
    @State private var query = ""
    @State private var scope: HistoryScope = .location

    private var results: [ParkingSession] {
        SessionSearch.filter(container.store.sessions, query: query, scope: scope, vehicles: container.store.vehicles)
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(HistoryScope.allCases) { s in Chip(title: s.rawValue, isSelected: scope == s) { scope = s } } }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if results.isEmpty {
                EmptyStateView(systemImage: query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                               title: query.isEmpty ? "No parking history yet" : "No matches",
                               message: query.isEmpty ? "Places you park will appear here." : "Try a different search or filter.")
                    .listRowBackground(Color.clear)
            }
            ForEach(results) { session in
                NavigationLink(value: AppRoute.sessionDetail(session.id)) { row(session) }
                    .swipeActions {
                        Button(role: .destructive) { container.store.delete(session) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search by location, date, vehicle…")
        .navigationTitle("Parking History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ s: ParkingSession) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: s.isActive ? "parkingsign.circle.fill" : "mappin.circle.fill",
                      tint: s.isActive ? Theme.success : Theme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(s.locationLabel).font(.footnote).foregroundStyle(Theme.primary)
                Text(s.isActive ? "Active now" : Formatters.shortDate(s.startDate) + " • " + Formatters.time(s.startDate))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SessionDetailView: View {
    let sessionID: UUID
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = VoicePlaybackModel()
    @State private var confirmDelete = false

    var body: some View {
        if let s = container.store.session(id: sessionID) {
            ScrollView {
                VStack(spacing: 16) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: s.coordinate, latitudinalMeters: 300, longitudinalMeters: 300)),
                        interactionModes: []) {
                        Marker(s.title, systemImage: "car.fill", coordinate: s.coordinate)
                    }
                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .accessibilityLabel("Map of where you parked at \(s.title)")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        if !s.address.isEmpty { Text(s.address).foregroundStyle(Theme.textSecondary) }
                        InfoRow(systemImage: "mappin.circle", title: "Spot", value: s.locationLabel)
                        InfoRow(systemImage: "calendar", title: "Parked", value: s.startDate.formatted(date: .abbreviated, time: .shortened))
                        if let end = s.endDate { InfoRow(systemImage: "flag.checkered", title: "Left", value: end.formatted(date: .omitted, time: .shortened)) }
                        InfoRow(systemImage: "clock", title: "Duration", value: Formatters.duration(s.elapsed(at: Date())))
                        if s.hourlyRate > 0 { InfoRow(systemImage: "banknote", title: "Cost", value: Formatters.currency(s.cost(at: Date()))) }
                        if let v = container.store.vehicle(id: s.vehicleID) { InfoRow(systemImage: v.kind.symbol, title: "Vehicle", value: v.name) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).cardStyle()

                    if let data = s.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge)).accessibilityLabel("Saved parking photo")
                    }
                    if !s.note.isEmpty { Label(s.note, systemImage: "note.text").frame(maxWidth: .infinity, alignment: .leading).cardStyle() }
                    if let file = s.voiceNoteFileName {
                        VStack(alignment: .leading, spacing: 8) {
                            Button { player.toggle(file) } label: {
                                Label(player.isPlaying ? "Stop voice note" : "Play voice note", systemImage: player.isPlaying ? "stop.circle" : "play.circle")
                            }.buttonStyle(.secondary)
                            if !s.voiceTranscript.isEmpty { Text("“\(s.voiceTranscript)”").foregroundStyle(Theme.textSecondary) }
                        }
                        .cardStyle()
                    }
                    NavigationLink(value: AppRoute.costTracker(s.id)) { Label("Cost breakdown", systemImage: "banknote") }.buttonStyle(.secondary)
                    ShareLink(item: MapLinks.url(for: s.coordinate, name: s.title),
                              message: Text("I parked here: \(s.locationLabel)")) {
                        Label("Share location", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.secondary)
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(.link).foregroundStyle(Theme.danger)
                }
                .padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Parking Details").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { container.store.delete(s); dismiss() }
            }
        } else {
            EmptyStateView(systemImage: "questionmark.folder", title: "Record not found", message: "It may have been deleted.")
        }
    }
}

enum MapLinks {
    static func url(for c: CLLocationCoordinate2D, name: String) -> URL {
        var comps = URLComponents(string: "https://maps.apple.com/")!
        comps.queryItems = [URLQueryItem(name: "ll", value: "\(c.latitude),\(c.longitude)"),
                            URLQueryItem(name: "q", value: name)]
        return comps.url!
    }
}

