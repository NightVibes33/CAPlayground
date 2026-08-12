import AVKit
import Foundation
import SafariServices
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct WallpapersResponse: Codable, Sendable {
    let baseURL: URL
    let wallpapers: [WallpaperItem]

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case wallpapers
    }
}

private struct WallpaperItem: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let creator: String
    let description: String
    let file: String
    let preview: String
    let date: Double?
    let from: String

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? values.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try values.decode(Int.self, forKey: .id))
        }
        name = try values.decode(String.self, forKey: .name)
        creator = try values.decode(String.self, forKey: .creator)
        description = try values.decode(String.self, forKey: .description)
        file = try values.decode(String.self, forKey: .file)
        preview = try values.decode(String.self, forKey: .preview)
        date = try values.decodeIfPresent(Double.self, forKey: .date)
        from = try values.decode(String.self, forKey: .from)
    }
}

private struct WallpaperDownloadStat: Codable, Sendable {
    let id: String
    let downloads: Int

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? values.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try values.decode(Int.self, forKey: .id))
        }
        downloads = try values.decode(Int.self, forKey: .downloads)
    }
}

private struct TendiesExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tendies] }
    static var writableContentTypes: [UTType] { [.tendies] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SafariDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct WallpapersView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private enum SortOrder: String, CaseIterable {
        case oldest = "Oldest to Newest"
        case newest = "Newest to Oldest"
        case downloads = "Most Downloads"
        case leastDownloads = "Least Downloads"
    }

    @State private var response: WallpapersResponse?
    @State private var query = ""
    @State private var sortOrder: SortOrder = .downloads
    @State private var downloadStats: [String: Int] = [:]
    @State private var selected: WallpaperItem?
    @State private var isLoading = true
    @State private var failed = false
    @State private var importingID: String?
    @State private var downloadingID: String?
    @State private var importedProject: CAProjectDocument?
    @State private var importError: String?
    @State private var showingSubmission = false
    @State private var exportDocument: TendiesExportDocument?
    @State private var exportFilename = "wallpaper.tendies"
    @State private var showingFileExporter = false
    @State private var copiedWallpaperID: String?
    @State private var safariDestination: SafariDestination?

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WallpaperGallery", isDirectory: true)
    }

    private var wallpapers: [WallpaperItem] {
        guard let response else { return [] }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = response.wallpapers.filter { item in
            term.isEmpty || item.name.lowercased().contains(term) || item.creator.lowercased().contains(term) || item.description.lowercased().contains(term)
        }
        switch sortOrder {
        case .newest:
            return filtered.sorted { ($0.date ?? 0) > ($1.date ?? 0) }
        case .oldest:
            return filtered.sorted { ($0.date ?? 0) < ($1.date ?? 0) }
        case .downloads, .leastDownloads:
            return filtered.sorted {
                let left = downloadStats[$0.id] ?? 0
                let right = downloadStats[$1.id] ?? 0
                return sortOrder == .downloads ? left > right : left < right
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 12) {
                        Text("Wallpaper Gallery")
                            .font(.system(size: 50, weight: .bold))
                        Text("Browse wallpapers made by the CAPlayground community.")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    controls

                    if isLoading {
                        ProgressView("Loading...").frame(minHeight: 260)
                    } else if failed || response == nil {
                        Text("Unable to load wallpapers right now. Please try again later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 260)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 28)], spacing: 28) {
                            ForEach(wallpapers) { item in
                                wallpaperCard(item)
                                    .onTapGesture { selected = item }
                            }
                        }
                    }
                }
                .frame(maxWidth: 1120)
                .padding(.horizontal, 24)
                .padding(.top, 96).padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
            CAWebsiteNavigation().padding(.horizontal, 16).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selected) { item in detail(item) }
        .fullScreenCover(item: $importedProject) { project in
            EditorView(initialProject: project)
        }
        .sheet(isPresented: $showingSubmission) {
            SubmitWallpaperView { Task { await loadWallpapers() } }
        }
        .sheet(item: $safariDestination) { destination in
            SafariView(url: destination.url).ignoresSafeArea()
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .tendies,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result { importError = error.localizedDescription }
            exportDocument = nil
        }
        .alert("Failed to open wallpaper", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "Unknown error")
        }
        .task {
            await loadWallpapers()
            await loadDownloadStats()
        }
        .onOpenURL { url in
            handleGalleryDeepLink(url)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button { showingSubmission = true } label: {
                Label("Submit Wallpaper", systemImage: "square.and.arrow.up")
            }.buttonStyle(CAWebButtonStyle(variant: .accent))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { searchField; sortPicker }
                VStack(spacing: 12) { searchField; sortPicker }
            }
        }
        .frame(maxWidth: 660)
    }

    private var searchField: some View {
        TextField("Search wallpapers by name, creator, or description...", text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 460)
    }

    private var sortPicker: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
                } label: {
                    Label(order.rawValue, systemImage: sortOrder == order ? "checkmark" : "")
                }
            }
        } label: {
            Text(sortOrder.rawValue).frame(minWidth: 150)
        }
        .buttonStyle(CAWebButtonStyle(variant: .outline))
    }

    private func wallpaperCard(_ item: WallpaperItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            preview(item)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))

            Text(item.name).font(.body.weight(.medium)).lineLimit(1)
            Text("by \(item.creator) (submitted on \(item.from))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let downloads = downloadStats[item.id], downloads > 0 {
                Label("\(downloads) \(downloads == 1 ? "Download" : "Downloads")", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            actions(item)
        }
        .padding(16)
        .caPanel()
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme), lineWidth: 1) }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func preview(_ item: WallpaperItem) -> some View {
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

    private func actions(_ item: WallpaperItem) -> some View {
        VStack(spacing: 8) {
            if let fileURL = fileURL(item) {
                Button {
                    Task { await downloadTendies(item, fileURL: fileURL) }
                } label: {
                    Label(downloadingID == item.id ? "Downloading..." : "Download .tendies", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CAWebButtonStyle(variant: .accent))
                .disabled(downloadingID != nil)

                Button {
                    Task {
                        await trackDownload(item)
                        let encoded = fileURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "pocketposter://download?url=\(encoded)") { openURL(url) }
                    }
                } label: {
                    Label("Open in Pocket Poster", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CAWebButtonStyle(variant: .accent))

                Button {
                    Task { await openInEditor(item, fileURL: fileURL) }
                } label: {
                    Label(importingID == item.id ? "Opening..." : "Open in Editor", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))
                .disabled(importingID != nil)
            }

            Button {
                safariDestination = SafariDestination(url: URL(string: "https://www.youtube.com/watch?v=nSBQIwAaAEc")!)
            } label: {
                Label("Watch Tutorial", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CAWebButtonStyle(variant: .outline))
        }
    }

    private func detail(_ item: WallpaperItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview(item)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        Text(item.description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let downloads = downloadStats[item.id], downloads > 0 {
                        Label("\(downloads) \(downloads == 1 ? "Download" : "Downloads")", systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    actions(item)
                    Button {
                        UIPasteboard.general.url = URL(string: "https://caplayground.vercel.app/wallpapers?id=\(item.id)")!
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
    }

    private func loadWallpapers() async {
        guard let url = URL(string: "https://raw.githubusercontent.com/CAPlayground/wallpapers/refs/heads/main/wallpapers.json") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            self.response = try JSONDecoder().decode(WallpapersResponse.self, from: data)
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cacheDirectory.appendingPathComponent("wallpapers.json"), options: .atomic)
            failed = false
        } catch {
            if let data = try? Data(contentsOf: cacheDirectory.appendingPathComponent("wallpapers.json")), let cached = try? JSONDecoder().decode(WallpapersResponse.self, from: data) {
                response = cached
                failed = false
            } else {
                failed = true
            }
        }
        isLoading = false
    }

    private func loadDownloadStats() async {
        guard let url = URL(string: "https://caplayground.vercel.app/api/wallpapers/stats") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let stats = try JSONDecoder().decode([WallpaperDownloadStat].self, from: data)
            downloadStats = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0.downloads) })
        } catch { }
    }

    private func trackDownload(_ item: WallpaperItem) async {
        guard let url = URL(string: "https://caplayground.vercel.app/api/wallpapers/download") else { return }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["wallpaperId": item.id, "name": item.name])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                await loadDownloadStats()
            }
        } catch { }
    }

    private func downloadTendies(_ item: WallpaperItem, fileURL: URL) async {
        downloadingID = item.id
        defer { downloadingID = nil }
        await trackDownload(item)
        do {
            let data = try await tendiesData(item, fileURL: fileURL)
            exportDocument = TendiesExportDocument(data: data)
            exportFilename = safeFilename(item.name) + ".tendies"
            showingFileExporter = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func openInEditor(_ item: WallpaperItem, fileURL: URL) async {
        importingID = item.id
        defer { importingID = nil }
        await trackDownload(item)
        do {
            let data = try await tendiesData(item, fileURL: fileURL)
            let project = try CAArchiveImporter.importProject(data: data, suggestedName: item.name)
            store.update(project)
            selected = nil
            importedProject = project
        } catch {
            importError = error.localizedDescription
        }
    }

    private func tendiesData(_ item: WallpaperItem, fileURL: URL) async throws -> Data {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        do {
            let (data, response) = try await URLSession.shared.data(from: fileURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try? data.write(to: cachedTendiesURL(item), options: .atomic)
            return data
        } catch {
            if let cached = try? Data(contentsOf: cachedTendiesURL(item)) { return cached }
            throw error
        }
    }

    private func cachedTendiesURL(_ item: WallpaperItem) -> URL {
        cacheDirectory.appendingPathComponent("\(item.id).tendies")
    }

    private func previewURL(_ item: WallpaperItem) -> URL? {
        URL(string: item.preview, relativeTo: response?.baseURL)?.absoluteURL
    }

    private func fileURL(_ item: WallpaperItem) -> URL? {
        URL(string: item.file, relativeTo: response?.baseURL)?.absoluteURL
    }

    private func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased()) || url.path.lowercased().contains("/video/")
    }

    private func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: #"[\\/:*?\"<>|]"#, with: "_", options: .regularExpression)
    }

    private func handleGalleryDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "caplayground", url.host == "wallpapers" else { return }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let id = values.first(where: { $0.name == "id" })?.value
        let action = values.first(where: { $0.name == "action" })?.value
        if let q = values.first(where: { $0.name == "q" })?.value { query = q }
        guard let id, let item = response?.wallpapers.first(where: { $0.id == id }) else { return }
        if action == "edit", let fileURL = fileURL(item) {
            Task { await openInEditor(item, fileURL: fileURL) }
        } else {
            selected = item
        }
    }
}

private struct WallpaperVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .disabled(true)
            .onAppear {
                player.isMuted = true
                player.play()
            }
            .onDisappear { player.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
                player.seek(to: .zero)
                player.play()
            }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}
