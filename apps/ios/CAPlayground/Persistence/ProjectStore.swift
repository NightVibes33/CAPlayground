import Foundation
import Observation

@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [CAProjectDocument] = []
    var lastError: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let directory: URL

    init(fileManager: FileManager = .default) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func createProject(name: String = "New Wallpaper", width: Double = 390, height: Double = 844, gyroEnabled: Bool = false) -> CAProjectDocument {
        var project = CAProjectDocument.blank(name: uniqueName(name))
        project.width = width
        project.height = height
        project.gyroEnabled = gyroEnabled
        for key in project.documents.keys {
            project.documents[key]?.root.position = .init(x: width / 2, y: height / 2)
            project.documents[key]?.root.size = .init(width: width, height: height)
        }
        if gyroEnabled {
            var wallpaper = AnimationDocument(root: LayerModel(
                id: UUID(), name: "Root Layer", kind: .basic,
                children: [
                    LayerModel(id: UUID(), name: "BACKGROUND", kind: .transform,
                               position: .init(x: width / 2, y: height / 2), size: .init(width: width, height: height)),
                    LayerModel(id: UUID(), name: "FLOATING", kind: .transform,
                               position: .init(x: width / 2, y: height / 2), size: .init(width: width, height: height))
                ],
                position: .init(x: width / 2, y: height / 2), size: .init(width: width, height: height)
            ))
            wallpaper.states = ["Locked", "Unlock", "Sleep"]
            project.documents = [.wallpaper: wallpaper]
            project.activeCA = .wallpaper
        }
        projects.insert(project, at: 0)
        save(project)
        return project
    }

    private func uniqueName(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "New Wallpaper" : trimmed
        let existing = Set(projects.map(\.name))
        guard existing.contains(candidate) else { return candidate }
        var suffix = 1
        while existing.contains("\(candidate) (\(suffix))") { suffix += 1 }
        return "\(candidate) (\(suffix))"
    }

    func update(_ project: CAProjectDocument) {
        var value = project
        value.modifiedAt = .now
        if let index = projects.firstIndex(where: { $0.id == value.id }) {
            projects[index] = value
        } else {
            projects.insert(value, at: 0)
        }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
        save(value)
    }

    func delete(_ project: CAProjectDocument) {
        projects.removeAll { $0.id == project.id }
        try? FileManager.default.removeItem(at: url(for: project.id))
    }

    private func load() {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "caproject" }
            projects = files.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(CAProjectDocument.self, from: data)
            }.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func save(_ project: CAProjectDocument) {
        do {
            try encoder.encode(project).write(to: url(for: project.id), options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("caproject")
    }
}
