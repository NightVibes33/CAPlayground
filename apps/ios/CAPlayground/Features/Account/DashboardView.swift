import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct DashboardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DriveStore.self) private var drive
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var submissions: [WallpaperSubmission] = []
    @State private var loading = true
    @State private var showingSubmission = false
    @State private var showingDeleteAll = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Welcome back\(displayName.isEmpty ? "" : ", \(displayName)")!")
                        .font(.system(size: sizeClass == .compact ? 40 : 60, weight: .heavy))
                        .tracking(-1.2)
                    Text("Manage your cloud projects and account settings.")
                        .font(.title3).foregroundStyle(.secondary).padding(.top, 20)
                    VStack(spacing: 24) { submissionCard; cloudCard; accountOptions }.padding(.top, 32)
                }
                .frame(maxWidth: 768, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 80).padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
            .background(CATheme.background(scheme).ignoresSafeArea())
            Button { dismiss() } label: { Label("Back", systemImage: "arrow.left") }
                .buttonStyle(CAWebButtonStyle(variant: .ghost, height: 32)).padding(.leading, 12).padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            submissions = await auth.wallpaperSubmissions()
            loading = false
        }
        .sheet(isPresented: $showingSubmission) {
            SubmitWallpaperView { Task { submissions = await auth.wallpaperSubmissions() } }
        }
        .confirmationDialog(
            "Delete All Cloud Projects",
            isPresented: $showingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { _ = await drive.deleteAll() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the entire CAPlayground folder and all cloud projects from Google Drive. Projects stored on this device will not be affected. This action cannot be undone.")
        }
    }

    private var displayName: String {
        if !auth.username.isEmpty { return auth.username }
        if case .string(let value) = auth.user?.userMetadata?["full_name"] { return value }
        return auth.user?.email ?? ""
    }

    private var submissionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Wallpaper Submissions").font(.title3.bold()); Spacer(); submitButton }
                VStack(alignment: .leading, spacing: 12) { Text("Wallpaper Submissions").font(.title3.bold()); submitButton }
            }
            if loading {
                Text("Loading your submissions...").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
            } else {
                let awaiting = submissions.filter { $0.status == "awaiting_review" }
                let rejected = submissions.filter { $0.status == "rejected" && ($0.submittedAt ?? .distantPast) > Date().addingTimeInterval(-30 * 86_400) }
                let published = submissions.filter { $0.status == "approved" }
                submissionSection("Awaiting Review", rows: awaiting, empty: "No wallpapers awaiting review", detail: "You can have up to five wallpapers awaiting review at a time.", countText: "\(awaiting.count)/5 slots used")
                if !rejected.isEmpty { submissionSection("Rejected (Last 30 Days)", rows: rejected, empty: "", detail: "Submissions that were not accepted. These will disappear after 30 days.", countText: "\(rejected.count) rejected") }
                submissionSection("Published", rows: published, empty: "No published wallpapers yet", detail: "Wallpapers that have been approved and are live in the gallery.", countText: published.isEmpty ? "None yet" : "\(published.count) published")
            }
        }
        .padding(24).background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1) }
    }

    private var submitButton: some View {
        Button { showingSubmission = true } label: { Label("Submit Wallpaper", systemImage: "plus") }.buttonStyle(CAWebButtonStyle(variant: .accent))
    }

    private func submissionSection(_ title: String, rows: [WallpaperSubmission], empty: String, detail: String, countText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.subheadline.bold()); Spacer(); Text(countText).font(.caption).foregroundStyle(.secondary) }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty {
                VStack(spacing: 4) {
                    Text(empty).font(.subheadline).foregroundStyle(.secondary)
                    if title == "Awaiting Review" { Text("Click \"Submit Wallpaper\" to get started").font(.caption).foregroundStyle(.secondary) }
                    if title == "Published" { Text("They'll appear here once approved").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5])))
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) { Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1); Text(row.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Spacer()
                        Text(statusTitle(row.status)).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4).background(statusColor(row.status).opacity(0.12), in: Capsule()).foregroundStyle(statusColor(row.status))
                    }
                    .padding(12).background(statusColor(row.status).opacity(0.05), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(statusColor(row.status).opacity(0.2)))
                }
            }
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Cloud Projects").font(.title3.bold())
                Text("BETA").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3).foregroundStyle(.blue).background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue.opacity(0.2)))
            }
            Text("Sync and manage your projects in the cloud with Google Drive.").font(.subheadline).foregroundStyle(.secondary)

            if drive.connected {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.connected.to.line.below.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in to Google Drive").font(.subheadline.weight(.medium))
                        Text("Your projects can be synced to the cloud").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.22)))

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        NavigationLink("Manage Projects") { ProjectsView() }
                            .buttonStyle(CAWebButtonStyle(variant: .outline))
                            .frame(maxWidth: .infinity)
                        Button("Delete All", role: .destructive) { showingDeleteAll = true }
                            .buttonStyle(CAWebButtonStyle(variant: .outline))
                            .foregroundStyle(CATheme.destructive)
                            .disabled(drive.isLoading)
                    }
                    Button {
                        drive.disconnect()
                    } label: {
                        Label("Sign out from Google Drive", systemImage: "cloud")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button { drive.connect() } label: {
                        Label("Sign in to Google Drive", systemImage: "externaldrive.connected.to.line.below")
                    }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                    .disabled(drive.isLoading)
                    Text("Once signed in, you can sync projects directly from the projects page.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if drive.isLoading { ProgressView() }
            if let message = drive.message { Text(message).font(.caption).foregroundStyle(.green) }
            if let error = drive.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(24).background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1) }
    }

    private var accountOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account Options").font(.title3.bold())
            Text("Manage your email, username, password, or delete your account.").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                NavigationLink("Manage Account") { AccountView() }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                Button { Task { await auth.signOut(); dismiss() } } label: {
                    Text(loading ? "Signing out..." : "Sign Out")
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))
                .disabled(loading)
            }
        }
        .padding(24).background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1) }
    }

    private func statusTitle(_ status: String) -> String { status == "awaiting_review" ? "Awaiting Review" : status == "approved" ? "Published" : "Rejected" }
    private func statusColor(_ status: String) -> Color { status == "awaiting_review" ? .orange : status == "approved" ? .green : .red }
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
                    Button("Update password") { Task { if password == confirmation { _ = await auth.updatePassword(password) } else { auth.error = "Passwords do not match." } } }.disabled(password.isEmpty || confirmation.isEmpty)
                }
            }.navigationTitle("Reset Password").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { auth.requiresPasswordReset = false } } }
        }
    }
}
