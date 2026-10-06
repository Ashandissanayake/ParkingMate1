import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .foregroundStyle(.white)
            .background(Theme.primary.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .foregroundStyle(Theme.primary)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .stroke(Theme.primary.opacity(0.25), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .foregroundStyle(.white)
            .background(Theme.danger, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
struct LinkButtonStyle: ButtonStyle {
    @Environment(\.accessibilityShowButtonShapes) private var systemShapes
    @Environment(\.appButtonShapes) private var appShapes
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.primary)
            .underline(systemShapes || appShapes)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { .init() } }
extension ButtonStyle where Self == DestructiveButtonStyle { static var destructive: DestructiveButtonStyle { .init() } }
extension ButtonStyle where Self == LinkButtonStyle { static var link: LinkButtonStyle { .init() } }

struct CardModifier: ViewModifier {
    @Environment(\.appHighContrast) private var highContrast
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(highContrast ? Theme.textPrimary : Theme.outline.opacity(0.35), lineWidth: highContrast ? 1.5 : 0.5))
            .shadow(color: Theme.primary.opacity(0.08), radius: 10, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
    func motionSafe<V: Equatable>(_ animation: Animation? = .easeInOut(duration: 0.25), value: V) -> some View {
        modifier(MotionSafeModifier(animation: animation, value: value))
    }
}

private struct MotionSafeModifier<V: Equatable>: ViewModifier {
    @Environment(\.appMotionReduced) private var reduced
    let animation: Animation?
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduced ? nil : animation, value: value)
    }
}

struct IconField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .never
    @State private var reveal = false
    @Environment(\.appHighContrast) private var highContrast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Group {
                if isSecure && !reveal {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .foregroundStyle(Theme.textPrimary)
            if isSecure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel(reveal ? "Hide password" : "Show password")
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
            .stroke(highContrast ? Theme.textPrimary : Theme.outline, lineWidth: highContrast ? 1.5 : 1))
    }
}

struct Chip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .background(isSelected ? Theme.primary : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct IconBadge: View {
    let systemImage: String
    var tint: Color = Theme.primary
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct InfoRow: View {
    let systemImage: String
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(Theme.primary).frame(width: 24).accessibilityHidden(true)
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
struct ProgressRing: View {
    let progress: Double
    let title: String
    let subtitle: String
    var lineWidth: CGFloat = 12
    var tint: Color = Theme.primary
    @Environment(\.appMotionReduced) private var reduced

    var body: some View {
        ZStack {
            Circle().stroke(Theme.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduced ? nil : .linear(duration: 0.5), value: progress)
            VStack(spacing: 4) {
                Image(systemName: "car.fill").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .padding(lineWidth + 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subtitle): \(title)")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(Theme.primary).accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.primary).padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).accessibilityHidden(true)
            Text(message).font(.footnote).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            if let retry { Button("Retry", action: retry).buttonStyle(.link) }
        }
        .padding(12)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ToggleRow: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                IconBadge(systemImage: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.textPrimary)
                    if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary) }
                }
            }
        }
        .frame(minHeight: 44)
    }
}
struct LogoMark: View {
    var size: CGFloat = 72
    var onDark = false
    var body: some View {
        ZStack {
            Circle().fill(onDark ? Color.white : Theme.primarySoft)
            Image(systemName: "parkingsign.circle.fill")
                .font(.system(size: size * 0.6))
                .foregroundStyle(Theme.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BrandTitle: View {
    var onDark = false
    var body: some View {
        (Text("Parking").foregroundColor(onDark ? .white : Theme.textPrimary) + Text("Mate").foregroundColor(Theme.primary))
            .font(.system(.title, design: .rounded).weight(.bold))
            .accessibilityLabel("ParkingMate")
    }
}
