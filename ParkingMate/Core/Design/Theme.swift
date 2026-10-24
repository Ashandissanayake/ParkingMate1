import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Theme {
    static let primary = Color(light: 0x0066FF, dark: 0x3D85FF)
    static let primaryStrong = Color(light: 0x0050CB, dark: 0x6BA1FF)
    static let primarySoft = Color(light: 0xF0F4FF, dark: 0x1B2740)
    static let background = Color(light: 0xF8F9FD, dark: 0x0E1013)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1D21)
    static let fieldBackground = Color(light: 0xFFFFFF, dark: 0x22262B)
    static let textPrimary = Color(light: 0x191C1F, dark: 0xECEEF2)
    static let textSecondary = Color(light: 0x424656, dark: 0xB0B5C2)
    static let outline = Color(light: 0xC2C6D8, dark: 0x3A3F4B)
    static let success = Color(light: 0x1B8F55, dark: 0x4CD98F)
    static let warning = Color(light: 0xB45309, dark: 0xF5B041)
    static let danger = Color(light: 0xBA1A1A, dark: 0xFF7B72)
    static let heroTop = Color(hex: 0x0A2A66)
    static let heroBottom = Color(hex: 0x050D1F)
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [heroTop, heroBottom], startPoint: .top, endPoint: .bottom)
    }
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusXL: CGFloat = 24
    static let space: CGFloat = 16
    static let spaceSmall: CGFloat = 8
}

private struct HighContrastKey: EnvironmentKey { static let defaultValue = false }
private struct MotionReducedKey: EnvironmentKey { static let defaultValue = false }
private struct ButtonShapesKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var appHighContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }
    var appButtonShapes: Bool {
        get { self[ButtonShapesKey.self] }
        set { self[ButtonShapesKey.self] = newValue }
    }
    var appMotionReduced: Bool {
        get { self[MotionReducedKey.self] }
        set { self[MotionReducedKey.self] = newValue }
    }
}
struct AppAppearanceModifier: ViewModifier {
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(settings.appearance.colorScheme)
            .dynamicTypeSize(settings.largerText ? .xLarge ... .accessibility3 : .xSmall ... .accessibility3)
            .transformEnvironment(\.legibilityWeight) { weight in
                if settings.boldText { weight = .bold }
            }
            .environment(\.appHighContrast, settings.increaseContrast)
            .environment(\.appButtonShapes, settings.buttonShapes)
            .environment(\.appMotionReduced, settings.reduceMotion || systemReduceMotion)
            .tint(Theme.primary)
    }
}

