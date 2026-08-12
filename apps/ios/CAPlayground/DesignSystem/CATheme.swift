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

struct CAWebsiteNavigation: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        HStack(spacing: 12) {
            Image(scheme == .dark ? "icon-dark" : "icon-light").resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("CAPlayground").font(.custom("Helvetica Neue", size: 20).weight(.bold))
            Spacer()
            if sizeClass == .compact {
                Menu {
                    Link("Docs", destination: URL(string: "https://docs.enkei64.xyz")!)
                    NavigationLink("Contributors") { ContributorsView() }; NavigationLink("Roadmap") { RoadmapView() }; NavigationLink("Wallpapers") { WallpapersView() }
                    if auth.isSignedIn { NavigationLink("Account") { AccountView() } } else { NavigationLink("Sign In") { SignInView() } }
                    NavigationLink("Projects") { ProjectsView() }
                    Button(scheme == .dark ? "Light Mode" : "Dark Mode", systemImage: scheme == .dark ? "sun.max" : "moon") { appearance = scheme == .dark ? "light" : "dark" }
                } label: { Image(systemName: "line.3.horizontal").frame(width: 40, height: 40) }
            } else {
                HStack(spacing: 24) { Link("Docs", destination: URL(string: "https://docs.enkei64.xyz")!); NavigationLink("Contributors") { ContributorsView() }; NavigationLink("Roadmap") { RoadmapView() }; NavigationLink("Wallpapers") { WallpapersView() } }.font(.system(size: 16))
                if auth.isSignedIn { NavigationLink { AccountView() } label: { Image(systemName: "person").frame(width: 36, height: 36) } } else { NavigationLink("Sign In") { SignInView() }.buttonStyle(CAWebButtonStyle(variant: .outline)) }
                NavigationLink { ProjectsView() } label: { Label("Projects", systemImage: "arrow.right") }.buttonStyle(CAWebButtonStyle(variant: .accent))
                Button { appearance = scheme == .dark ? "light" : "dark" } label: { Image(systemName: scheme == .dark ? "sun.max" : "moon").frame(width: 36, height: 36) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).frame(height: 56)
        .background(CATheme.background(scheme).opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CATheme.border(scheme), lineWidth: 1) }.shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
}
