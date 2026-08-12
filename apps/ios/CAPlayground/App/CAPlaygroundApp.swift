import SwiftUI

@main
struct CAPlaygroundApp: App {
    @State private var store = ProjectStore()
    @State private var auth = AuthStore()
    @State private var drive = DriveStore()
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
                .onOpenURL { url in Task { await auth.handleIncomingURL(url) } }
                .sheet(isPresented: resetBinding) { ResetPasswordView() }
        }
    }
}
