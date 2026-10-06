import SwiftUI
enum SaveStartAction: Hashable { case scan, voice, photo }

struct ParkingPrefill: Hashable {
    var facility: ParkingFacility?
    var floorHint: String?
    var startAction: SaveStartAction?
}
enum AppRoute: Hashable {
    case saveParking(ParkingPrefill)
    case findMyCar, navigateToCar, timer, extend, reminders
    case costTracker(UUID), sessionDetail(UUID)
    case nearby(GeoPoint?), facility(ParkingFacility)
    case favorites, vehicles, shareLocation, smartDetection
    case profileEdit, accessibility, iCloud, security, help, about
    init?(deepLinkKey: String) {
        switch deepLinkKey {
        case "findMyCar": self = .findMyCar
        case "saveParking": self = .saveParking(ParkingPrefill())
        case "timer": self = .timer
        default: return nil
        }
    }
}

struct RouteDestination: View {
    let route: AppRoute
    var body: some View {
        switch route {
        case .saveParking(let prefill): SaveParkingView(prefill: prefill)
        case .findMyCar: FindMyCarView()
        case .navigateToCar: NavigateToCarView()
        case .timer: ParkingTimerView()
        case .extend: ExtendSessionView()
        case .reminders: ParkingRemindersView()
        case .costTracker(let id): CostTrackerView(sessionID: id)
        case .sessionDetail(let id): SessionDetailView(sessionID: id)
        case .nearby(let point): NearbyParkingView(initialCenter: point?.coordinate)
        case .facility(let f): FacilityDetailView(facility: f)
        case .favorites: FavoriteLocationsView()
        case .vehicles: VehiclesView()
        case .shareLocation: ShareLocationView()
        case .smartDetection: SmartDetectionView()
        case .profileEdit: EditProfileView()
        case .accessibility: AccessibilitySettingsView()
        case .iCloud: ICloudSyncView()
        case .security: SecuritySettingsView()
        case .help: HelpSupportView()
        case .about: AboutView()
        }
    }
}

extension View {
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
    }
}
struct PopToRootAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}
private struct PopToRootKey: EnvironmentKey { static let defaultValue = PopToRootAction() }
extension EnvironmentValues {
    var popToRoot: PopToRootAction {
        get { self[PopToRootKey.self] }
        set { self[PopToRootKey.self] = newValue }
    }
}
