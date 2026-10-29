import SwiftUI

@main
struct ParkingMateApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environmentObject(container.settings)
                .modifier(AppAppearanceModifier(settings: container.settings))
        }
        .onChange(of: scenePhase) { _, phase in container.lock.scenePhaseChanged(phase) }
    }
}
