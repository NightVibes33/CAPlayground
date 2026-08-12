import SwiftUI

struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                        layersSection
                        growingSection
                        footer
                    }
                }
                .background(CATheme.background(scheme).ignoresSafeArea())
                CAWebsiteNavigation().padding(.horizontal, horizontalSizeClass == .compact ? 16 : 24).padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
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
                .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 24).padding(.bottom, horizontalSizeClass == .compact ? 40 : 64).frame(maxWidth: 1400)
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
            (Text("The Open Source\n") + Text("CA Wallpaper Editor.").foregroundStyle(CATheme.accent))
                .font(.system(size: horizontalSizeClass == .compact ? 48 : 72, weight: .bold))
                .tracking(-1.5)
            Text("Create beautiful animated wallpapers for iOS and iPadOS on any desktop computer with CAPlayground.")
                .font(.title2.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: 600, alignment: .leading)
            NavigationLink(destination: ProjectsView()) {
                Label("Get Started", systemImage: "paperplane.fill")
                    .font(.title3.weight(.semibold)).frame(minWidth: 200, minHeight: 56)
            }.buttonStyle(CAWebButtonStyle(variant: .accent, height: 56))
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private var githubButton: some View {
        Link(destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!) {
            Label("View GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.body.weight(.medium)).frame(minWidth: 200, minHeight: 48)
        }.buttonStyle(CAWebButtonStyle(variant: .outline, height: 48))
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
                    ZStack(alignment: .bottomLeading) {
                        LayerPreview(kind: kind)
                        LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind == .basic ? "Basic Layer" : "\(kind.title) Layer").font(.system(size: 22, weight: .bold))
                            Text(description).font(.system(size: 14)).foregroundStyle(Color(white: 0.82)).lineLimit(horizontalSizeClass == .compact ? 2 : nil)
                        }.padding(24)
                    }
                    .foregroundStyle(.white).frame(height: horizontalSizeClass == .compact ? 300 : 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color(white: scheme == .dark ? 0.12 : 0.82), lineWidth: 1) }
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
        HStack { Text("CAPlayground").fontWeight(.bold); Spacer(); NavigationLink("Privacy") { PrivacyPolicyView() }; NavigationLink("Terms") { TermsOfServiceView() }; NavigationLink("Tendies Checker") { TendiesCheckerView() } }
            .padding(24).overlay(alignment: .top) { Divider() }
    }
}

private struct LayerPreview: View {
    let kind: LayerKind
    @State private var animate = false
    var body: some View {
        ZStack {
            Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255)
            switch kind {
            case .basic:
                Circle().fill(Color(red: 82 / 255, green: 82 / 255, blue: 1)).frame(width: 96, height: 96).offset(x: 70, y: -70)
                    .shadow(color: Color.blue.opacity(0.4), radius: 20)
                RoundedRectangle(cornerRadius: 16).fill(Color(red: 1, green: 82 / 255, blue: 82 / 255)).frame(width: 128, height: 128)
                    .rotationEffect(.degrees(animate ? 45 : 12)).shadow(color: Color.red.opacity(0.4), radius: 20)
            case .gradient:
                LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { RadialGradient(colors: [.white.opacity(0.4), .clear], center: UnitPoint(x: 0.5, y: 1.2), startRadius: 0, endRadius: 260) }
            case .image:
                Image("app-dark").resizable().scaledToFill().opacity(0.8)
            case .video:
                Image("app-dark").resizable().scaledToFill().opacity(0.8)
                Image(systemName: "pause.fill").font(.system(size: 14)).foregroundStyle(.white).padding(10)
                    .background(.black.opacity(0.5), in: Circle()).overlay(Circle().stroke(.white.opacity(0.1))).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            case .emitter:
                TimelineView(.animation) { context in
                    Canvas { graphics, size in
                        for index in 0..<22 {
                            let phase = context.date.timeIntervalSinceReferenceDate * 0.2 + Double(index) * 0.071
                            let x = CGFloat(Double(index * 83 % 101) / 100) * size.width
                            let y = CGFloat(phase.truncatingRemainder(dividingBy: 1.2) / 1.2) * (size.height + 50) - 25
                            let rect = CGRect(x: x, y: y, width: 7, height: 7)
                            graphics.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                        }
                    }
                }
            case .transform:
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color(white: 0.16)).frame(width: 100, height: 180).overlay { RoundedRectangle(cornerRadius: 24).stroke(Color(white: 0.28), lineWidth: 2) }
                    RoundedRectangle(cornerRadius: 19).fill(.black).frame(width: 92, height: 172)
                    RoundedRectangle(cornerRadius: 6).fill(CATheme.accent).frame(width: 32, height: 32).shadow(color: CATheme.accent.opacity(0.5), radius: 8)
                }.rotation3DEffect(.degrees(animate ? 10 : -8), axis: (x: 0.5, y: 1, z: 0), perspective: 0.5)
            case .replicator:
                ZStack { ForEach(0..<5) { index in RoundedRectangle(cornerRadius: 12).fill(CATheme.accent).frame(width: 64, height: 48).offset(x: CGFloat(index - 2) * 58).rotationEffect(.degrees(Double(index * 10))) } }
            case .liquidGlass:
                Image("app-light").resizable().scaledToFill().overlay { RadialGradient(colors: [.yellow.opacity(0.5), .red.opacity(0.5), .purple.opacity(0.65)], center: .center, startRadius: 5, endRadius: 230) }
                RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial).frame(width: 192, height: 192).shadow(color: .black.opacity(0.5), radius: 25, y: 20)
            default: Image(systemName: kind.symbol).font(.system(size: 76)).foregroundStyle(CATheme.accent)
            }
        }
        .clipped()
        .onAppear { withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { animate = true } }
    }
}
