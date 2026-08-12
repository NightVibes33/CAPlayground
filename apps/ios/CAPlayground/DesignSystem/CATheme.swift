import SwiftUI

enum CATheme {
    static let accent = Color(red: 90 / 255, green: 209 / 255, blue: 151 / 255)
    static let destructive = Color(red: 190 / 255, green: 18 / 255, blue: 60 / 255)
    static let lightForeground = Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255)
    static let lightCard = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
    static let darkBackground = Color(red: 11 / 255, green: 11 / 255, blue: 11 / 255)
    static let darkCard = Color(red: 15 / 255, green: 17 / 255, blue: 21 / 255)
    static let darkMuted = Color(red: 156 / 255, green: 163 / 255, blue: 175 / 255)
    static let radius: CGFloat = 8
    static let largeRadius: CGFloat = 16

    static func foreground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255) : lightForeground
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255) : lightCard
    }

    static func mutedForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkMuted : lightForeground
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255) : Color(red: 209 / 255, green: 213 / 255, blue: 219 / 255)
    }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : .white
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkCard : lightCard
    }
}

struct CAWebButtonStyle: ButtonStyle {
    enum Variant { case accent, outline, ghost }
    @Environment(\.colorScheme) private var scheme
    let variant: Variant
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(variant == .accent ? .white : CATheme.foreground(scheme))
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { if variant == .outline { RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme), lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private func background(_ pressed: Bool) -> Color {
        switch variant {
        case .accent: CATheme.accent.opacity(pressed ? 0.82 : 1)
        case .outline: CATheme.background(scheme).opacity(pressed ? 0.8 : 0.5)
        case .ghost: CATheme.muted(scheme).opacity(pressed ? 0.8 : 0)
        }
    }
}

struct CAPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(CATheme.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: CATheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CATheme.radius, style: .continuous)
                    .stroke(.separator.opacity(0.55), lineWidth: 0.5)
            }
    }
}

extension View {
    func caPanel() -> some View { modifier(CAPanelModifier()) }
}
