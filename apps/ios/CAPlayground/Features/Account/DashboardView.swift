import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DriveStore.self) private var drive
    @Environment(ProjectStore.self) private var projectStore
    @State private var submissions: [WallpaperSubmission] = []
    @State private var loading = true
    @State private var showingSubmission = false

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
        }.navigationTitle("Dashboard").task { submissions = await auth.wallpaperSubmissions(); if drive.connected { await drive.refresh() }; loading = false }
            .sheet(isPresented: $showingSubmission) { SubmitWallpaperView { Task { submissions = await auth.wallpaperSubmissions() } } }
    }

    private var displayName: String {
        if !auth.username.isEmpty { return auth.username }
        if case .string(let value) = auth.user?.userMetadata?["full_name"] { return value }
        return auth.user?.email ?? ""
    }

    private var submissionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Wallpaper Submissions").font(.title3.bold()); Spacer(); Button("Submit Wallpaper") { showingSubmission = true }.buttonStyle(.borderedProminent).tint(CATheme.accent) }
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
            if !drive.connected { Button("Connect Google Drive") { drive.connect() }.buttonStyle(.borderedProminent) }
            else {
                Menu("Upload Local Project") { ForEach(projectStore.projects) { project in Button(project.name) { Task { await drive.upload(project) } } } }.buttonStyle(.bordered)
                if drive.files.isEmpty && !drive.isLoading { Text("No cloud projects yet.").font(.caption).foregroundStyle(.secondary) }
                ForEach(drive.files) { file in
                    HStack { VStack(alignment: .leading) { Text(file.name); if let size = file.size { Text("\(size) bytes").font(.caption).foregroundStyle(.secondary) } }; Spacer(); Button("Download") { Task { await drive.download(file, into: projectStore) } }; Button(role: .destructive) { Task { await drive.delete(file) } } label: { Image(systemName: "trash") } }
                        .padding(10).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                Button("Sign Out from Google Drive") { drive.disconnect() }.buttonStyle(.bordered)
            }
            if drive.isLoading { ProgressView() }
            if let message = drive.message { Text(message).font(.caption).foregroundStyle(.green) }
            if let error = drive.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(20).caPanel()
    }
}

struct SubmitWallpaperView: View {
    private enum Step { case form, preview, rules, submitting, success }
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .form
    @State private var name = ""
    @State private var description = ""
    @State private var tendies: Data?
    @State private var video: Data?
    @State private var tendiesName = ""
    @State private var videoName = ""
    @State private var videoExtension = "mp4"
    @State private var pickTendies = false
    @State private var pickVideo = false
    @State private var agreedRules = false
    @State private var agreedQuality = false
    @State private var pullRequestURL: URL?
    let completed: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 20) { content }.padding(20) }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .fileImporter(isPresented: $pickTendies, allowedContentTypes: [.tendies], allowsMultipleSelection: false) { load($0, videoFile: false) }
        .fileImporter(isPresented: $pickVideo, allowedContentTypes: [.movie], allowsMultipleSelection: false) { load($0, videoFile: true) }
    }

    private var title: String { step == .form ? "Submit Wallpaper" : step == .preview ? "Preview Submission" : step == .rules ? "Submission Rules & Guidelines" : step == .submitting ? "Submitting Wallpaper" : "Submission Successful!" }

    @ViewBuilder private var content: some View {
        switch step {
        case .form:
            Text("Share your wallpaper with the CAPlayground community").foregroundStyle(.secondary)
            TextField("Wallpaper Name", text: $name).textFieldStyle(.roundedBorder).onChange(of: name) { _, value in if value.count > 42 { name = String(value.prefix(42)) } }
            Text("\(name.count)/42 characters").font(.caption).foregroundStyle(.secondary)
            TextField("Describe your wallpaper...", text: $description, axis: .vertical).lineLimit(4...4).textFieldStyle(.roundedBorder).onChange(of: description) { _, value in if value.count > 60 { description = String(value.prefix(60)) } }
            Text("\(description.count)/60 characters").font(.caption).foregroundStyle(.secondary)
            Button(tendiesName.isEmpty ? "Choose .tendies file" : tendiesName, systemImage: "square.and.arrow.up") { pickTendies = true }.buttonStyle(.bordered)
            Button(videoName.isEmpty ? "Choose video file" : videoName, systemImage: "square.and.arrow.up") { pickVideo = true }.buttonStyle(.bordered)
            LabeledContent("Author", value: auth.username.isEmpty ? "Anonymous" : auth.username)
            Button("Continue", systemImage: "arrow.right") { step = .preview }.buttonStyle(.borderedProminent).disabled(!valid)
        case .preview:
            Text("This is how your wallpaper will appear in the gallery").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) { Image(systemName: "play.rectangle.fill").font(.system(size: 70)).frame(maxWidth: .infinity).frame(height: 220).background(.secondary.opacity(0.08)); Text(name).font(.title2.bold()); Text("by \(auth.username.isEmpty ? "Anonymous" : auth.username) (submitted on website)").foregroundStyle(.secondary); Text(description) }.padding(16).caPanel()
            HStack { Button("Back") { step = .form }; Spacer(); Button("Looks Good") { step = .rules }.buttonStyle(.borderedProminent) }
        case .rules:
            Text("Please review and agree to the rules before submitting your wallpaper").foregroundStyle(.secondary)
            Text("1. No NSFW or adult-only content.\n\n2. Wallpapers must not consist of a single video layer. They should demonstrate creative use of CAPlayground's features.\n\n3. No political, inappropriate, or offensive content.\n\n4. Ensure you have the rights to all assets used in your submission.")
            Toggle("I confirm that this submission is original and does not contain NSFW, political, or offensive content.", isOn: $agreedRules)
            Toggle("I confirm that this wallpaper is more than just a single video layer.", isOn: $agreedQuality)
            HStack { Button("Back") { step = .preview }; Spacer(); Button("Submit Wallpaper") { submit() }.buttonStyle(.borderedProminent).disabled(!agreedRules || !agreedQuality) }
        case .submitting:
            ProgressView(); Text("Submitting Wallpaper").font(.headline); Text("Uploading files and creating Pull Request...").foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green).frame(maxWidth: .infinity)
            Text("Your wallpaper has been submitted as a Pull Request. Once approved, it will appear in the gallery.").multilineTextAlignment(.center)
            if let pullRequestURL { Link("View Pull Request", destination: pullRequestURL) }
            Button("Done") { completed(); dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
        if let error = auth.error { Text(error).foregroundStyle(.red) }
    }

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !description.trimmingCharacters(in: .whitespaces).isEmpty && tendies != nil && video != nil }
    private func load(_ result: Result<[URL], Error>, videoFile: Bool) {
        guard case .success(let urls) = result, let url = urls.first else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        if videoFile { video = data; videoName = url.lastPathComponent; videoExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension } else { tendies = data; tendiesName = url.lastPathComponent }
    }
    private func submit() { guard let tendies, let video else { return }; step = .submitting; Task { if let url = await auth.submitWallpaper(name: name, description: description, tendies: tendies, video: video, videoExtension: videoExtension) { pullRequestURL = url; step = .success } else { step = .preview } } }
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
