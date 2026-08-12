import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO
import WebKit

struct LayerPanel: View {
    private enum DropPosition { case before, after, into }

    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @State private var renameOpen = false
    @State private var renameID: UUID?
    @State private var renameValue = ""
    @State private var collapsed: Set<UUID> = []
    @State private var rootCollapsed = false
    @State private var selectMode = false
    @State private var multiSelected: Set<UUID> = []
    @State private var dragOverID: UUID?
    @State private var dragPosition: DropPosition?
    @State private var uploadStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                if let uploadStatus { Text(uploadStatus).font(.caption).foregroundStyle(.secondary) }
                if selectedID.flatMap({ project.root.find(id: $0) })?.kind == .emitter {
                    Button { } label: { Label("Add Layer", systemImage: "plus") }.buttonStyle(.plain).disabled(true)
                        .help("Sublayers are not supported for emitter layers.")
                } else {
                    AddLayerMenu(project: $project, selectedID: $selectedID)
                }
            }
            .padding(12)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    rootRow
                    if !rootCollapsed {
                        if project.root.children.isEmpty {
                            Text("No layers yet").font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 24).frame(height: 40)
                        }
                        ForEach(project.root.children) { layer in rowTree(layer, depth: 1) }
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let source = UUID(uuidString: raw) else { return false }
                    move(source, target: nil, position: .after)
                    return true
                }
            }

            if selectMode {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(multiSelected.count) selected").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button { duplicateSelected() } label: { Image(systemName: "doc.on.doc").frame(width: 32, height: 32) }
                            .buttonStyle(.bordered).disabled(multiSelected.isEmpty).help("Duplicate layers")
                        Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "trash").frame(width: 32, height: 32) }
                            .buttonStyle(.bordered).disabled(multiSelected.isEmpty).help("Delete layers")
                        Button { selectMode = false; multiSelected.removeAll() } label: { Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                }.padding(10)
            }
        }
        .caPanel()
        .sheet(isPresented: $renameOpen) { renameDialog }
        .onChange(of: project.root) { _, root in multiSelected = multiSelected.filter { root.find(id: $0) != nil } }
    }

    private var rootRow: some View {
        HStack(spacing: 6) {
            if !project.root.children.isEmpty {
                Button { rootCollapsed.toggle() } label: { Image(systemName: rootCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 11)).frame(width: 18, height: 28) }.buttonStyle(.plain)
            } else { Color.clear.frame(width: 18, height: 28) }
            Text("Root Layer").fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 8).frame(height: 40)
        .background(selectedID == project.root.id ? CATheme.accent.opacity(0.30) : .clear)
        .contentShape(Rectangle()).onTapGesture { if !selectMode { selectedID = project.root.id } }
    }

    @ViewBuilder private func rowTree(_ layer: LayerModel, depth: Int) -> some View {
        layerRow(layer, depth: depth)
        if !collapsed.contains(layer.id), layer.kind != .video {
            ForEach(layer.children) { child in rowTree(child, depth: depth + 1) }
        }
    }

    private func layerRow(_ layer: LayerModel, depth: Int) -> some View {
        let protected = isProtected(layer)
        let hasChildren = layer.kind != .video && !layer.children.isEmpty
        let hidden = !layer.isVisible
        return VStack(spacing: 0) {
            if dragOverID == layer.id && dragPosition == .before { dropLine(depth) }
            HStack(spacing: 5) {
                if selectMode && !protected {
                    Button { toggleMulti(layer.id) } label: {
                        Image(systemName: multiSelected.contains(layer.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(multiSelected.contains(layer.id) ? CATheme.accent : .secondary).frame(width: 18, height: 28)
                    }.buttonStyle(.plain)
                } else if hasChildren {
                    Button { toggleCollapse(layer.id) } label: {
                        Image(systemName: collapsed.contains(layer.id) ? "chevron.right" : "chevron.down").font(.system(size: 11)).frame(width: 18, height: 28)
                    }.buttonStyle(.plain)
                } else { Color.clear.frame(width: 18, height: 28) }

                Image(systemName: layer.kind.symbol).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(layer.name).lineLimit(1)
                Text("(\(layer.kind == .shape ? "basic" : layer.kind.rawValue))").foregroundStyle(.secondary).font(.caption)
                Spacer(minLength: 4)

                Button { project.root.update(id: layer.id) { $0.isVisible.toggle() } } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye").frame(width: 26, height: 28).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(hidden ? "Show layer" : "Hide layer")

                if !protected {
                    Menu {
                        Button("Rename") { beginRename(layer) }
                        Button("Duplicate") { if let newID = project.root.duplicate(id: layer.id) { selectedID = newID } }
                        Button("Delete", role: .destructive) { delete(layer.id) }
                        Button("Select") { selectMode = true; multiSelected.insert(layer.id) }
                    } label: { Image(systemName: "ellipsis.vertical").frame(width: 26, height: 28).foregroundStyle(.secondary) }
                }
            }
            .font(.system(size: 14))
            .padding(.leading, CGFloat(8 + depth * 16)).padding(.trailing, 8).frame(height: 40)
            .opacity(hidden ? 0.5 : 1)
            .background(dragOverID == layer.id && dragPosition == .into ? CATheme.accent.opacity(0.30) : selectedID == layer.id && dragOverID == nil ? CATheme.accent.opacity(0.30) : .clear)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if !selectMode { beginRename(layer) } }
            .onTapGesture { if selectMode && !protected { toggleMulti(layer.id) } else { selectedID = layer.id } }
            .contextMenu {
                Button("Bring to Front") { project.root.reorder(id: layer.id, action: .front) }
                Button("Bring Forward") { project.root.reorder(id: layer.id, action: .forward) }
                Button("Send Backward") { project.root.reorder(id: layer.id, action: .backward) }
                Button("Send to Back") { project.root.reorder(id: layer.id, action: .back) }
                Divider()
                Button("Rename…") { beginRename(layer) }
                Button("Duplicate") { if let newID = project.root.duplicate(id: layer.id) { selectedID = newID } }
                if !protected { Button("Delete", role: .destructive) { delete(layer.id) } }
            }
            .draggable(layer.id.uuidString)
            .dropDestination(for: String.self) { items, point in
                guard let raw = items.first, let source = UUID(uuidString: raw), source != layer.id else { return false }
                let position: DropPosition = protected && project.gyroEnabled ? .into : point.y < 10 ? .before : point.y > 30 ? .after : .into
                move(source, target: layer.id, position: position)
                dragOverID = nil; dragPosition = nil
                return true
            } isTargeted: { targeted in
                dragOverID = targeted ? layer.id : nil
                if targeted { dragPosition = protected && project.gyroEnabled ? .into : .into }
                else { dragPosition = nil }
            }
            if dragOverID == layer.id && dragPosition == .after { dropLine(depth) }
        }
    }

    private func dropLine(_ depth: Int) -> some View {
        Rectangle().fill(CATheme.accent).frame(height: 2).padding(.leading, CGFloat(8 + depth * 16))
    }

    private var renameDialog: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Give this layer a nice new name.").font(.subheadline).foregroundStyle(.secondary)
                TextField("Layer name", text: $renameValue).textFieldStyle(.roundedBorder)
                Spacer()
            }.padding(20)
            .navigationTitle("Rename layer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renameOpen = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let renameID else { return }
                        let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        project.root.update(id: renameID) { $0.name = name }
                        renameOpen = false
                    }.disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.height(220)])
    }

    private func beginRename(_ layer: LayerModel) { renameID = layer.id; renameValue = layer.name; renameOpen = true }
    private func toggleCollapse(_ id: UUID) { if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) } }
    private func toggleMulti(_ id: UUID) { if multiSelected.contains(id) { multiSelected.remove(id) } else { multiSelected.insert(id) } }
    private func isProtected(_ layer: LayerModel) -> Bool { project.gyroEnabled && (layer.name == "BACKGROUND" || layer.name == "FLOATING") }
    private func delete(_ id: UUID) { project.root.remove(id: id); multiSelected.remove(id); if selectedID == id { selectedID = nil } }

    private func duplicateSelected() {
        for id in multiSelected { _ = project.root.duplicate(id: id) }
    }

    private func deleteSelected() {
        for id in multiSelected where project.root.find(id: id).map({ !isProtected($0) }) ?? false { project.root.remove(id: id) }
        if let selectedID, multiSelected.contains(selectedID) { self.selectedID = nil }
        multiSelected.removeAll()
    }

    private func move(_ source: UUID, target: UUID?, position: DropPosition) {
        guard source != target, let sourceLayer = project.root.find(id: source), target.map({ !sourceLayer.contains(id: $0) }) ?? true else { return }
        guard let moving = project.root.removeReturning(id: source) else { return }
        if let target {
            project.root.insert(moving, relativeTo: target, position: position)
        } else {
            project.root.children.append(moving)
        }
        selectedID = source
    }
}

struct AddLayerMenu: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @State private var imageImporterOpen = false
    @State private var videoLayerOpen = false
    @State private var uploadStatus: String?

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
        .accessibilityLabel("Add Layer")
        .disabled(selectedID.flatMap { project.root.find(id: $0) }?.kind == .emitter)
        .fileImporter(isPresented: $imageImporterOpen, allowedContentTypes: NativeImageAssetLoader.allowedTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await importImages(urls) }
        }
        .sheet(isPresented: $videoLayerOpen) { VideoLayerDialog(project: $project, selectedID: $selectedID) }
    }

    private func add(_ kind: LayerKind) {
        let id = UUID()
        let parent = selectedID.flatMap { project.root.find(id: $0) }
        let containerWidth = parent?.size.width ?? project.width
        let containerHeight = parent?.size.height ?? project.height
        let baseName: String = switch kind { case .shape: "Basic Layer"; case .replicator: "Replicator"; default: "\(kind.title) Layer" }
        var layer = LayerModel(id: id, name: nextName(baseName), kind: kind, position: .init(x: containerWidth / 2, y: containerHeight / 2), size: .init(width: 120, height: 40))
        switch kind {
        case .text:
            layer.text = "Text Layer"; layer.fontSize = 16; layer.textColor = "#111827"; layer.textAlignment = "center"; layer.fontFamily = "SFProText-Regular"; layer.wrapsText = true
        case .shape:
            layer.size = .init(width: 120, height: 120); layer.shape = "rect"; layer.fillColor = "#60A5FA"; layer.backgroundColor = "#60A5FA"
        case .gradient:
            layer.size = .init(width: 200, height: 200); layer.gradientType = "axial"; layer.gradientStops = [.init(color: "#FFFFFF", opacity: 1), .init(color: "#000000", opacity: 1)]; layer.gradientStart = .init(x: 0, y: 0); layer.gradientEnd = .init(x: 1, y: 1)
        case .liquidGlass: layer.size = .init(width: 200, height: 200); layer.cornerRadius = 40
        case .emitter:
            layer.position = .init(x: project.width / 2, y: project.height / 2); layer.size = .init(width: project.width, height: project.height); layer.emitterPosition = .init(x: 0, y: 0); layer.emitterSize = .init(width: 0, height: 0); layer.emitterShape = "point"; layer.emitterMode = "volume"; layer.renderMode = "unordered"; layer.emitterCells = []
        case .replicator:
            layer.size = .init(width: project.width, height: project.height); layer.instanceCount = 5; layer.instanceTranslationX = 0; layer.instanceTranslationY = 0; layer.instanceTranslationZ = 0; layer.instanceRotation = 0; layer.instanceDelay = 0
        case .transform: layer.size = .init(width: 200, height: 200)
        case .image, .video, .basic: break
        }
        insert(layer)
    }

    @MainActor private func importImages(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        uploadStatus = urls.count > 1 ? "Uploading \(urls.count) images..." : "Uploading image..."
        defer { uploadStatus = nil }
        for url in urls {
            if url.pathExtension.lowercased() == "gif" { uploadStatus = "GIFs must be imported via Video Layer…"; continue }
            do {
                let imported = try await NativeImageAssetLoader.load(url)
                let filename = project.uniqueAssetName(imported.filename, defaultExtension: "png")
                project.setAsset(imported.data, named: filename)
                let imageWidth = Double(imported.image.size.width), imageHeight = Double(imported.image.size.height)
                let scale = min(1, min(project.width / max(imageWidth, 1), project.height / max(imageHeight, 1)))
                let id = UUID()
                var layer = LayerModel(id: id, name: nextName(url.deletingPathExtension().lastPathComponent.isEmpty ? "Image Layer" : url.deletingPathExtension().lastPathComponent), kind: .image, position: insertionPosition(), size: .init(width: imageWidth * scale, height: imageHeight * scale))
                layer.imageName = filename; layer.contentMode = "fill"; insert(layer)
            } catch { uploadStatus = "Failed to import \(url.lastPathComponent)" }
        }
    }

    private func insertionPosition() -> Vector2 {
        let parent = selectedID.flatMap { project.root.find(id: $0) }
        return .init(x: (parent?.size.width ?? project.width) / 2, y: (parent?.size.height ?? project.height) / 2)
    }

    private func insert(_ layer: LayerModel) {
        if let selectedID, project.root.find(id: selectedID)?.kind != .emitter { project.root.update(id: selectedID) { $0.children.append(layer) } }
        else { project.root.children.append(layer) }
        selectedID = layer.id
    }

    private func nextName(_ base: String) -> String {
        let names = Set(project.root.flattened().map(\.name)); guard names.contains(base) else { return base }
        var index = 2; while names.contains("\(base) \(index)") { index += 1 }; return "\(base) \(index)"
    }
}

@MainActor
enum NativeImageAssetLoader {
    struct Imported { let data: Data; let image: UIImage; let filename: String }
    static let allowedTypes: [UTType] = [.png, .jpeg, UTType(filenameExtension: "webp")!, UTType(filenameExtension: "bmp")!, UTType(filenameExtension: "svg")!]

    static func load(_ url: URL) async throws -> Imported {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "svg" || UTType(filenameExtension: url.pathExtension)?.conforms(to: UTType(filenameExtension: "svg")!) == true {
            let raster = try await rasterizeSVG(data)
            guard let image = UIImage(data: raster) else { throw CocoaError(.fileReadCorruptFile) }
            let base = url.deletingPathExtension().lastPathComponent.isEmpty ? "Image" : url.deletingPathExtension().lastPathComponent
            return .init(data: raster, image: image, filename: "\(base).png")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        return .init(data: data, image: image, filename: url.lastPathComponent.isEmpty ? "Image.png" : url.lastPathComponent)
    }

    private static func rasterizeSVG(_ data: Data) async throws -> Data {
        guard let svg = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        let escaped = svg.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive)
        web.loadHTMLString("<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head><body style='margin:0;background:transparent;display:inline-block'>\(escaped)</body></html>", baseURL: nil)
        for _ in 0..<100 {
            if !web.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let raw = try await web.evaluateJavaScript("(()=>{const e=document.querySelector('svg'); if(!e)return {w:512,h:512}; const r=e.getBoundingClientRect(); const vb=e.viewBox&&e.viewBox.baseVal; return {w:r.width||vb.width||512,h:r.height||vb.height||512};})()")
        let dict = raw as? [String: Any]
        let sourceW = (dict?["w"] as? NSNumber)?.doubleValue ?? 512, sourceH = (dict?["h"] as? NSNumber)?.doubleValue ?? 512
        let scale = min(1, 4096 / max(sourceW, sourceH, 1))
        let width = max(1, sourceW * scale), height = max(1, sourceH * scale)
        web.frame = CGRect(x: 0, y: 0, width: width, height: height)
        web.scrollView.contentSize = web.frame.size
        let configuration = WKSnapshotConfiguration(); configuration.rect = web.bounds
        let image = try await web.takeSnapshot(configuration: configuration)
        guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return png
    }
}

enum LayerReorderAction { case front, forward, backward, back }

extension LayerModel {
    func flattened() -> [LayerModel] { [self] + children.flatMap { $0.flattened() } }
    func contains(id: UUID) -> Bool { self.id == id || children.contains { $0.contains(id: id) } }

    mutating func duplicate(id: UUID) -> UUID? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            var copy = children[index]; copy.refreshIDs(); copy.name += " Copy"; children.insert(copy, at: index + 1); return copy.id
        }
        for index in children.indices { if let duplicated = children[index].duplicate(id: id) { return duplicated } }
        return nil
    }

    mutating func reorder(id: UUID, action: LayerReorderAction) {
        if let index = children.firstIndex(where: { $0.id == id }) {
            switch action {
            case .front: children.append(children.remove(at: index))
            case .forward where index < children.count - 1: children.swapAt(index, index + 1)
            case .backward where index > 0: children.swapAt(index, index - 1)
            case .back: children.insert(children.remove(at: index), at: 0)
            default: break
            }
            return
        }
        for index in children.indices { children[index].reorder(id: id, action: action) }
    }

    mutating func removeReturning(id: UUID) -> LayerModel? {
        if let index = children.firstIndex(where: { $0.id == id }) { return children.remove(at: index) }
        for index in children.indices { if let result = children[index].removeReturning(id: id) { return result } }
        return nil
    }

    mutating func insert(_ moving: LayerModel, relativeTo target: UUID, position: LayerPanel.DropPosition) {
        if let index = children.firstIndex(where: { $0.id == target }) {
            switch position {
            case .before: children.insert(moving, at: index)
            case .after: children.insert(moving, at: index + 1)
            case .into: children[index].children.append(moving)
            }
            return
        }
        for index in children.indices {
            if children[index].contains(id: target) { children[index].insert(moving, relativeTo: target, position: position); return }
        }
    }

    private mutating func refreshIDs() { id = UUID(); for index in children.indices { children[index].refreshIDs() } }
}
