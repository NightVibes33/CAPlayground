import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExportView: View {
    private enum ViewState { case select, success }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    let project: CAProjectDocument

    @State private var filename: String
    @State private var format: CAExportFormat = .ca
    @State private var license: CAExportLicense = .none
    @State private var confirmed = false
    @State private var file: ExportedArchive?
    @State private var exporting = false
    @State private var errorMessage: String?
    @State private var viewState: ViewState = .select
    @State private var showingSubmission = false

    init(project: CAProjectDocument) {
        self.project = project
        _filename = State(initialValue: project.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewState == .select { exportSelection }
                    else { successView }
                }
                .padding(16)
            }
            .navigationTitle(viewState == .select ? "Export" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewState == .select {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { viewState = .select } label: { Label("Back", systemImage: "arrow.left") }
                    }
                }
            }
            .fileExporter(
                isPresented: $exporting,
                document: file,
                contentType: format == .ca ? .zip : .tendies,
                defaultFilename: safeFilename + (format == .ca ? ".zip" : ".tendies")
            ) { result in
                switch result {
                case .success:
                    viewState = .success
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Export failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Failed to export file. Please try again.")
            }
            .sheet(isPresented: $showingSubmission) { submissionSheet }
        }
    }

    private var exportSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a filename, format, and license, then export your project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("File name").font(.subheadline.weight(.medium))
                TextField(project.name.isEmpty ? "Project" : project.name, text: $filename)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Format").font(.subheadline.weight(.medium))
                Picker("Choose export format", selection: $format) {
                    Text(".ca bundle").tag(CAExportFormat.ca)
                    Text("Tendies").tag(CAExportFormat.tendies)
                }
                .pickerStyle(.segmented)
                Text(format == .ca
                     ? "Download a .zip containing your Background.ca and Floating.ca files."
                     : "Create a .tendies wallpaper file compatible with Nugget and Pocket Poster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("License").font(.subheadline.weight(.medium))
                Picker("Choose a license", selection: $license) {
                    Text("No license").tag(CAExportLicense.none)
                    Text("CC BY 4.0").tag(CAExportLicense.attribution)
                    Text("CC BY-SA 4.0").tag(CAExportLicense.shareAlike)
                    Text("CC BY-NC 4.0").tag(CAExportLicense.nonCommercial)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(licenseDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                if license != .none {
                    Button { confirmed.toggle() } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                                .foregroundStyle(confirmed ? CATheme.accent : .secondary)
                            Text("I confirm that I created or have permission to use all content in this wallpaper and that I grant the selected license to the exported file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("By exporting, you confirm that you created or have permission to use all content in this wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(format == .ca ? "Export .ca" : "Export tendies") { export() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(license != .none && !confirmed)
            }
        }
    }

    private var successView: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Thank you for using CAPlayground!")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text("What should I do next?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                nextStep(number: 1, title: "Watch video") {
                    Text("Watch the video on how to use Pocket Poster or Nugget.")
                    Link(destination: URL(string: "https://www.youtube.com/watch?v=nSBQIwAaAEc")!) {
                        Label("Watch the video", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                nextStep(number: 2, title: "Test your wallpaper") {
                    Text("Apply the wallpaper to your device and test it.")
                }

                nextStep(number: 3, title: "Showcase your work (Optional)") {
                    Text("Submit the wallpaper if you want to showcase your work.")
                    Button("Submit wallpaper") { showingSubmission = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!) {
                    Label("Star the repo", systemImage: "star")
                }
                .buttonStyle(.bordered)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func nextStep<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).")
                .font(.subheadline.weight(.medium))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.medium))
                content()
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(.separator)))
    }

    @ViewBuilder private var submissionSheet: some View {
        if auth.user == nil {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Sign In Required").font(.title2.weight(.semibold))
                    Text("You need to be signed in to submit wallpapers")
                        .foregroundStyle(.secondary)
                    Text("Please sign in to your account to submit wallpapers to the gallery.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    NavigationLink("Sign In") { SignInView() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingSubmission = false }
                    }
                }
            }
            .presentationDetents([.medium])
        } else {
            SubmitWallpaperView { showingSubmission = false }
        }
    }

    private var licenseDescription: String {
        switch license {
        case .none:
            "No license text is included. You retain all rights; sharing terms are not specified."
        case .attribution:
            "Requires attribution. Allows sharing and adaptation, including commercial use. Not recommended to allow commercial use."
        case .shareAlike:
            "Requires attribution and share-alike. Adaptations must use the same license. Not recommended to allow commercial use."
        case .nonCommercial:
            "Requires attribution. Non-commercial use only; adaptations are allowed with the same terms. This license is recommended to prevent work from being sold."
        }
    }

    private var safeFilename: String {
        let candidate = filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (project.name.isEmpty ? "Project" : project.name) : filename
        let safe = candidate.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return safe.isEmpty ? "Project" : safe
    }

    private func export() {
        guard license == .none || confirmed else { return }
        do {
            file = ExportedArchive(data: try CAArchiveExporter.export(project: project, format: format, license: license))
            exporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ExportedArchive: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .tendies] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CAProjectFile: FileDocument {
    static var readableContentTypes: [UTType] { [.caPlaygroundProject] }
    var project: CAProjectDocument
    init(project: CAProjectDocument) { self.project = project }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(CAProjectDocument.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(project))
    }
}

extension UTType {
    static let caPlaygroundProject = UTType(exportedAs: "com.nightvibes33.caplayground.project", conformingTo: .json)
    static let tendies = UTType(exportedAs: "com.nightvibes33.caplayground.tendies", conformingTo: .zip)
}
