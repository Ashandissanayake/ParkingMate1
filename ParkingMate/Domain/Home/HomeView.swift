import SwiftUI
struct HomeView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass

    private struct Action: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let route: AppRoute
    }

    private var parkingActions: [Action] {
        [
            Action(id: "findParking", title: "Find Parking", subtitle: "Search nearby", symbol: "magnifyingglass", tint: Theme.primary, route: .nearby(nil)),
            Action(id: "findCar", title: "Find My Car", subtitle: "Locate your car", symbol: "car.fill", tint: Theme.success, route: .findMyCar),
            Action(id: "save", title: "Save Parking", subtitle: "Save current spot", symbol: "bookmark.fill", tint: .indigo, route: .saveParking(ParkingPrefill())),
            Action(id: "timer", title: "Parking Timer", subtitle: "Start / manage", symbol: "timer", tint: .orange, route: .timer),
            Action(id: "cost", title: "Parking Cost", subtitle: "Calculate cost", symbol: "banknote.fill", tint: .pink, route: .costTracker(container.store.activeSession?.id ?? container.store.history.first?.id ?? UUID()))
        ]
    }

    private var navigationActions: [Action] {
        [
            Action(id: "navigate", title: "Navigate to Car", subtitle: "Walking directions", symbol: "location.fill", tint: Theme.primary, route: .navigateToCar),
            Action(id: "share", title: "Share Location", subtitle: "Send your spot", symbol: "square.and.arrow.up", tint: .teal, route: .shareLocation),
            Action(id: "favorites", title: "Favourites", subtitle: "Saved places", symbol: "star.fill", tint: .yellow, route: .favorites)
        ]
    }

    private var smartActions: [Action] {
        [
            Action(id: "scan", title: "Scan Parking Spot", subtitle: "Camera finds bay no.", symbol: "camera.viewfinder", tint: .pink,
                   route: .saveParking(ParkingPrefill(startAction: .scan))),
            Action(id: "voice", title: "Voice Note", subtitle: "Record a landmark", symbol: "mic.fill", tint: .purple,
                   route: .saveParking(ParkingPrefill(startAction: .voice))),
            Action(id: "smart", title: "Smart Parking", subtitle: "Auto-detect parking", symbol: "sensor.tag.radiowaves.forward.fill", tint: .green, route: .smartDetection),
            Action(id: "reminder", title: "Set Reminder", subtitle: "Before it expires", symbol: "bell.fill", tint: .orange, route: .reminders)
        ]
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        ActiveSessionCard().frame(maxWidth: 420)
                        actionsColumn
                    }
                } else {
                    ActiveSessionCard()
                    actionsColumn
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.always)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("ParkingMate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.nearby(nil)) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search parking")
            }
        }
    }

    private var hero: some View {
        let first = container.auth.currentUser?.fullName.split(separator: " ").first.map(String.init) ?? "there"
        return VStack(alignment: .leading, spacing: 6) {
            Text("Hi, \(first)").font(.title2.weight(.bold)).foregroundStyle(.white)
            Label("Quick actions – everything in one place", systemImage: "bolt.fill")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var actionsColumn: some View {
        VStack(spacing: 20) {
            section("Parking", parkingActions)
            section("Navigation", navigationActions)
            section("Smart Features", smartActions)
        }
    }

    private func section(_ title: String, _ actions: [Action]) -> some View {
        VStack(spacing: 10) {
            SectionTitle(title)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(actions) { action in
                    NavigationLink(value: action.route) {
                        HStack(spacing: 10) {
                            IconBadge(systemImage: action.symbol, tint: action.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text(action.subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .cardStyle(padding: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(action.title): \(action.subtitle)")
                    .accessibilityHint("Opens \(action.title)")
                }
            }
        }
    }
}
struct ActiveSessionCard: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        if let session = container.store.activeSession {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Parked now", systemImage: "parkingsign.circle.fill").font(.headline)
                        .foregroundStyle(Theme.primary)
                    Spacer()
                    NavigationLink(value: AppRoute.sessionDetail(session.id)) { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Open parking details")
                }
                Text(session.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(session.locationLabel).foregroundStyle(Theme.textSecondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let remaining = session.remaining(at: context.date), let progress = session.progress(at: context.date) {
                        HStack(spacing: 16) {
                            ProgressRing(progress: progress, title: Formatters.clock(remaining),
                                         subtitle: remaining == 0 ? "Expired" : "Remaining", lineWidth: 8,
                                         tint: remaining == 0 ? Theme.danger : Theme.primary)
                                .frame(width: 120, height: 120)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Parked \(Formatters.time(session.startDate))").font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(Formatters.currency(session.cost(at: context.date)) + " so far").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    } else {
                        Text("Parked for \(Formatters.duration(session.elapsed(at: context.date))) – no timer set")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }

                HStack(spacing: 12) {
                    NavigationLink(value: AppRoute.findMyCar) { Label("Find my car", systemImage: "location.fill") }
                        .buttonStyle(.primary)
                    NavigationLink(value: AppRoute.extend) { Label("Extend", systemImage: "plus.circle") }
                        .buttonStyle(.secondary)
                }
            }
            .cardStyle()
        } else {
            VStack(spacing: 8) {
                EmptyStateView(systemImage: "parkingsign.circle", title: "No car saved yet",
                               message: "Save your spot in a few taps so you can find it later.")
                NavigationLink(value: AppRoute.saveParking(ParkingPrefill())) { Text("Save My Parking") }
                    .buttonStyle(.primary)
            }
            .cardStyle()
        }
    }
}
