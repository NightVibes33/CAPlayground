import SwiftUI

struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appearance") private var appearance = "system"

    private let layers: [(LayerKind, String)] = [
        (.basic, "A fundamental solid color or shape layer (CALayer) for backgrounds or simple elements."),
        (.gradient, "Creates smooth color gradients with configurable colors, directions, and stops."),
        (.image, "Renders static images or photos, supporting scaling, positioning, and masking."),
        (.video, "Plays embedded video content as a looping animated element."),
        (.emitter, "Generates particle effects (CAEmitterLayer) like snow, fire, or confetti with customizable particles."),
        (.transform, "Controls 3D transformations, perspective, and depth for immersive, realistic layer interactions."),
        (.replicator, "Duplicates child layers in patterns for efficient repetitive designs."),
        (.liquidGlass, "A special effect layer simulating refractive, fluid glass distortion")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    layersSection
                    growingSection
                    footer
                }
            }
            .background(CATheme.background(scheme).ignoresSafeArea())
            .safeAreaInset(edge: .top) { navigation }
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Image(scheme == .dark ? "icon-dark" : "icon-light")
                .resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("CAPlayground").font(.title3.bold())
            Spacer()
            if horizontalSizeClass == .compact {
                Menu {
                    Link("Docs", destination: URL(string: "https://docs.enkei64.xyz")!)
                    NavigationLink("Contributors") { ContributorsView() }
                    NavigationLink("Roadmap") { RoadmapView() }
                    NavigationLink("Wallpapers") { WallpapersView() }
                    if auth.isSignedIn {
                        NavigationLink("Account") { AccountView() }
                    } else {
                        NavigationLink("Sign In") { SignInView() }
                    }
                    NavigationLink("Projects") { ProjectsView() }
                    Button(appearance == "dark" ? "Light Mode" : "Dark Mode", systemImage: appearance == "dark" ? "sun.max" : "moon") { toggleTheme() }
                } label: { Image(systemName: "line.3.horizontal").frame(width: 40, height: 40) }
            } else {
                HStack(spacing: 24) {
                    Link("Docs", destination: URL(string: "https://docs.enkei64.xyz")!)
                    NavigationLink("Contributors") { ContributorsView() }
                    NavigationLink("Roadmap") { RoadmapView() }
                    NavigationLink("Wallpapers") { WallpapersView() }
                }.font(.subheadline).foregroundStyle(.primary)
                if auth.isSignedIn {
                    Menu {
                        NavigationLink("Dashboard") { AccountView() }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { Task { await auth.signOut() } }
                    } label: { Image(systemName: "person").frame(width: 36, height: 36) }
                } else {
                    NavigationLink("Sign In") { SignInView() }.buttonStyle(.bordered)
                }
                NavigationLink(destination: ProjectsView()) {
                    Label("Projects", systemImage: "arrow.right").labelStyle(.titleAndIcon)
                }.buttonStyle(.borderedProminent).tint(CATheme.accent)
                Button { toggleTheme() } label: { Image(systemName: appearance == "dark" ? "sun.max" : "moon").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("Toggle theme")
            }
        }
        .padding(.horizontal, 20).frame(height: 56)
        .background(.regularMaterial).overlay(alignment: .bottom) { Divider() }
    }

    private func toggleTheme() {
        appearance = scheme == .dark ? "light" : "dark"
    }

    private var hero: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Image(scheme == .dark ? "app-dark" : "app-light")
                    .resizable().scaledToFit().opacity(geometry.size.width < 700 ? 0.5 : 1)
                    .frame(maxWidth: 1152).offset(y: geometry.size.width < 700 ? -190 : -40)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 32) { heroCopy; githubButton }
                    VStack(alignment: .leading, spacing: 24) { heroCopy; githubButton }
                }
                .padding(.horizontal, 24).padding(.bottom, 48).frame(maxWidth: 1400)
            }.frame(maxWidth: .infinity)
        }.containerRelativeFrame(.vertical)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink(destination: ProjectsView()) {
                Label("Blending Modes and Filters are out!", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(CATheme.accent)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(CATheme.accent.opacity(0.1), in: Capsule())
                    .overlay(Capsule().stroke(CATheme.accent.opacity(0.2)))
            }
            Text("The Open Source\n") + Text("CA Wallpaper Editor.").foregroundStyle(CATheme.accent)
            Text("Create beautiful animated wallpapers for iOS and iPadOS on any desktop computer with CAPlayground.")
                .font(.title2.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: 600, alignment: .leading)
            NavigationLink(destination: ProjectsView()) {
                Label("Get Started", systemImage: "paperplane.fill")
                    .font(.title3.weight(.semibold)).frame(minWidth: 200, minHeight: 56)
            }.buttonStyle(.borderedProminent).tint(CATheme.accent)
        }
        .font(.system(size: 64, weight: .bold))
        .frame(maxWidth: 900, alignment: .leading)
    }

    private var githubButton: some View {
        Link(destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!) {
            Label("View GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.body.weight(.medium)).frame(minWidth: 200, minHeight: 48)
        }.buttonStyle(.bordered)
    }

    private var layersSection: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                Text("Layers of Possibility.").font(.system(size: 52, weight: .bold))
                Text("Build complex wallpaper states by combining different layer types, each with their own unique properties and animations.")
                    .font(.title3.weight(.medium)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 680)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                ForEach(layers.indices, id: \.self) { index in
                    let kind = layers[index].0
                    let description = layers[index].1
                    VStack(alignment: .leading, spacing: 16) {
                        LayerPreview(kind: kind).frame(height: 200)
                        Text(kind == .basic ? "Basic Layer" : "\(kind.title) Layer").font(.title3.bold())
                        Text(description).foregroundStyle(.secondary).font(.subheadline)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).caPanel()
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 96).frame(maxWidth: 1400)
    }

    private var growingSection: some View {
        VStack(spacing: 64) {
            Text("CAPlayground is growing!").font(.system(size: 52, weight: .bold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 72) { statistic("100k+", "users in the first 4 months"); statistic("1.5k+", "Discord server members"); statistic("500+", "GitHub Commits") }
                VStack(spacing: 48) { statistic("100k+", "users in the first 4 months"); statistic("1.5k+", "Discord server members"); statistic("500+", "GitHub Commits") }
            }
        }.padding(.horizontal, 24).padding(.vertical, 112).frame(maxWidth: .infinity)
    }

    private func statistic(_ value: String, _ label: String) -> some View {
        VStack { Text(value).font(.system(size: 76, weight: .black)).foregroundStyle(CATheme.accent); Text(label).font(.title3.weight(.medium)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 250) }
    }

    private var footer: some View {
        HStack { Text("CAPlayground").fontWeight(.bold); Spacer(); Text("Open Source Core Animation Wallpaper Editor").foregroundStyle(.secondary) }
            .padding(24).overlay(alignment: .top) { Divider() }
    }
}

private struct LayerPreview: View {
    let kind: LayerKind
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.88))
            switch kind {
            case .basic: RoundedRectangle(cornerRadius: 22).fill(CATheme.accent).frame(width: 110, height: 110)
            case .gradient: Circle().fill(LinearGradient(colors: [.indigo, CATheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 130, height: 130)
            case .image: Image(systemName: "photo.fill").font(.system(size: 80)).foregroundStyle(CATheme.accent)
            case .video: Image(systemName: "play.rectangle.fill").font(.system(size: 76)).foregroundStyle(.white)
            case .emitter: Image(systemName: "sparkles").font(.system(size: 80)).foregroundStyle(CATheme.accent)
            case .transform: Image(systemName: "move.3d").font(.system(size: 80)).foregroundStyle(.indigo)
            case .replicator: HStack(spacing: -20) { ForEach(0..<4) { _ in Circle().fill(CATheme.accent.opacity(0.7)).frame(width: 70, height: 70) } }
            case .liquidGlass: RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial).frame(width: 150, height: 110).overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.5)))
            default: Image(systemName: kind.symbol).font(.system(size: 76)).foregroundStyle(CATheme.accent)
            }
        }
    }
}
