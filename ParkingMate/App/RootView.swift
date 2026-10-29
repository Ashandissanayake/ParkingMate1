import SwiftUI

/// Splash → auth → (Face ID lock) → main app.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if !container.auth.isSignedIn {
                    AuthFlowView()
                } else if container.lock.isLocked {
                    BiometricLockView()
                } else if container.lock.showWelcomeBack {
                    WelcomeBackView()
                } else {
                    MainView()
                }
            }
            .transition(.opacity)

            if showSplash {
                SplashView().transition(.opacity).zIndex(1)
            }
        }
        .task {
            container.lock.lockIfNeeded()        // cold launch2
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSplash = false }
        }
        .task(id: container.auth.isSignedIn) {
            guard container.auth.isSignedIn else { return }
            container.startServices()
            _ = await container.notifications.requestAuthorization()
        }
        .onChange(of: container.auth.isSignedIn) { _, signedIn in
            if !signedIn { container.lock.reset() }
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case home, history, map, profile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .map: return "Map"
        case .profile: return "Profile"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .map: return "map.fill"
        case .profile: return "person.fill"
        }
    }
}

/// iPhone → bottom tab bar. iPad (regular width) → sidebar + detail (multi-device adaptation, LO1).
struct MainView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: MainTab = .home
    @State private var homePath = NavigationPath()

    var body: some View {
        Group {
            if sizeClass == .regular { splitLayout } else { tabLayout }
        }
        .environment(\.popToRoot, PopToRootAction { homePath = NavigationPath() })
        .onChange(of: container.pendingRoute) { _, route in
            guard let route else { return }
            tab = .home
            homePath.append(route)
            container.pendingRoute = nil
        }
    }

    private var tabLayout: some View {
        TabView(selection: $tab) {
            ForEach(MainTab.allCases) { item in
                root(for: item)
                    .tabItem { Label(item.title, systemImage: item.symbol) }
                    .tag(item)
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(MainTab.allCases, selection: Binding<MainTab?>(get: { tab }, set: { if let v = $0 { tab = v } })) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("ParkingMate")
        } detail: {
            root(for: tab)
        }
    }

    @ViewBuilder
    private func root(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: $homePath) { HomeView().appRoutes() }
        case .history:
            NavigationStack { HistoryView().appRoutes() }
        case .map:
            NavigationStack { NearbyParkingView(initialCenter: nil).appRoutes() }
        case .profile:
            NavigationStack { ProfileView().appRoutes() }
        }
    }
}
