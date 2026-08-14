import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var githubStars: Int?
    @State private var commitCount: Int?
    @State private var wallpaperResponse: WallpapersResponse?
    @State private var downloadStats: [String: Int] = [:]
    @State private var selectedExample: WallpaperItem?
    @State private var importedProject: CAProjectDocument?
    @State private var exportDocument: TendiesExportDocument?
    @State private var exportFilename = "wallpaper.tendies"
    @State private var showingFileExporter = false
    @State private var homeError: String?
    @State private var copiedWallpaperID: String?
    @State private var navScrolled = false

    private let layers: [(kind: LayerKind, description: String, exampleID: String)] = [
        (.basic, "A fundamental solid color or shape layer (CALayer) for backgrounds or simple elements.", "4983462"),
        (.gradient, "Creates smooth color gradients with configurable colors, directions, and stops.", "9612103"),
        (.image, "Renders static images or photos, supporting scaling, positioning, and masking.", "9372814"),
        (.video, "Plays embedded video content as a looping animated element.", "9232798"),
        (.emitter, "Generates particle effects (CAEmitterLayer) like snow, fire, or confetti with customizable particles.", "1633426"),
        (.transform, "Controls 3D transformations, perspective, and depth for immersive, realistic layer interactions.", "9531199"),
        (.replicator, "Duplicates child layers in patterns (e.g., grids, circles) for efficient repetitive designs.", "5733952"),
        (.liquidGlass, "A special effect layer simulating refractive, fluid glass distortion", "7670567")
    ]

    private var mostDownloaded: (item: WallpaperItem, downloads: Int)? {
        guard let wallpaperResponse,
              let top = downloadStats.max(by: { $0.value < $1.value }),
              let item = wallpaperResponse.wallpapers.first(where: { $0.id == top.key }) else { return nil }
        return (item, top.value)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HomeScrollOffsetKey.self,
                                value: proxy.frame(in: .named("home-scroll")).minY
                            )
                        }
                        .frame(height: 0)

                        hero
                        layersSection
                        growingSection
                        if let mostDownloaded { mostDownloadedSection(mostDownloaded) }
                        CAWebsiteFooter()
                    }
                }
                .coordinateSpace(name: "home-scroll")
                .onPreferenceChange(HomeScrollOffsetKey.self) { navScrolled = $0 < -50 }
                .background(CATheme.background(scheme).ignoresSafeArea())

                CAWebsiteNavigation(isScrolled: navScrolled)
                    .frame(maxWidth: navScrolled ? 1024 : .infinity)
                    .padding(.horizontal, navScrolled ? (horizontalSizeClass == .compact ? 16 : 24) : 0)
                    .padding(.top, navScrolled ? 8 : 0)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedExample) { item in exampleDetail(item) }
            .fullScreenCover(item: $importedProject) { project in EditorView(initialProject: project) }
            .fileExporter(
                isPresented: $showingFileExporter,
                document: exportDocument,
                contentType: .tendies,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result { homeError = error.localizedDescription }
                exportDocument = nil
            }
            .alert("Wallpaper action failed", isPresented: Binding(
                get: { homeError != nil },
                set: { if !$0 { homeError = nil } }
            )) {
                Button("OK") { homeError = nil }
            } message: {
                Text(homeError ?? "Unknown error")
            }
            .task { await loadHomeData() }
        }
    }

    private var hero: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Image(scheme == .dark ? "app-dark" : "app-light")
                    .resizable()
                    .scaledToFit()
                    .opacity(geometry.size.width < 700 ? 0.5 : 1)
                    .frame(maxWidth: 1152)
                    .offset(y: geometry.size.width < 700 ? -190 : -40)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 32) { heroCopy; githubButton }
                    VStack(alignment: .leading, spacing: 24) { heroCopy; githubButton }
                }
                .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 24)
                .padding(.bottom, horizontalSizeClass == .compact ? 40 : 64)
                .frame(maxWidth: 1400)
            }
            .frame(maxWidth: .infinity)
        }
        .containerRelativeFrame(.vertical)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink(destination: ProjectsView()) {
                Label("Blending Modes and Filters are out!", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CATheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(CATheme.accent.opacity(0.1), in: Capsule())
                    .overlay(Capsule().stroke(CATheme.accent.opacity(0.2)))
            }

            (Text("The Open Source\n") + Text("CA Wallpaper Editor.").foregroundStyle(CATheme.accent))
                .font(.system(size: horizontalSizeClass == .compact ? 48 : 72, weight: .bold))
                .tracking(-1.5)

            Text("Create beautiful animated wallpapers for iOS and iPadOS on any desktop computer with CAPlayground.")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 600, alignment: .leading)

            NavigationLink(destination: ProjectsView()) {
                Label("Get Started", systemImage: "paperplane.fill")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 200, minHeight: 56)
            }
            .buttonStyle(CAWebButtonStyle(variant: .accent, height: 56))
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private var githubButton: some View {
        Link(destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(githubStars.map { "View GitHub \(formattedNumber($0))" } ?? "View GitHub")
                if githubStars != nil {
                    Image(systemName: "star.fill").font(.caption).opacity(0.5)
                }
            }
            .font(.body.weight(.medium))
            .frame(minWidth: 200, minHeight: 48)
        }
        .buttonStyle(CAWebButtonStyle(variant: .outline, height: 48))
    }

    private var layersSection: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                Text("Layers of Possibility.")
                    .font(.system(size: horizontalSizeClass == .compact ? 40 : 60, weight: .bold))
                Text("Build complex wallpaper states by combining different layer types, each with their own unique properties and animations.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                ForEach(layers.indices, id: \.self) { index in
                    let entry = layers[index]
                    Button {
                        selectedExample = wallpaperResponse?.wallpapers.first(where: { $0.id == entry.exampleID })
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            LayerPreview(kind: entry.kind)
                            LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.kind == .basic ? "Basic Layer" : "\(entry.kind.title) Layer")
                                    .font(.system(size: 22, weight: .bold))
                                Text(entry.description)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(white: 0.82))
                                    .lineLimit(horizontalSizeClass == .compact ? 2 : nil)
                            }
                            .padding(24)
                        }
                        .foregroundStyle(.white)
                        .frame(height: horizontalSizeClass == .compact ? 300 : 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(white: scheme == .dark ? 0.12 : 0.82), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(wallpaperResponse == nil)
                    .accessibilityHint("Opens the example wallpaper used by the website")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 96)
        .frame(maxWidth: 1400)
    }

    private var growingSection: some View {
        VStack(spacing: 64) {
            Text("CAPlayground is growing!")
                .font(.system(size: horizontalSizeClass == .compact ? 40 : 60, weight: .bold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 72) {
                    statistic("100k+", "users in the first 4 months")
                    statistic("1.5k+", "Discord server members")
                    statistic(commitCount.map(String.init) ?? "500+", "GitHub Commits")
                }
                VStack(spacing: 48) {
                    statistic("100k+", "users in the first 4 months")
                    statistic("1.5k+", "Discord server members")
                    statistic(commitCount.map(String.init) ?? "500+", "GitHub Commits")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 112)
        .frame(maxWidth: .infinity)
    }

    private func mostDownloadedSection(_ featured: (item: WallpaperItem, downloads: Int)) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 64) {
                mostDownloadedCard(featured)
                mostDownloadedCopy(featured)
            }
            VStack(spacing: 40) {
                mostDownloadedCard(featured)
                mostDownloadedCopy(featured)
            }
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 24)
        .padding(.vertical, horizontalSizeClass == .compact ? 64 : 96)
        .frame(maxWidth: 1152)
        .frame(maxWidth: .infinity)
        .background(CATheme.muted(scheme).opacity(0.30))
    }

    private func mostDownloadedCard(_ featured: (item: WallpaperItem, downloads: Int)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            wallpaperPreview(featured.item)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CATheme.border(scheme)))
            Text(featured.item.name).font(.headline).lineLimit(1)
            Text("by \(featured.item.creator) (submitted on \(featured.item.from))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if featured.downloads > 0 {
                Label("\(featured.downloads) \(featured.downloads == 1 ? "Download" : "Downloads")", systemImage: "arrow.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(featured.item.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: 520)
        .background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme), lineWidth: 8))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }

    private func mostDownloadedCopy(_ featured: (item: WallpaperItem, downloads: Int)) -> some View {
        VStack(alignment: horizontalSizeClass == .compact ? .center : .leading, spacing: 16) {
            Text("Explore the most downloaded wallpaper")
                .font(.system(size: horizontalSizeClass == .compact ? 30 : 40, weight: .bold))
                .multilineTextAlignment(horizontalSizeClass == .compact ? .center : .leading)
            Text("See what the community loves most, then dive into the full gallery to discover more animated wallpapers for your devices.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(horizontalSizeClass == .compact ? .center : .leading)
                .frame(maxWidth: 560)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { mostDownloadedActions(featured.item) }
                VStack(spacing: 12) { mostDownloadedActions(featured.item) }
            }
        }
        .frame(maxWidth: 560, alignment: horizontalSizeClass == .compact ? .center : .leading)
    }

    @ViewBuilder private func mostDownloadedActions(_ item: WallpaperItem) -> some View {
        NavigationLink("View this wallpaper") {
            WallpapersView(launchIntent: WallpapersLaunchIntent(wallpaperID: item.id))
        }
        .buttonStyle(CAWebButtonStyle(variant: .accent))
        NavigationLink("View wallpaper gallery") { WallpapersView() }
            .buttonStyle(CAWebButtonStyle(variant: .outline))
    }

    private func statistic(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.system(size: 76, weight: .black)).foregroundStyle(CATheme.accent)
            Text(label).font(.title3.weight(.medium)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 250)
        }
    }

    private func exampleDetail(_ item: WallpaperItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    wallpaperPreview(item)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme)))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        Text(item.description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        Button {
                            Task { await downloadTendies(item) }
                        } label: {
                            Label("Download .tendies", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CAWebButtonStyle(variant: .accent))

                        Button {
                            Task { await openInEditor(item) }
                        } label: {
                            Label("Open in Editor", systemImage: "pencil").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CAWebButtonStyle(variant: .outline))

                        Link(destination: URL(string: "https://www.youtube.com/watch?v=nSBQIwAaAEc")!) {
                            Label("Watch Tutorial", systemImage: "play.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CAWebButtonStyle(variant: .outline))

                        Button {
                            UIPasteboard.general.string = "https://caplayground.vercel.app/wallpapers?id=\(item.id)"
                            copiedWallpaperID = item.id
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                if copiedWallpaperID == item.id { copiedWallpaperID = nil }
                            }
                        } label: {
                            Label(copiedWallpaperID == item.id ? "Copied" : "Copy Link", systemImage: copiedWallpaperID == item.id ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CAWebButtonStyle(variant: .outline))
                    }
                }
                .padding(24)
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text("by \(item.creator) (submitted on \(item.from))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private func wallpaperPreview(_ item: WallpaperItem) -> some View {
        if let url = previewURL(item), isVideo(url) {
            WallpaperVideoPreview(url: url)
        } else {
            AsyncImage(url: previewURL(item)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
    }

    @MainActor private func loadHomeData() async {
        await loadGitHubStats()
        await loadWallpaperData()
        await loadDownloadStats()
    }

    @MainActor private func loadGitHubStats() async {
        if let repoURL = URL(string: "https://api.github.com/repos/CAPlayground/CAPlayground") {
            do {
                let (data, response) = try await URLSession.shared.data(from: repoURL)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    githubStars = try JSONDecoder().decode(GitHubRepoStats.self, from: data).stargazersCount
                }
            } catch { }
        }

        guard let commitsURL = URL(string: "https://api.github.com/repos/CAPlayground/CAPlayground/commits?per_page=1") else { return }
        do {
            let (_, response) = try await URLSession.shared.data(from: commitsURL)
            if let link = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Link"),
               let last = link.split(separator: ",").first(where: { $0.contains("rel=\"last\"") }),
               let pageRange = last.range(of: "page=") {
                let tail = last[pageRange.upperBound...]
                let digits = tail.prefix(where: { $0.isNumber })
                commitCount = Int(digits)
            }
        } catch { }
    }

    @MainActor private func loadWallpaperData() async {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WallpaperGallery", isDirectory: true)
        let cached = cacheDirectory.appendingPathComponent("wallpapers.json")
        guard let url = URL(string: "https://raw.githubusercontent.com/CAPlayground/wallpapers/refs/heads/main/wallpapers.json") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            wallpaperResponse = try JSONDecoder().decode(WallpapersResponse.self, from: data)
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cached, options: .atomic)
        } catch {
            if let data = try? Data(contentsOf: cached) {
                wallpaperResponse = try? JSONDecoder().decode(WallpapersResponse.self, from: data)
            }
        }
    }

    @MainActor private func loadDownloadStats() async {
        guard let url = URL(string: "https://caplayground.vercel.app/api/wallpapers/stats") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let stats = try JSONDecoder().decode([WallpaperDownloadStat].self, from: data)
            downloadStats = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0.downloads) })
        } catch { }
    }

    @MainActor private func downloadTendies(_ item: WallpaperItem) async {
        guard let url = fileURL(item) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            exportDocument = TendiesExportDocument(data: data)
            exportFilename = "\(safeFilename(item.name)).tendies"
            showingFileExporter = true
            await trackDownload(item)
        } catch {
            homeError = error.localizedDescription
        }
    }

    @MainActor private func openInEditor(_ item: WallpaperItem) async {
        guard let url = fileURL(item) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let project = try CAArchiveImporter.importProject(data: data, suggestedName: item.name)
            store.update(project)
            selectedExample = nil
            importedProject = project
            await trackDownload(item)
        } catch {
            homeError = error.localizedDescription
        }
    }

    @MainActor private func trackDownload(_ item: WallpaperItem) async {
        guard let url = URL(string: "https://caplayground.vercel.app/api/wallpapers/download") else { return }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["id": item.id])
            _ = try await URLSession.shared.data(for: request)
            downloadStats[item.id, default: 0] += 1
        } catch { }
    }

    private func previewURL(_ item: WallpaperItem) -> URL? {
        URL(string: item.preview, relativeTo: wallpaperResponse?.baseURL)?.absoluteURL
    }

    private func fileURL(_ item: WallpaperItem) -> URL? {
        URL(string: item.file, relativeTo: wallpaperResponse?.baseURL)?.absoluteURL
    }

    private func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased()) || url.path.lowercased().contains("/video/")
    }

    private func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: #"[\\/:*?\"<>|]"#, with: "_", options: .regularExpression)
    }

    private func formattedNumber(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

private struct GitHubRepoStats: Decodable {
    let stargazersCount: Int
    enum CodingKeys: String, CodingKey { case stargazersCount = "stargazers_count" }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct LayerPreview: View {
    let kind: LayerKind
    @State private var animate = false

    var body: some View {
        ZStack {
            Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255)
            switch kind {
            case .basic:
                Circle().fill(Color(red: 82 / 255, green: 82 / 255, blue: 1)).frame(width: 96, height: 96).offset(x: 70, y: -70).shadow(color: Color.blue.opacity(0.4), radius: 20)
                RoundedRectangle(cornerRadius: 16).fill(Color(red: 1, green: 82 / 255, blue: 82 / 255)).frame(width: 128, height: 128).rotationEffect(.degrees(animate ? 45 : 12)).shadow(color: Color.red.opacity(0.4), radius: 20)
            case .gradient:
                LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing).overlay { RadialGradient(colors: [.white.opacity(0.4), .clear], center: UnitPoint(x: 0.5, y: 1.2), startRadius: 0, endRadius: 260) }
            case .image:
                Image("app-dark").resizable().scaledToFill().opacity(0.8)
            case .video:
                Image("app-dark").resizable().scaledToFill().opacity(0.8)
                Image(systemName: "pause.fill").font(.system(size: 14)).foregroundStyle(.white).padding(10).background(.black.opacity(0.5), in: Circle()).overlay(Circle().stroke(.white.opacity(0.1))).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            case .emitter:
                TimelineView(.animation) { context in
                    Canvas { graphics, size in
                        for index in 0..<22 {
                            let phase = context.date.timeIntervalSinceReferenceDate * 0.2 + Double(index) * 0.071
                            let x = CGFloat(Double(index * 83 % 101) / 100) * size.width
                            let y = CGFloat(phase.truncatingRemainder(dividingBy: 1.2) / 1.2) * (size.height + 50) - 25
                            graphics.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: 7, height: 7)), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
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
            default:
                Image(systemName: kind.symbol).font(.system(size: 76)).foregroundStyle(CATheme.accent)
            }
        }
        .clipped()
        .onAppear { withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { animate = true } }
    }
}
