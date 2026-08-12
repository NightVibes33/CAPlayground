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

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : .white
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkCard : lightCard
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
