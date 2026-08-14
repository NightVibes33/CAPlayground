import SwiftUI

struct ProjectsLaunchIntent: Identifiable, Equatable {
    let id = UUID()
    let uploadMode: Bool
    let importURL: String?
    let name: String
    let creator: String

    init(uploadMode: Bool = false, importURL: String? = nil, name: String = "", creator: String = "") {
        self.uploadMode = uploadMode
        self.importURL = importURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.creator = creator.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "caplayground" else { return nil }
        let host = url.host?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "projects" || path == "projects" else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value
        }

        uploadMode = value("mode")?.lowercased() == "upload"
        importURL = value("importUrl")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        name = value("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        creator = value("creator")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct WallpapersLaunchIntent: Identifiable, Equatable {
    let id = UUID()
    let wallpaperID: String?
    let action: String?
    let query: String

    init(wallpaperID: String? = nil, action: String? = nil, query: String = "") {
        self.wallpaperID = wallpaperID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.action = action?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "caplayground" else { return nil }
        let host = url.host?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "wallpapers" || path == "wallpapers" else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value
        }

        wallpaperID = value("id")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        action = value("action")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        query = value("q")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@main
struct CAPlaygroundApp: App {
    @State private var store = ProjectStore()
    @State private var auth = AuthStore()
    @State private var drive = DriveStore()
    @State private var projectsLaunchIntent: ProjectsLaunchIntent?
    @State private var wallpapersLaunchIntent: WallpapersLaunchIntent?
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            let resetBinding = Binding(get: { auth.requiresPasswordReset }, set: { auth.requiresPasswordReset = $0 })
            HomeView()
                .environment(store)
                .environment(auth)
                .environment(drive)
                .tint(CATheme.accent)
                .preferredColorScheme(
                    appearance == "dark" ? .dark : appearance == "light" ? .light : nil
                )
                .onOpenURL { url in
                    if let intent = ProjectsLaunchIntent(url: url) {
                        projectsLaunchIntent = intent
                    } else if let intent = WallpapersLaunchIntent(url: url) {
                        wallpapersLaunchIntent = intent
                    } else {
                        Task { await auth.handleIncomingURL(url) }
                    }
                }
                .sheet(isPresented: resetBinding) { WebsiteResetPasswordView() }
                .fullScreenCover(item: $projectsLaunchIntent) { intent in
                    ProjectsView(launchIntent: intent)
                        .environment(store)
                        .environment(auth)
                        .environment(drive)
                }
                .fullScreenCover(item: $wallpapersLaunchIntent) { intent in
                    WallpapersView(launchIntent: intent)
                        .environment(store)
                        .environment(auth)
                        .environment(drive)
                }
        }
    }
}
