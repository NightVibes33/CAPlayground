import SwiftUI

struct ProjectsLaunchIntent: Identifiable, Equatable {
    let id = UUID()
    let uploadMode: Bool
    let importURL: String?
    let name: String
    let creator: String

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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@main
struct CAPlaygroundApp: App {
    @State private var store = ProjectStore()
    @State private var auth = AuthStore()
    @State private var drive = DriveStore()
    @State private var projectsLaunchIntent: ProjectsLaunchIntent?
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
        }
    }
}
