import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LayerPanel: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @State private var renameOpen = false
    @State private var renameID: UUID?
    @State private var renameValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                AddLayerMenu(project: $project, selectedID: $selectedID)
            }
            .padding(12)
            Divider()
            List(selection: $selectedID) {
                OutlineGroup(project.root.children.reversed(), children: \.outlineChildren) { layer in
                    HStack(spacing: 6) {
                        Text(layer.name)
                        Text("(\(layer.kind == .shape ? "basic" : layer.kind.rawValue))").foregroundStyle(.secondary)
                        Spacer()
                        Button { project.root.update(id: layer.id) { $0.isVisible.toggle() } } label: { Image(systemName: layer.isVisible ? "eye" : "eye.slash") }
                            .buttonStyle(.plain)
                    }
                        .tag(layer.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = layer.id }
                        .contextMenu {
                            Button("Bring to Front") { project.root.reorder(id: layer.id, action: .front) }
                            Button("Bring Forward") { project.root.reorder(id: layer.id, action: .forward) }
                            Button("Send Backward") { project.root.reorder(id: layer.id, action: .backward) }
                            Button("Send to Back") { project.root.reorder(id: layer.id, action: .back) }
                            Divider()
                            Button("Rename…") { beginRename(layer) }
                            Button("Duplicate") {
                                if let newID = project.root.duplicate(id: layer.id) { selectedID = newID }
                            }
                            if !isProtected(layer) {
                                Button("Delete", role: .destructive) {
                                    project.root.remove(id: layer.id)
                                    if selectedID == layer.id { selectedID = nil }
                                }
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
        .caPanel()
        .sheet(isPresented: $renameOpen) {
            NavigationStack {
                Form { TextField("Layer name", text: $renameValue) }
                    .navigationTitle("Rename layer")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renameOpen = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard let renameID else { return }
                                let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                project.root.update(id: renameID) { $0.name = name }
                                renameOpen = false
                            }
                            .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
            .presentationDetents([.height(220)])
        }
    }

    private func beginRename(_ layer: LayerModel) {
        renameID = layer.id
        renameValue = layer.name
        renameOpen = true
    }

    private func isProtected(_ layer: LayerModel) -> Bool {
        project.gyroEnabled && (layer.name == "BACKGROUND" || layer.name == "FLOATING")
    }
}

struct AddLayerMenu: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @State private var imageImporterOpen = false
    @State private var videoLayerOpen = false

    var body: some View {
        Menu {
            Button("Text Layer") { add(.text) }
            Button("Basic Layer") { add(.shape) }
            Button("Gradient Layer") { add(.gradient) }
            Button("Image Layer…") { imageImporterOpen = true }
            Button("Video Layer…") { videoLayerOpen = true }
            Button("Emitter Layer") { add(.emitter) }
            Button("Replicator Layer") { add(.replicator) }
            if project.gyroEnabled { Button("Transform Layer") { add(.transform) } }
            Button("Liquid Glass Layer") { add(.liquidGlass) }
        } label: { Label("Add Layer", systemImage: "plus") }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Add Layer")
        .disabled(selectedID.flatMap { project.root.find(id: $0) }?.kind == .emitter)
        .fileImporter(isPresented: $imageImporterOpen, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls where url.pathExtension.lowercased() != "gif" { importImage(url) }
        }
        .sheet(isPresented: $videoLayerOpen) {
            VideoLayerDialog(project: $project, selectedID: $selectedID)
        }
    }

    private func add(_ kind: LayerKind) {
        let id = UUID()
        let parent = selectedID.flatMap { project.root.find(id: $0) }
        let containerWidth = parent?.size.width ?? project.width
        let containerHeight = parent?.size.height ?? project.height
        let baseName: String = switch kind {
        case .shape: "Basic Layer"
        case .replicator: "Replicator"
        default: "\(kind.title) Layer"
        }
        var layer = LayerModel(
            id: id, name: nextName(baseName), kind: kind,
            position: .init(x: containerWidth / 2, y: containerHeight / 2),
            size: .init(width: 120, height: 40)
        )
        switch kind {
        case .text:
            layer.text = "Text Layer"; layer.fontSize = 16; layer.textColor = "#111827"
            layer.textAlignment = "center"; layer.fontFamily = "SFProText-Regular"; layer.wrapsText = true
        case .shape:
            layer.size = .init(width: 120, height: 120); layer.shape = "rect"
            layer.fillColor = "#60A5FA"; layer.backgroundColor = "#60A5FA"
        case .gradient:
            layer.size = .init(width: 200, height: 200)
            layer.gradientType = "axial"
            layer.gradientStops = [.init(color: "#FFFFFF", opacity: 1), .init(color: "#000000", opacity: 1)]
            layer.gradientStart = .init(x: 0, y: 0); layer.gradientEnd = .init(x: 1, y: 1)
        case .liquidGlass:
            layer.size = .init(width: 200, height: 200); layer.cornerRadius = 40
        case .emitter:
            layer.position = .init(x: project.width / 2, y: project.height / 2)
            layer.size = .init(width: project.width, height: project.height)
            layer.emitterPosition = .init(x: 0, y: 0); layer.emitterSize = .init(width: 0, height: 0)
            layer.emitterShape = "point"; layer.emitterMode = "volume"; layer.renderMode = "unordered"; layer.emitterCells = []
        case .replicator:
            layer.size = .init(width: project.width, height: project.height)
            layer.instanceCount = 5; layer.instanceTranslationX = 0; layer.instanceTranslationY = 0
            layer.instanceTranslationZ = 0; layer.instanceRotation = 0; layer.instanceDelay = 0
        case .transform:
            layer.size = .init(width: 200, height: 200)
        case .image, .video:
            break
        default: break
        }
        if let selectedID, project.root.find(id: selectedID)?.kind != .emitter {
            project.root.update(id: selectedID) { $0.children.append(layer) }
        } else {
            project.root.children.append(layer)
        }
        selectedID = id
    }

    private func importImage(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        let filename = uniqueAssetName(url.lastPathComponent.isEmpty ? "Image.png" : url.lastPathComponent)
        project.assets[filename] = data
        let imageWidth = Double(image.size.width)
        let imageHeight = Double(image.size.height)
        let scale = min(1, min(project.width / imageWidth, project.height / imageHeight))
        let id = UUID()
        var layer = LayerModel(
            id: id, name: nextName(url.deletingPathExtension().lastPathComponent.isEmpty ? "Image Layer" : url.deletingPathExtension().lastPathComponent), kind: .image,
            position: insertionPosition(),
            size: .init(width: imageWidth * scale, height: imageHeight * scale)
        )
        layer.imageName = filename
        layer.contentMode = "fill"
        insert(layer)
    }

    private func insertionPosition() -> Vector2 {
        let parent = selectedID.flatMap { project.root.find(id: $0) }
        return .init(x: (parent?.size.width ?? project.width) / 2, y: (parent?.size.height ?? project.height) / 2)
    }

    private func insert(_ layer: LayerModel) {
        if let selectedID, project.root.find(id: selectedID)?.kind != .emitter {
            project.root.update(id: selectedID) { $0.children.append(layer) }
        } else {
            project.root.children.append(layer)
        }
        selectedID = layer.id
    }

    private func uniqueAssetName(_ proposed: String) -> String {
        guard project.assets[proposed] != nil else { return proposed }
        let url = URL(fileURLWithPath: proposed)
        return "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
    }

    private func nextName(_ base: String) -> String {
        let names = Set(project.root.flattened().map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}

enum LayerReorderAction { case front, forward, backward, back }

extension LayerModel {
    func flattened() -> [LayerModel] { [self] + children.flatMap { $0.flattened() } }
    mutating func duplicate(id: UUID) -> UUID? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            var copy = children[index]
            copy.refreshIDs()
            copy.name += " Copy"
            children.insert(copy, at: index + 1)
            return copy.id
        }
        for index in children.indices {
            if let duplicated = children[index].duplicate(id: id) { return duplicated }
        }
        return nil
    }

    mutating func reorder(id: UUID, action: LayerReorderAction) {
        if let index = children.firstIndex(where: { $0.id == id }) {
            switch action {
            case .front:
                children.append(children.remove(at: index))
            case .forward where index < children.count - 1:
                children.swapAt(index, index + 1)
            case .backward where index > 0:
                children.swapAt(index, index - 1)
            case .back:
                children.insert(children.remove(at: index), at: 0)
            default:
                break
            }
            return
        }
        for index in children.indices { children[index].reorder(id: id, action: action) }
    }

    private mutating func refreshIDs() {
        id = UUID()
        for index in children.indices { children[index].refreshIDs() }
    }
}
