import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let project: CAProjectDocument
    @State private var filename: String
    @State private var format: CAExportFormat = .ca
    @State private var license: CAExportLicense = .none
    @State private var confirmed = false
    @State private var file: ExportedArchive?
    @State private var exporting = false
    @State private var errorMessage: String?

    init(project: CAProjectDocument) { self.project = project; _filename = State(initialValue: project.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") { TextField("Filename", text: $filename) }
                Section("Format") {
                    Picker("Format", selection: $format) {
                        Text(".ca").tag(CAExportFormat.ca); Text(".tendies").tag(CAExportFormat.tendies)
                    }.pickerStyle(.segmented)
                    Text(format == .ca ? "Download a .zip containing your Background.ca and Floating.ca files." : "Create a .tendies wallpaper file compatible with Nugget and Pocket Poster.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("License") {
                    Picker("License", selection: $license) {
                        Text("No license").tag(CAExportLicense.none)
                        Text("CC BY 4.0").tag(CAExportLicense.attribution)
                        Text("CC BY-SA 4.0").tag(CAExportLicense.shareAlike)
                        Text("CC BY-NC 4.0").tag(CAExportLicense.nonCommercial)
                    }
                    if license != .none {
                        Toggle("I understand this license will be included with the export.", isOn: $confirmed)
                    }
                }
                Section {
                    Button(format == .ca ? "Export .ca" : "Export tendies") { export() }
                        .frame(maxWidth: .infinity)
                        .disabled(filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (license != .none && !confirmed))
                }
            }
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: file, contentType: format == .ca ? .zip : .tendies,
                          defaultFilename: safeFilename + (format == .ca ? ".zip" : ".tendies")) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "Failed to export file. Please try again.") }
        }
    }

    private var safeFilename: String {
        filename.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }

    private func export() {
        do {
            file = ExportedArchive(data: try CAArchiveExporter.export(project: project, format: format, license: license))
            exporting = true
        } catch { errorMessage = error.localizedDescription }
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
