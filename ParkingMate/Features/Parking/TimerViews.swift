import SwiftUI

private struct NoActiveSession: View {
    var title = "No active parking"
    var body: some View {
        EmptyStateView(systemImage: "timer", title: title, message: "Save your parking spot to start tracking time and cost.")
            .frame(maxHeight: .infinity).background(Theme.background.ignoresSafeArea())
    }
}

struct ParkingTimerView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false
    @State private var finished: ParkingSession?

    var body: some View {
        Group {
            if let session = container.store.activeSession { content(session) } else { NoActiveSession() }
        }
        .navigationTitle("Parking Timer")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $finished) { CostTrackerView(sessionID: $0.id) }
    }

    private func content(_ session: ParkingSession) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let remaining = session.remaining(at: context.date), let progress = session.progress(at: context.date) {
                        ProgressRing(progress: progress, title: Formatters.clock(remaining),
                                     subtitle: remaining == 0 ? "Time expired" : "Remaining Time",
                                     tint: remaining == 0 ? Theme.danger : Theme.primary)
                            .frame(width: 260, height: 260)
                    } else {
                        ProgressRing(progress: 1, title: Formatters.clock(session.elapsed(at: context.date)),
                                     subtitle: "Parked for").frame(width: 260, height: 260)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(systemImage: "mappin.circle", title: "Location", value: "\(session.title) • \(session.locationLabel)")
                    InfoRow(systemImage: "clock", title: "Parked at", value: session.startDate.formatted(date: .abbreviated, time: .shortened))
                    if let expiry = session.expiryDate { InfoRow(systemImage: "hourglass", title: "Expires", value: Formatters.time(expiry)) }
                }
                .cardStyle()

                HStack(spacing: 12) {
                    NavigationLink(value: AppRoute.extend) { Label("Extend", systemImage: "plus.circle") }.buttonStyle(.secondary)
                    NavigationLink(value: AppRoute.reminders) { Label("Reminder", systemImage: "bell") }.buttonStyle(.secondary)
                }
                Button { confirmStop = true } label: { Label("Stop Timer", systemImage: "stop.fill") }.buttonStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .confirmationDialog("End this parking session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("End & see cost", role: .destructive) { finished = container.store.endActiveSession() }
            Button("Keep parking", role: .cancel) {}
        } message: { Text("Your car stays in History. Reminders and geofence alerts will stop.") }
    }
}

struct ExtendSessionView: View {
    @Environment(AppContainer.self) private var container
    @State private var addMinutes = 60
    @State private var result: ParkingSession?
    private let quick = [30, 60, 120, 180]

    var body: some View {
        Group {
            if let session = container.store.activeSession { form(session) } else { NoActiveSession() }
        }
        .navigationTitle("Extend Parking")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $result) { SessionExtendedView(sessionID: $0.id, addedMinutes: addMinutes) }
    }

    private func form(_ session: ParkingSession) -> some View {
        let currentExpiry = max(session.expiryDate ?? Date(), Date())
        let newExpiry = currentExpiry.addingTimeInterval(Double(addMinutes) * 60)
        let extraCost = ParkingCostCalculator.cost(hourlyRate: session.hourlyRate, duration: Double(addMinutes) * 60)
        return ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(session.locationLabel).foregroundStyle(Theme.textSecondary)
                    if session.hourlyRate > 0 { Text("Rate \(Formatters.currency(session.hourlyRate)) / hour").font(.footnote).foregroundStyle(Theme.textSecondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).cardStyle()

                SectionTitle("Select additional time")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(quick, id: \.self) { m in
                        Chip(title: m < 60 ? "+\(m) mins" : "+\(m / 60) hour\(m == 60 ? "" : "s")", isSelected: addMinutes == m) { addMinutes = m }
                    }
                }
                Stepper("Fine tune: +\(Formatters.duration(Double(addMinutes) * 60))", value: $addMinutes, in: 5...480, step: 5)
                    .cardStyle(padding: 12)

                VStack(spacing: 10) {
                    SectionTitle("Extension summary")
                    InfoRow(systemImage: "clock", title: "Current expiry", value: Formatters.time(currentExpiry))
                    InfoRow(systemImage: "clock.badge.checkmark", title: "Extended expiry", value: Formatters.time(newExpiry))
                    InfoRow(systemImage: "plus.circle", title: "Additional time", value: Formatters.duration(Double(addMinutes) * 60))
                    InfoRow(systemImage: "banknote", title: "Estimated additional cost", value: Formatters.currency(extraCost))
                }
                .cardStyle()

                Button("Confirm & Extend") {
                    result = container.store.extend(sessionID: session.id, byMinutes: addMinutes)
                    if result != nil { Haptics.success() }
                }
                .buttonStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

struct SessionExtendedView: View {
    let sessionID: UUID
    let addedMinutes: Int
    @Environment(AppContainer.self) private var container
    @Environment(\.popToRoot) private var popToRoot

    var body: some View {
        let session = container.store.session(id: sessionID)
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                Text("Session Extended!").font(.title.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("Time added successfully. Your reminders were updated.").foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                if let session {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let remaining = session.remaining(at: context.date), let progress = session.progress(at: context.date) {
                            ProgressRing(progress: progress, title: Formatters.clock(remaining), subtitle: "Time left", lineWidth: 10)
                                .frame(width: 200, height: 200)
                        }
                    }
                    VStack(spacing: 10) {
                        InfoRow(systemImage: "plus.circle", title: "Added", value: Formatters.duration(Double(addedMinutes) * 60))
                        if let expiry = session.expiryDate { InfoRow(systemImage: "clock", title: "New expiry time", value: Formatters.time(expiry)) }
                        InfoRow(systemImage: "mappin.circle", title: "Location", value: session.locationLabel)
                    }
                    .cardStyle()
                }
                Button("Return to Dashboard") { popToRoot() }.buttonStyle(.primary)
                Button("Find My Car") { popToRoot(); container.pendingRoute = .findMyCar }.buttonStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Session Extended")
        .navigationBarBackButtonHidden(true)
    }
}

struct ParkingRemindersView: View {
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings
    @State private var pending: [PendingReminder] = []
    @State private var granted: Bool?
    private let leadOptions = [5, 10, 15, 30, 60]

    var body: some View {
        List {
            Section {
                Toggle("Enable reminders", isOn: $settings.remindersEnabled)
                Picker("Reminder time", selection: $settings.reminderLeadMinutes) {
                    ForEach(leadOptions, id: \.self) { Text("\($0) minutes before").tag($0) }
                }
                LabeledContent("Notification type", value: "Push notification")
            } header: { Text("Set a reminder") } footer: {
                Text("You'll get an alert before your meter runs out, with a quick “Extend 30 min” action.")
            }

            if granted == false {
                Section {
                    Button("Allow notifications in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } footer: { Text("Notifications are turned off for ParkingMate.") }
            }

            Section("Upcoming alerts") {
                if pending.isEmpty {
                    Text(container.store.activeSession == nil ? "No active parking session." : "No alerts scheduled.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(pending) { reminder in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title).font(.subheadline.weight(.semibold))
                        if let date = reminder.fireDate {
                            Text(date.formatted(date: .omitted, time: .shortened)).font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                Button("Send test notification") {
                    container.notifications.notifyNow(id: "test", title: "Parking reminder test",
                                                      body: "This is how your expiry alert will look.", userInfo: [:])
                }
            }
        }
        .navigationTitle("Parking Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: settings.remindersEnabled) { _, _ in apply() }
        .onChange(of: settings.reminderLeadMinutes) { _, _ in apply() }
    }

    private func apply() {
        container.store.refreshReminders()
        Task { try? await Task.sleep(for: .milliseconds(300)); await refresh() }
    }

    private func refresh() async {
        granted = await container.notifications.requestAuthorization()
        pending = await container.notifications.pendingReminders()
    }
}

struct CostTrackerView: View {
    let sessionID: UUID
    @Environment(AppContainer.self) private var container
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var rate: Double?

    var body: some View {
        if let session = container.store.session(id: sessionID) {
            let currentRate = rate ?? session.hourlyRate
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(session.locationLabel).foregroundStyle(Theme.textSecondary)
                        if session.isActive { Label("Active", systemImage: "circle.fill").font(.caption).foregroundStyle(Theme.success) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).cardStyle()

                    TimelineView(.periodic(from: .now, by: session.isActive ? 1 : 3600)) { context in
                        let duration = session.elapsed(at: context.date)
                        let total = ParkingCostCalculator.cost(hourlyRate: currentRate, duration: duration)
                        VStack(spacing: 12) {
                            HStack {
                                Text("Total Cost").foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(Formatters.currency(total)).font(.title.weight(.bold)).foregroundStyle(Theme.primary)
                            }
                            InfoRow(systemImage: "clock", title: "Duration", value: Formatters.duration(duration))
                            InfoRow(systemImage: "chart.line.uptrend.xyaxis", title: "Rate", value: "\(Formatters.currency(currentRate)) / hour")
                            Divider()
                            InfoRow(systemImage: "hourglass", title: "Billing", value: "15-minute blocks")
                        }
                        .cardStyle()
                        .accessibilityElement(children: .combine)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Enter parking fee")
                        Stepper("Hourly rate: \(Formatters.currency(currentRate))",
                                value: Binding(get: { currentRate }, set: { rate = $0 }), in: 0...5000, step: 10)
                    }
                    .cardStyle()

                    Button("Save") {
                        var updated = session
                        updated.hourlyRate = currentRate
                        container.store.update(updated)
                        settings.defaultHourlyRate = currentRate
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Parking Cost")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            NoActiveSession(title: "No parking to price").navigationTitle("Parking Cost")
        }
    }
}

