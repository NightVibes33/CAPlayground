import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

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
    @State private var deleting = false
    @State private var isSyncing = false
    @State private var messageDialogOpen = false
    @State private var messageDialogTitle = ""
    @State private var messageDialogContent = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Welcome back\(displayName.isEmpty ? "" : ", \(displayName)")!")
                        .font(.system(size: sizeClass == .compact ? 40 : 60, weight: .heavy))
                        .tracking(-1.2)
                    Text("Manage your cloud projects and account settings.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                    VStack(spacing: 24) {
                        submissionCard
                        cloudCard
                        accountOptions
                    }
                    .padding(.top, 32)
                }
                .frame(maxWidth: 768, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 80)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
            .background(CATheme.background(scheme).ignoresSafeArea())

            Button { dismiss() } label: {
                Label("Back", systemImage: "arrow.left")
            }
            .buttonStyle(CAWebButtonStyle(variant: .ghost, height: 32))
            .padding(.leading, 12)
            .padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadAndSyncSubmissions() }
        .sheet(isPresented: $showingSubmission) {
            SubmitWallpaperView {
                Task { await loadAndSyncSubmissions() }
            }
        }
        .alert("Delete All Cloud Projects", isPresented: $showingDeleteAll) {
            Button("Cancel", role: .cancel) { }
            Button(deleting ? "Deleting..." : "Delete All", role: .destructive) {
                deleteAllCloudProjects()
            }
            .disabled(deleting)
        } message: {
            Text("This will permanently delete the entire CAPlayground folder and all projects from your Google Drive.\n\n⚠️ Warning: This action cannot be undone. All cloud-stored projects will be permanently lost.")
        }
        .alert(messageDialogTitle, isPresented: $messageDialogOpen) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(messageDialogContent)
        }
    }

    private var displayName: String {
        if !auth.username.isEmpty { return auth.username }
        if case .string(let value) = auth.user?.userMetadata?["full_name"] { return value }
        return auth.user?.email ?? ""
    }

    private var submissionCard: some View {
        let awaiting = Array(submissions.filter { $0.status == "awaiting_review" }.prefix(3))
        let rejected = submissions.filter {
            $0.status == "rejected" && ($0.submittedAt ?? .distantPast) > Date().addingTimeInterval(-30 * 86_400)
        }
        let published = submissions.filter { $0.status == "approved" }

        return VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Wallpaper Submissions").font(.title3.bold())
                    Spacer()
                    submitButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Wallpaper Submissions").font(.title3.bold())
                    submitButton
                }
            }

            if loading {
                Text("Loading your submissions...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                submissionSection(
                    "Awaiting Review",
                    rows: awaiting,
                    empty: "No wallpapers awaiting review",
                    detail: "You can have up to five wallpapers awaiting review at a time.",
                    countText: "\(awaiting.count)/5 slots used",
                    syncing: isSyncing
                )
                if !rejected.isEmpty {
                    submissionSection(
                        "Rejected (Last 30 Days)",
                        rows: rejected,
                        empty: "",
                        detail: "Submissions that were not accepted. These will disappear after 30 days.",
                        countText: "\(rejected.count) rejected"
                    )
                }
                submissionSection(
                    "Published",
                    rows: published,
                    empty: "No published wallpapers yet",
                    detail: "Wallpapers that have been approved and are live in the gallery.",
                    countText: published.isEmpty ? "None yet" : "\(published.count) published"
                )
            }
        }
        .padding(24)
        .background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1)
        }
    }

    private var submitButton: some View {
        Button { showingSubmission = true } label: {
            Label("Submit Wallpaper", systemImage: "plus")
        }
        .buttonStyle(CAWebButtonStyle(variant: .accent))
    }

    private func submissionSection(
        _ title: String,
        rows: [WallpaperSubmission],
        empty: String,
        detail: String,
        countText: String,
        syncing: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Text(title).font(.subheadline.bold())
                    if syncing {
                        HStack(spacing: 4) {
                            Image(systemName: "cloud").font(.caption2)
                            Text("Syncing...")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(countText).font(.caption).foregroundStyle(.secondary)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)

            if rows.isEmpty {
                VStack(spacing: 4) {
                    Text(empty).font(.subheadline).foregroundStyle(.secondary)
                    if title == "Awaiting Review" {
                        Text("Click \"Submit Wallpaper\" to get started")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if title == "Published" {
                        Text("They'll appear here once approved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            CATheme.border(scheme).opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, dash: [5])
                        )
                }
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(row.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(statusTitle(row.status))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor(row.status).opacity(0.12), in: Capsule())
                            .foregroundStyle(statusColor(row.status))
                    }
                    .padding(12)
                    .background(statusColor(row.status).opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(statusColor(row.status).opacity(0.2))
                    }
                }
            }
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Cloud Projects").font(.title3.bold())
                Text("BETA")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(.blue)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue.opacity(0.2)))
            }
            Text("Sync and manage your projects in the cloud with Google Drive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if drive.connected {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.connected.to.line.below.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in to Google Drive").font(.subheadline.weight(.medium))
                        Text("Your projects can be synced to the cloud").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                            .disabled(deleting || drive.isLoading)
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if drive.isLoading { ProgressView() }
            if let message = drive.message { Text(message).font(.caption).foregroundStyle(.green) }
            if let error = drive.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(24)
        .background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1)
        }
    }

    private var accountOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account Options").font(.title3.bold())
            Text("Manage your email, username, password, or delete your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                NavigationLink("Manage Account") { AccountView() }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                Button {
                    Task { await auth.signOut(); dismiss() }
                } label: {
                    Text(loading ? "Signing out..." : "Sign Out")
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))
                .disabled(loading)
            }
        }
        .padding(24)
        .background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1)
        }
    }

    private func loadAndSyncSubmissions() async {
        loading = true
        submissions = await auth.wallpaperSubmissions()
        loading = false
        await syncAwaitingSubmissionStatuses()
    }

    private func syncAwaitingSubmissionStatuses() async {
        let awaiting = Array(submissions.filter { $0.status == "awaiting_review" }.prefix(3))
        guard !awaiting.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        var changed = false
        for submission in awaiting {
            do {
                var request = URLRequest(url: URL(string: "https://caplayground.vercel.app/api/wallpapers/sync")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["submission_id": submission.id])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if object["updated"] as? Bool == true { changed = true }
            } catch {
                // Match the website: one failed status sync must not block the dashboard.
            }
        }

        if changed {
            submissions = await auth.wallpaperSubmissions()
        }
    }

    private func deleteAllCloudProjects() {
        deleting = true
        Task {
            let success = await drive.deleteAll()
            deleting = false
            if success {
                messageDialogTitle = "Success"
                messageDialogContent = "All cloud projects deleted successfully!"
            } else {
                messageDialogTitle = "Error"
                messageDialogContent = "Failed to delete: \(drive.error ?? "Failed to delete cloud projects")"
            }
            messageDialogOpen = true
        }
    }

    private func statusTitle(_ status: String) -> String {
        status == "awaiting_review" ? "Awaiting Review" : status == "approved" ? "Published" : "Rejected"
    }

    private func statusColor(_ status: String) -> Color {
        status == "awaiting_review" ? .orange : status == "approved" ? .green : .red
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
    @State private var videoPreviewURL: URL?
    @State private var pickTendies = false
    @State private var pickVideo = false
    @State private var agreedRules = false
    @State private var agreedQuality = false
    @State private var pullRequestURL: URL?
    let completed: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if auth.user == nil { signInRequiredContent } else { content }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $pickTendies,
            allowedContentTypes: [.tendies],
            allowsMultipleSelection: false
        ) { load($0, videoFile: false) }
        .fileImporter(
            isPresented: $pickVideo,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { load($0, videoFile: true) }
        .onDisappear { removePreviewFile() }
    }

    private var signInRequiredContent: some View {
        VStack(spacing: 16) {
            Text("Sign In Required").font(.title2.weight(.semibold))
            Text("You need to be signed in to submit wallpapers")
                .foregroundStyle(.secondary)
            Text("Please sign in to your account to submit wallpapers to the gallery.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink("Sign In") { SignInView() }
                .buttonStyle(CAWebButtonStyle(variant: .accent))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var title: String {
        step == .form ? "Submit Wallpaper" :
        step == .preview ? "Preview Submission" :
        step == .rules ? "Submission Rules & Guidelines" :
        step == .submitting ? "Submitting Wallpaper" : "Submission Successful!"
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .form:
            Text("Share your wallpaper with the CAPlayground community")
                .foregroundStyle(.secondary)

            labeledField("Wallpaper Name *") {
                TextField("Enter wallpaper name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, value in
                        if value.count > 42 { name = String(value.prefix(42)) }
                    }
                Text("\(name.count)/42 characters").font(.caption).foregroundStyle(.secondary)
            }

            labeledField("Description *") {
                TextField("Describe your wallpaper...", text: $description, axis: .vertical)
                    .lineLimit(4...4)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: description) { _, value in
                        if value.count > 60 { description = String(value.prefix(60)) }
                    }
                Text("\(description.count)/60 characters").font(.caption).foregroundStyle(.secondary)
            }

            labeledField(".tendies File *") {
                Button {
                    pickTendies = true
                } label: {
                    Label(tendiesName.isEmpty ? "Choose .tendies file" : tendiesName, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))
            }

            labeledField("Preview Video *") {
                Button {
                    pickVideo = true
                } label: {
                    Label(videoName.isEmpty ? "Choose video file" : videoName, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CAWebButtonStyle(variant: .outline))

                if let videoPreviewURL {
                    LoopingVideoPreview(url: videoPreviewURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                }
            }

            labeledField("Author") {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                Text("Your username will be displayed as the wallpaper creator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Continue", systemImage: "arrow.right") { step = .preview }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                    .disabled(!valid)
            }

        case .preview:
            Text("This is how your wallpaper will appear in the gallery")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                if let videoPreviewURL {
                    LoopingVideoPreview(url: videoPreviewURL)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(.separator)))
                }
                Text(name).font(.title2.bold()).lineLimit(1)
                Text("by \(author) (submitted on website)").foregroundStyle(.secondary).lineLimit(2)
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Button("Download .tendies") { }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                    .frame(maxWidth: .infinity)
                    .disabled(true)
                    .accessibilityHint("Download not available in preview")
            }
            .padding(16)
            .caPanel()

            HStack {
                Button("Back", systemImage: "arrow.left") { step = .form }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                Spacer()
                Button("Looks Good", systemImage: "arrow.right") { step = .rules }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
            }

        case .rules:
            Text("Please review and agree to the rules before submitting your wallpaper")
                .foregroundStyle(.secondary)

            Text("1. No NSFW or adult-only content.\n\n2. Wallpapers must not consist of a single video layer. They should demonstrate creative use of CAPlayground's features.\n\n3. No political, inappropriate, or offensive content (including but not limited to discrimination based on sex, race, or religion).\n\n4. Ensure you have the rights to all assets used in your submission.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            websiteCheckbox(
                "I confirm that this submission is original and does not contain NSFW, political, or offensive content.",
                isOn: $agreedRules
            )
            websiteCheckbox(
                "I confirm that this wallpaper is more than just a single video layer.",
                isOn: $agreedQuality
            )

            HStack {
                Button("Back", systemImage: "arrow.left") { step = .preview }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                Spacer()
                Button("Submit Wallpaper", systemImage: "chevron.left.forwardslash.chevron.right") { submit() }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                    .disabled(!agreedRules || !agreedQuality)
            }

        case .submitting:
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Submitting Wallpaper").font(.headline)
                Text("Uploading files and creating Pull Request...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)

        case .success:
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Submission Successful!").font(.title2.bold())
                Text("Your wallpaper has been submitted as a Pull Request. Once approved, it will appear in the gallery.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let pullRequestURL {
                    Link("View Pull Request", destination: pullRequestURL)
                        .buttonStyle(CAWebButtonStyle(variant: .outline))
                }
                Button("Done") {
                    completed()
                    dismiss()
                }
                .buttonStyle(CAWebButtonStyle(variant: .accent))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }

        if let error = auth.error {
            Text(error).font(.subheadline).foregroundStyle(.red)
        }
    }

    private var author: String { auth.username.isEmpty ? "Anonymous" : auth.username }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        tendies != nil && video != nil
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium))
            content()
        }
    }

    private func websiteCheckbox(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue ? CATheme.accent : .secondary)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func load(_ result: Result<[URL], Error>, videoFile: Bool) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }

        if videoFile {
            video = data
            videoName = url.lastPathComponent
            videoExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension.lowercased()
            removePreviewFile()
            let preview = FileManager.default.temporaryDirectory
                .appendingPathComponent("caplayground-preview-\(UUID().uuidString)")
                .appendingPathExtension(videoExtension)
            do {
                try data.write(to: preview, options: .atomic)
                videoPreviewURL = preview
            } catch {
                auth.error = error.localizedDescription
            }
        } else {
            tendies = data
            tendiesName = url.lastPathComponent
        }
    }

    private func submit() {
        guard let tendies, let video else { return }
        auth.error = nil
        step = .submitting
        Task {
            if let url = await auth.submitWallpaper(
                name: name,
                description: description,
                tendies: tendies,
                video: video,
                videoExtension: videoExtension
            ) {
                pullRequestURL = url
                step = .success
            } else {
                step = .preview
            }
        }
    }

    private func removePreviewFile() {
        if let videoPreviewURL {
            try? FileManager.default.removeItem(at: videoPreviewURL)
            self.videoPreviewURL = nil
        }
    }
}

private struct LoopingVideoPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.configure(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}

private final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
    }

    func configure(url: URL) {
        guard currentURL != url else { return }
        stop()
        currentURL = url
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        queuePlayer = player
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        playerLayer.player = nil
        looper = nil
        queuePlayer = nil
        currentURL = nil
    }
}
