import SwiftUI

struct EditorView: View {
    enum CompactPage: String, CaseIterable { case canvas = "Canvas", panels = "Panels" }

    @Environment(ProjectStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var project: CAProjectDocument
    @State private var selectedID: UUID?
    @State private var compactPage: CompactPage = .canvas
    @State private var showLayers = true
    @State private var showInspector = true
    @State private var showExport = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false

    init(initialProject: CAProjectDocument) { _project = State(initialValue: initialProject) }

    var body: some View {
        VStack(spacing: 0) {
            menuBar
            GeometryReader { proxy in
                Group {
                    if proxy.size.width < 700 || horizontalSizeClass == .compact {
                        compactLayout
                    } else {
                        regularLayout(width: proxy.size.width)
                    }
                }
                .background(CATheme.background(scheme))
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showExport) { ExportView(project: project) }
        .onChange(of: project) { oldValue, newValue in scheduleSave(oldValue: oldValue, newValue: newValue) }
        .onDisappear { store.update(project) }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            if compactPage == .canvas {
                canvas.padding(12)
            } else {
                TabView {
                    LayerPanel(project: $project, selectedID: $selectedID)
                        .tabItem { Label("Layers", systemImage: "square.3.layers.3d") }
                    StatePanel(project: $project)
                        .tabItem { Label("States", systemImage: "circle.grid.2x2") }
                    InspectorView(project: $project, selectedID: $selectedID)
                        .tabItem { Label("Inspector", systemImage: "slider.horizontal.3") }
                }
            }
            HStack(spacing: 8) {
                Button {
                    compactPage = compactPage == .canvas ? .panels : .canvas
                } label: {
                    Label(compactPage == .canvas ? "Panels" : "Canvas",
                          systemImage: compactPage == .canvas ? "chevron.up" : "chevron.down")
                }.buttonStyle(.bordered)
                activeCAMenu
                AddLayerMenu(project: $project, selectedID: $selectedID)
                    .frame(width: 40, height: 40).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                Menu {
                    Button("Base State") { project.activeState = "Base State" }
                    ForEach(project.states, id: \.self) { state in Button(state) { project.activeState = state } }
                } label: {
                    Image(systemName: "circle.circle").frame(width: 40, height: 40)
                }.overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity).background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func regularLayout(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            if showLayers {
                VStack(spacing: 8) {
                    LayerPanel(project: $project, selectedID: $selectedID)
                    StatePanel(project: $project).frame(height: 260)
                }
                .frame(width: min(max(width * 0.24, 260), 360))
            }
            canvas
            if showInspector {
                InspectorView(project: $project, selectedID: $selectedID)
                    .frame(width: min(max(width * 0.28, 300), 420))
            }
        }
        .padding(12)
    }

    private var canvas: some View {
        EditorCanvasRepresentable(project: $project, selectedID: $selectedID)
            .clipShape(RoundedRectangle(cornerRadius: CATheme.radius, style: .continuous))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Label(project.activeState, systemImage: "circle.fill")
                    if let selected = project.root.find(id: selectedID ?? UUID()) {
                        Text(selected.name).foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
    }

    private var menuBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Back to projects", systemImage: "arrow.left") { store.update(project); dismiss() }
                Button("Rename", systemImage: "pencil") {}
                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(project); dismiss() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                    Text(project.name).lineLimit(1)
                }.frame(height: 32).padding(.horizontal, 8)
            }
            .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack(spacing: 0) {
                Button { undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 32, height: 32) }
                Button { undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 32, height: 32) }
            }.buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack(spacing: 6) {
                Circle().fill(saving ? .orange : .green).frame(width: 8, height: 8)
                Text(saving ? "Saving…" : "Saved").font(.caption).foregroundStyle(.secondary)
            }.accessibilityLabel(saving ? "Saving" : "Saved")
            Spacer()
            if horizontalSizeClass != .compact { activeCAMenu }
            Button { showLayers.toggle() } label: { Image(systemName: "sidebar.left").frame(width: 32, height: 32) }
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right").frame(width: 32, height: 32) }
            Button { showExport = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 32, height: 32) }
        }
        .buttonStyle(.plain).padding(.horizontal, 12).frame(height: 48)
        .background(.regularMaterial).overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var activeCAMenu: some View {
        if project.gyroEnabled {
            Text("Wallpaper").font(.subheadline).padding(.horizontal, 12).frame(height: 36)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator)).opacity(0.65)
        } else {
            Menu {
                Section("Choose Active CA") {
                    Button { project.activeCA = .background; selectedID = project.documents[.background]?.selectedID } label: {
                        Label("Background — Appears behind the clock.", systemImage: project.activeCA == .background ? "checkmark" : "square.3.layers.3d")
                    }
                    Button { project.activeCA = .floating; selectedID = project.documents[.floating]?.selectedID } label: {
                        Label("Floating — Appears over the clock.", systemImage: project.activeCA == .floating ? "checkmark" : "square.3.layers.3d")
                    }
                }
            } label: {
                HStack(spacing: 8) { Text(project.activeCA.title); Image(systemName: "arrow.up.arrow.down").foregroundStyle(.secondary) }
                    .font(.subheadline).padding(.horizontal, 12).frame(height: 36)
            }.overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    private func scheduleSave(oldValue: CAProjectDocument, newValue: CAProjectDocument) {
        undoManager?.registerUndo(withTarget: UndoBox { project = oldValue }) { $0.action() }
        saveTask?.cancel()
        saving = true
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            store.update(newValue)
            saving = false
        }
    }
}

private final class UndoBox: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
}
