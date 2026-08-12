import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let project: CAProjectDocument
    @State private var document: CAProjectFile?
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("Native project") {
                    Button {
                        document = CAProjectFile(project: project)
                        exporting = true
                    } label: {
                        Label("Export .caproject", systemImage: "doc.zipper")
                    }
                }
                Section {
                    Label(".ca and .tendies compatibility export is isolated from system wallpaper APIs.",
                          systemImage: "checkmark.shield")
                } footer: {
                    Text("The app only writes user-selected documents through the Files interface.")
                }
            }
            .navigationTitle("Export")
            .toolbar { Button("Done") { dismiss() } }
            .fileExporter(isPresented: $exporting, document: document,
                          contentType: .caPlaygroundProject,
                          defaultFilename: project.name) { _ in }
        }
    }
}

struct CAProjectFile: FileDocument {
    static var readableContentTypes: [UTType] { [.caPlaygroundProject] }
    var project: CAProjectDocument

    init(project: CAProjectDocument) { self.project = project }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(CAProjectDocument.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(project))
    }
}

extension UTType {
    static let caPlaygroundProject = UTType(exportedAs: "com.nightvibes33.caplayground.project",
                                            conformingTo: .json)
}
