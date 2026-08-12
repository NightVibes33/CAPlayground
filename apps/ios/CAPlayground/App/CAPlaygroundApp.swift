import SwiftUI

@main
struct CAPlaygroundApp: App {
    @State private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .tint(CATheme.accent)
        }
    }
}
