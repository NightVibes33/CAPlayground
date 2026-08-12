import SwiftUI

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth
    @State private var submissions: [WallpaperSubmission] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome back\(displayName.isEmpty ? "" : ", \(displayName)")!").font(.system(size: 46, weight: .heavy))
                    Text("Manage your cloud projects and account settings.").font(.title3).foregroundStyle(.secondary)
                }
                submissionCard
                cloudCard
                VStack(alignment: .leading, spacing: 14) {
                    Text("Account Options").font(.title3.bold())
                    Text("Manage your email, username, password, or delete your account.").foregroundStyle(.secondary)
                    NavigationLink("Manage Account") { AccountView() }.buttonStyle(.bordered)
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") { Task { await auth.signOut() } }.buttonStyle(.bordered)
                }.padding(20).caPanel()
            }.frame(maxWidth: 1000).padding(20).padding(.vertical, 24)
        }.navigationTitle("Dashboard").task { submissions = await auth.wallpaperSubmissions(); loading = false }
    }

    private var displayName: String {
        if !auth.username.isEmpty { return auth.username }
        if case .string(let value) = auth.user?.userMetadata?["full_name"] { return value }
        return auth.user?.email ?? ""
    }

    private var submissionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Wallpaper Submissions").font(.title3.bold()); Spacer(); NavigationLink("Submit Wallpaper") { WallpapersView() }.buttonStyle(.borderedProminent).tint(CATheme.accent) }
            if loading { ProgressView() }
            else {
                submissionSection("Awaiting Review", rows: submissions.filter { $0.status == "awaiting_review" }.prefix(3).map { $0 }, empty: "No wallpapers awaiting review")
                submissionSection("Rejected (Last 30 Days)", rows: submissions.filter { $0.status == "rejected" && ($0.submittedAt ?? .distantPast) > Date().addingTimeInterval(-30 * 86_400) }, empty: "No recently rejected wallpapers")
                submissionSection("Published", rows: submissions.filter { $0.status == "approved" }, empty: "No published wallpapers yet")
            }
        }.padding(20).caPanel()
    }

    private func submissionSection(_ title: String, rows: [WallpaperSubmission], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            if rows.isEmpty { Text(empty).font(.caption).foregroundStyle(.secondary) }
            ForEach(rows) { row in
                HStack { VStack(alignment: .leading) { Text(row.name).fontWeight(.medium); Text(row.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Text(row.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption.bold()) }
                    .padding(12).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Cloud Projects", systemImage: "cloud").font(.title3.bold()); Text("BETA").font(.caption.bold()).foregroundStyle(CATheme.accent) }
            Text("Cloud Projects are stored in your Google Drive account and sync across devices.").foregroundStyle(.secondary)
            Link("Manage Cloud Projects on CAPlayground", destination: URL(string: "https://caplayground.vercel.app/dashboard")!).buttonStyle(.bordered)
        }.padding(20).caPanel()
    }
}

struct ResetPasswordView: View {
    @Environment(AuthStore.self) private var auth
    @State private var password = ""
    @State private var confirmation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Reset your password") {
                    SecureField("New password", text: $password)
                    SecureField("Confirm new password", text: $confirmation)
                    if let error = auth.error { Text(error).foregroundStyle(.red) }
                    Button("Update password") { Task { if password == confirmation { _ = await auth.updatePassword(password) } else { auth.error = "Passwords do not match." } } }
                        .disabled(password.isEmpty || confirmation.isEmpty)
                }
            }.navigationTitle("Reset Password").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { auth.requiresPasswordReset = false } } }
        }
    }
}
