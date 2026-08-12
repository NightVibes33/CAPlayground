import SwiftUI

@main
struct CAPlaygroundApp: App {
    @State private var store = ProjectStore()
    @State private var auth = AuthStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(auth)
                .tint(CATheme.accent)
                .preferredColorScheme(
                    appearance == "dark" ? .dark : appearance == "light" ? .light : nil
                )
        }
    }
}
