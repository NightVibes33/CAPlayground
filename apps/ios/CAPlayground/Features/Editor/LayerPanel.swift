import SwiftUI

struct LayerPanel: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Button(selectMode ? "Done" : "Select") { selectMode.toggle() }
                    .font(.caption).buttonStyle(.plain)
                AddLayerMenu(project: $project, selectedID: $selectedID)
            }
            .padding(12)
            Divider()
            List(selection: $selectedID) {
                OutlineGroup(project.root.children.reversed(), children: \.outlineChildren) { layer in
                    HStack(spacing: 6) {
                        if selectMode { Image(systemName: multiSelected.contains(layer.id) ? "circle.inset.filled" : "circle").foregroundStyle(CATheme.accent) }
                        Text(layer.name)
                        Text("(\(layer.kind == .shape ? "basic" : layer.kind.rawValue))").foregroundStyle(.secondary)
                        Spacer()
                        Button { project.root.update(id: layer.id) { $0.isVisible.toggle() } } label: { Image(systemName: layer.isVisible ? "eye" : "eye.slash") }
                            .buttonStyle(.plain)
                    }
                        .tag(layer.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectMode {
                                if multiSelected.contains(layer.id) { multiSelected.remove(layer.id) } else { multiSelected.insert(layer.id) }
                            } else { selectedID = layer.id }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                project.root.remove(id: layer.id)
                                if selectedID == layer.id { selectedID = nil }
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
        .caPanel()
    }

    @State private var selectMode = false
    @State private var multiSelected: Set<UUID> = []
}

struct AddLayerMenu: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?

    var body: some View {
        Menu {
            ForEach(LayerKind.allCases) { kind in
                Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
            }
        } label: { Label("Add Layer", systemImage: "plus") }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Add Layer")
    }

    private func add(_ kind: LayerKind) {
        let id = UUID()
        var layer = LayerModel(
            id: id, name: kind.title, kind: kind,
            position: .init(x: project.width / 2, y: project.height / 2),
            size: .init(width: kind == .text ? 260 : 160, height: kind == .text ? 70 : 160)
        )
        switch kind {
        case .text:
            layer.text = "Text Layer"; layer.fontSize = 32; layer.textColor = "#FFFFFF"
        case .shape:
            layer.shape = "rounded-rect"; layer.fillColor = "#5AD197"; layer.cornerRadius = 24
        case .gradient:
            layer.gradientStops = [.init(color: "#6366F1", opacity: 1), .init(color: "#5AD197", opacity: 1)]
            layer.gradientStart = .init(x: 0, y: 0); layer.gradientEnd = .init(x: 1, y: 1)
        case .liquidGlass:
            layer.cornerRadius = 28
        case .emitter:
            layer.emitterPosition = .init(x: 80, y: 80)
        case .replicator:
            layer.instanceCount = 3; layer.instanceTranslationX = 18; layer.instanceDelay = 0.1
        default:
            layer.backgroundColor = kind == .basic ? "#5AD197" : nil
        }
        project.root.children.append(layer)
        selectedID = id
    }
}
