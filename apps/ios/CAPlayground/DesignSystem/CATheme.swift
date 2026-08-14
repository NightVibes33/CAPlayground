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

    static func foreground(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255) : lightForeground }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255) : lightCard }
    static func mutedForeground(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkMuted : lightForeground }
    static func border(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255) : Color(red: 209 / 255, green: 213 / 255, blue: 219 / 255) }
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBackground : .white }
    static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkCard : lightCard }
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
        content.background(CATheme.card(scheme)).clipShape(RoundedRectangle(cornerRadius: CATheme.radius, style: .continuous)).overlay {
            RoundedRectangle(cornerRadius: CATheme.radius, style: .continuous).stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
    }
}

extension View { func caPanel() -> some View { modifier(CAPanelModifier()) } }

struct CAWebsiteNavigation: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"

    var isScrolled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                HStack(spacing: 10) {
                    Image(scheme == .dark ? "icon-dark" : "icon-light")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("CAPlayground")
                        .font(.custom("Helvetica Neue", size: 20).weight(.bold))
                        .foregroundStyle(CATheme.foreground(scheme))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("CAPlayground Home")

            Spacer()

            if sizeClass == .compact {
                Menu {
                    Link("Docs", destination: URL(string: "https://docs.enkei64.xyz")!)
                    NavigationLink("Contributors") { ContributorsView() }
                    NavigationLink("Roadmap") { RoadmapView() }
                    NavigationLink("Wallpapers") { WallpapersView() }
                    if auth.isSignedIn {
                        NavigationLink("Account") { DashboardView() }
                        Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                    } else {
                        NavigationLink("Sign In") { SignInView() }
                    }
                    NavigationLink("Projects") { ProjectsView() }
                    Button(scheme == .dark ? "Light Mode" : "Dark Mode", systemImage: scheme == .dark ? "sun.max" : "moon") {
                        appearance = scheme == .dark ? "light" : "dark"
                    }
                } label: {
                    Image(systemName: "line.3.horizontal").frame(width: 40, height: 40)
                }
            } else {
                HStack(spacing: 24) {
                    Link("Docs", destination: URL(string: "https://docs.enkei64.xyz")!)
                    NavigationLink("Contributors") { ContributorsView() }
                    NavigationLink("Roadmap") { RoadmapView() }
                    NavigationLink("Wallpapers") { WallpapersView() }
                }
                .font(.system(size: 16))

                if auth.isSignedIn {
                    Menu {
                        NavigationLink("Dashboard") { DashboardView() }
                        Divider()
                        Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                    } label: {
                        Image(systemName: "person")
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Account menu")
                } else {
                    NavigationLink("Sign In") { SignInView() }
                        .buttonStyle(CAWebButtonStyle(variant: .outline))
                }

                NavigationLink { ProjectsView() } label: {
                    Label("Projects", systemImage: "arrow.right")
                }
                .buttonStyle(CAWebButtonStyle(variant: .accent))

                Button { appearance = scheme == .dark ? "light" : "dark" } label: {
                    Image(systemName: scheme == .dark ? "sun.max" : "moon").frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, isScrolled ? 20 : 24)
        .frame(height: isScrolled ? 56 : 64)
        .background {
            if isScrolled {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CATheme.background(scheme).opacity(0.80))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Rectangle()
                    .fill(CATheme.background(scheme).opacity(0.80))
                    .background(.ultraThinMaterial)
            }
        }
        .overlay {
            if isScrolled {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CATheme.border(scheme), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isScrolled ? 0.10 : 0), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.30), value: isScrolled)
    }
}

struct CAWebsiteFooter: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 56) {
                VStack(spacing: 20) {
                    Text("Ready to get started?").font(.system(size: sizeClass == .compact ? 30 : 38, weight: .bold)).multilineTextAlignment(.center)
                    Text("Build your first animated wallpaper in minutes. No sign in required.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ViewThatFits(in: .horizontal) { HStack(spacing: 12) { footerActions }; VStack(spacing: 12) { footerActions } }
                }.frame(maxWidth: 760)
                Group {
                    if sizeClass == .compact {
                        VStack(alignment: .leading, spacing: 32) { aboutColumn; resourcesColumn; communityColumn }
                    } else {
                        HStack(alignment: .top, spacing: 64) { aboutColumn; resourcesColumn; communityColumn }
                    }
                }.frame(maxWidth: 1152, alignment: .leading)
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack { copyright; Spacer(); legalLinks }
                    VStack(alignment: .leading, spacing: 14) { copyright; legalLinks }
                }.frame(maxWidth: 1152)
                Text("CAPlayground").font(.system(size: sizeClass == .compact ? 56 : 116, weight: .black)).tracking(sizeClass == .compact ? -3 : -7).lineLimit(1).minimumScaleFactor(0.45).frame(maxWidth: 1280).padding(.top, 4).accessibilityHidden(true)
            }.padding(.horizontal, sizeClass == .compact ? 24 : 32).padding(.vertical, 48).frame(maxWidth: .infinity)
        }.background(CATheme.muted(scheme).opacity(0.30))
    }
    @ViewBuilder private var footerActions: some View {
        NavigationLink { ProjectsView() } label: { Label("Get Started", systemImage: "paperplane.fill") }.buttonStyle(CAWebButtonStyle(variant: .accent))
        Link(destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!) { Label("View GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }.buttonStyle(CAWebButtonStyle(variant: .outline))
    }
    private var aboutColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { Image(scheme == .dark ? "icon-dark" : "icon-light").resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8)); Text("CAPlayground").font(.headline) }
            Text("Create beautiful animated wallpapers for iOS and iPadOS on any desktop computer.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: 320, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var resourcesColumn: some View {
        VStack(alignment: .leading, spacing: 12) { Text("Resources").font(.subheadline.bold()); Link("Documentation", destination: URL(string: "https://docs.enkei64.xyz")!); NavigationLink("Roadmap") { RoadmapView() }; NavigationLink("Tendies Checker") { TendiesCheckerView() } }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var communityColumn: some View {
        VStack(alignment: .leading, spacing: 12) { Text("Community").font(.subheadline.bold()); NavigationLink("Contributors") { ContributorsView() }; Link("GitHub", destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!); Link("Discord", destination: URL(string: "https://discord.gg/8rW3SHsK8b")!) }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var copyright: some View { Text("© 2025 CAPlayground. All rights reserved.").font(.caption).foregroundStyle(.secondary) }
    private var legalLinks: some View { HStack(spacing: 18) { NavigationLink("Privacy Policy") { PrivacyPolicyView() }; NavigationLink("Terms of Service") { TermsOfServiceView() } }.font(.caption) }
}
