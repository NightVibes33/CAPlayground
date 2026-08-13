import SwiftUI

struct EditorView: View {
    enum CompactPage: String, CaseIterable { case canvas = "Canvas", panels = "Panels" }
    enum MobilePanelScreen: String, CaseIterable { case layersStates = "Layers/States", inspector = "Inspector" }

    @Environment(ProjectStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("caplay_panel_left_width") private var leftWidth = 320.0
    @AppStorage("caplay_panel_right_width") private var rightWidth = 400.0
    @AppStorage("caplay_panel_states_height") private var statesHeight = 350.0
    @AppStorage("caplay_settings_auto_close_panels") private var autoClosePanels = true
    @AppStorage("caplay_settings_ui_density") private var uiDensity = "default"
    @AppStorage("caplay_preview_show_background") private var showBackground = true
    @AppStorage("caplay_preview_edge_guide") private var showEdgeGuide = false
    @AppStorage("caplay_preview_clip") private var clipToCanvas = false
    @AppStorage("caplay_preview_anchor_point") private var showAnchorPoint = false
    @AppStorage("caplay_onboarding_seen") private var onboardingSeen = false

    @State private var project: CAProjectDocument
    @State private var selectedID: UUID?
    @State private var compactPage: CompactPage = .canvas
    @State private var mobilePanelScreen: MobilePanelScreen = .layersStates
    @State private var showLayers = true
    @State private var showInspector = false
    @State private var showExport = false
    @State private var settingsOpen = false
    @State private var onboardingOpen = false
    @State private var onboardingFrames: [EditorTourTarget: CGRect] = [:]
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false
    @State private var lastSavedAt: Date?
    @State private var renameOpen = false
    @State private var renameValue = ""
    @State private var deleteOpen = false
    @State private var showPreview = false
    @State private var useGyroControls = false
    @State private var gyroX = 0.0
    @State private var gyroY = 0.0
    @State private var canvasCommand: EditorCanvasCommand?
    @State private var timelinePlaying = false
    @State private var timelineTime = 0.0
    @State private var showTimeline = false
    @State private var timelineViewSeconds = 10.0

    init(initialProject: CAProjectDocument) { _project = State(initialValue: initialProject) }

    var body: some View {
        ZStack(alignment: .trailing) {
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
                    .onAppear {
                        if proxy.size.width >= 1250 { showLayers = true; showInspector = true }
                        else if autoClosePanels { showInspector = false }
                        if !onboardingSeen && proxy.size.width >= 1250 { onboardingOpen = true }
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        if autoClosePanels {
                            if width >= 1250 { showLayers = true; showInspector = true }
                            else if showLayers && showInspector { showInspector = false }
                        }
                    }
                }
            }
            if settingsOpen { settingsDrawer }
            if onboardingOpen { onboardingOverlay }
        }
        .coordinateSpace(name: "editor-tour")
        .onPreferenceChange(EditorTourFramePreferenceKey.self) { onboardingFrames = $0 }
        .navigationBarHidden(true)
        .sheet(isPresented: $showExport) { ExportView(project: project) }
        .sheet(isPresented: $renameOpen) { renameDialog }
        .confirmationDialog("Delete Project", isPresented: $deleteOpen, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(project); dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone. This will permanently delete the project and its editor data.")
        }
        .onChange(of: project) { oldValue, newValue in scheduleSave(oldValue: oldValue, newValue: newValue) }
        .onDisappear { store.update(project) }
        .task(id: timelinePlaying) { await runTimelineClock() }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            if compactPage == .canvas {
                canvas.padding(12).padding(.bottom, 64)
            } else {
                VStack(spacing: 8) {
                    Picker("Panel", selection: $mobilePanelScreen) {
                        ForEach(MobilePanelScreen.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    if mobilePanelScreen == .layersStates {
                        ScrollView {
                            VStack(spacing: 12) {
                                LayerPanel(project: $project, selectedID: $selectedID)
                                StatePanel(project: $project)
                            }
                            .padding(.horizontal, 12)
                        }
                    } else {
                        InspectorView(project: $project, selectedID: $selectedID)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 64)
            }
            mobileBottomBar
        }
    }

    private func regularLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if showLayers {
                VStack(spacing: 0) {
                    LayerPanel(project: $project, selectedID: $selectedID)
                        .editorTourTarget(.layers)
                        .frame(maxHeight: .infinity)
                    Rectangle().fill(Color.clear).frame(height: 8)
                    StatePanel(project: $project)
                        .editorTourTarget(.states)
                        .frame(height: min(max(CGFloat(statesHeight), 120), 560))
                }
                .frame(width: min(max(CGFloat(leftWidth), 240), 560))
                .padding(.trailing, 4)
            }
            canvas
                .editorTourTarget(.canvas)
                .padding(.horizontal, 4)
            if showInspector {
                InspectorView(project: $project, selectedID: $selectedID)
                    .editorTourTarget(.inspector)
                    .frame(width: min(max(CGFloat(rightWidth), 260), 560))
                    .padding(.leading, 4)
            }
        }
        .padding(12)
    }

    private var canvas: some View {
        ZStack {
            EditorCanvasRepresentable(
                project: $project,
                selectedID: $selectedID,
                showBackground: showBackground,
                showPreview: showPreview,
                showEdgeGuide: showEdgeGuide,
                clipToCanvas: clipToCanvas,
                showAnchorPoint: showAnchorPoint,
                gyroX: gyroX,
                gyroY: gyroY,
                timelineTime: timelineTime,
                timelinePlaying: timelinePlaying,
                command: canvasCommand
            )
            .clipShape(RoundedRectangle(cornerRadius: CATheme.radius, style: .continuous))

            VStack {
                HStack(alignment: .top) {
                    canvasPreviewControls
                    Spacer()
                    zoomControls
                }
                Spacer()
                if hasAnimatedContent && !showPreview { timelineControls }
            }
            .padding(10)

            VStack {
                HStack {
                    Label(project.activeState, systemImage: "circle.fill")
                    if let selected = selectedLayer { Text(selected.name).foregroundStyle(.secondary) }
                }
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .allowsHitTesting(false)

            if useGyroControls && project.activeCA == .wallpaper { gyroControlPanel }
        }
    }

    private var selectedLayer: LayerModel? { selectedID.flatMap { project.root.find(id: $0) } }

    private var hasAnimatedContent: Bool {
        project.root.flattened().contains { layer in
            layer.animations.contains(where: \.enabled) || layer.kind == .video || layer.kind == .emitter || (layer.kind == .replicator && (layer.instanceDelay ?? 0) > 0)
        }
    }

    private var canvasPreviewControls: some View {
        VStack(spacing: 8) {
            if project.activeCA == .wallpaper {
                canvasIconButton("view.3d", active: useGyroControls, label: "Gyro") {
                    useGyroControls.toggle()
                    if !useGyroControls { gyroX = 0; gyroY = 0 }
                }
            }
            canvasIconButton("iphone", active: showPreview, label: "Show Preview") {
                showPreview.toggle()
                if showPreview { timelinePlaying = true }
                else { timelinePlaying = false }
            }
            canvasIconButton("square", active: showEdgeGuide, label: "Edge guide") { showEdgeGuide.toggle() }
            canvasIconButton("crop", active: clipToCanvas, label: "Clip to canvas") { clipToCanvas.toggle() }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private var zoomControls: some View {
        VStack(spacing: 8) {
            canvasIconButton("plus", label: "Zoom in") { sendCanvas(.zoomIn) }
            canvasIconButton("minus", label: "Zoom out") { sendCanvas(.zoomOut) }
            canvasIconButton("scope", label: "Re-center") { sendCanvas(.resetZoom) }
        }
    }

    private func canvasIconButton(_ symbol: String, active: Bool = false, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 32, height: 32)
                .background(active ? CATheme.accent : CATheme.background(scheme).opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(active ? .white : .primary)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? CATheme.accent : CATheme.border(scheme)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var gyroControlPanel: some View {
        VStack(spacing: 10) {
            Text("Gyro").font(.caption.bold())
            HStack {
                Text("X").font(.caption2)
                Slider(value: $gyroX, in: -1...1)
                Text(gyroX.formatted(.number.precision(.fractionLength(2)))).font(.caption2.monospacedDigit()).frame(width: 36)
            }
            HStack {
                Text("Y").font(.caption2)
                Slider(value: $gyroY, in: -1...1)
                Text(gyroY.formatted(.number.precision(.fractionLength(2)))).font(.caption2.monospacedDigit()).frame(width: 36)
            }
            Button { gyroX = 0; gyroY = 0 } label: { Label("Re-center gyro", systemImage: "scope") }
                .font(.caption).buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(12)
    }

    private var timelineControls: some View {
        VStack(spacing: 6) {
            if showTimeline { timelinePanel }
            HStack(spacing: 8) {
                Button(timelinePlaying ? "Pause" : "Play") { timelinePlaying.toggle() }.buttonStyle(.borderedProminent).controlSize(.small)
                Button("Restart") { timelineTime = 0; sendCanvas(.restartTimeline) }.buttonStyle(.bordered).controlSize(.small)
                Button {
                    showTimeline.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text("\(timelineTime.formatted(.number.precision(.fractionLength(2))))s").font(.caption.monospacedDigit())
                        Image(systemName: showTimeline ? "chevron.down" : "chevron.up")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .frame(maxWidth: .infinity)
    }

    private var timelinePanel: some View {
    WebsiteTimelinePanel(
        project: $project,
        selectedID: $selectedID,
        currentTime: $timelineTime,
        viewSeconds: $timelineViewSeconds
    )
}

    private var animatedLayerRows: [(layer: LayerModel, depth: Int)] {
        func walk(_ layer: LayerModel, depth: Int) -> [(LayerModel, Int)] {
            let own = !layer.animations.isEmpty ? [(layer, depth)] : []
            return own + layer.children.flatMap { walk($0, depth: depth + 1) }
        }
        return project.root.children.flatMap { walk($0, depth: 0) }
    }

    private func timelineLayerRow(_ layer: LayerModel, depth: Int) -> some View {
        VStack(spacing: 2) {
            Button { selectedID = layer.id } label: {
                HStack(spacing: 4) {
                    Image(systemName: layer.children.isEmpty ? "circle.fill" : "chevron.down").font(.system(size: 8))
                    Text(layer.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth * 8))
                .frame(height: 24)
                .background(selectedID == layer.id ? CATheme.accent.opacity(0.18) : .clear)
            }
            .buttonStyle(.plain)
            ForEach(layer.animations) { animation in
                HStack(spacing: 6) {
                    Text(animation.keyPath).font(.system(size: 9)).lineLimit(1).frame(width: 110, alignment: .leading)
                    GeometryReader { geometry in
                        let effective = animation.duration / max(animation.speed, 0.0001)
                        let width = max(2, min(geometry.size.width, geometry.size.width * effective / timelineViewSeconds))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CATheme.accent.opacity(0.72))
                            .frame(width: width, height: 18)
                            .overlay(alignment: .leading) {
                                Text("\(animation.duration.formatted(.number.precision(.fractionLength(1))))s")
                                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(.white).padding(.leading, 4)
                            }
                            .gesture(DragGesture().onEnded { value in
                                let delta = Double(value.translation.width / max(geometry.size.width, 1)) * timelineViewSeconds * max(animation.speed, 0.0001)
                                updateAnimationDuration(layerID: layer.id, animationID: animation.id, duration: max(0.1, animation.duration + delta))
                            })
                    }
                    .frame(height: 20)
                }
                .padding(.leading, CGFloat(16 + depth * 8))
                .frame(height: 24)
            }
        }
    }

    private func updateAnimationDuration(layerID: UUID, animationID: UUID, duration: Double) {
        project.root.update(id: layerID) { layer in
            if let index = layer.animations.firstIndex(where: { $0.id == animationID }) { layer.animations[index].duration = (duration * 10).rounded() / 10 }
        }
    }

    private var menuBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Back to projects", systemImage: "arrow.left") { manualSave(); dismiss() }
                Button("Rename", systemImage: "pencil") { renameValue = project.name; renameOpen = true }
                Button("Delete", systemImage: "trash", role: .destructive) { deleteOpen = true }
            } label: {
                HStack(spacing: 8) { Image(systemName: "arrow.left"); Text(project.name).lineLimit(1) }
                    .frame(height: 32).padding(.horizontal, 8)
            }
            .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            HStack(spacing: 0) {
                Button { undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 32, height: 32) }
                    .keyboardShortcut("z", modifiers: .command)
                Button { undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 32, height: 32) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            Button { manualSave() } label: {
                HStack(spacing: 6) {
                    Circle().fill(saving ? .orange : .green).frame(width: 8, height: 8)
                    if horizontalSizeClass != .compact { Text(saving ? "Saving…" : "Saved").font(.caption) }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manual Save")
            .help(lastSavedAt.map { "Last saved \($0.formatted(date: .omitted, time: .standard)) — tap to save now" } ?? "Save now")

            Spacer()
            if horizontalSizeClass != .compact { activeCAMenu }

            HStack(spacing: 0) {
                Button { toggleLeft() } label: { Image(systemName: "sidebar.left").frame(width: 32, height: 32).opacity(showLayers ? 1 : 0.5) }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button { toggleRight() } label: { Image(systemName: "sidebar.right").frame(width: 32, height: 32).opacity(showInspector ? 1 : 0.5) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            Button {
                appearance = scheme == .dark ? "light" : "dark"
            } label: { Image(systemName: scheme == .dark ? "sun.max" : "moon").frame(width: 32, height: 32) }
            .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .accessibilityLabel("Toggle theme")

            Button { settingsOpen = true } label: { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .accessibilityLabel("Settings")
                .editorTourTarget(.settings)

            Button { showExport = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 32, height: 32) }
                .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Export")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var mobileBottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { mobileToggle; activeCAMenu; mobileAdd; mobileStates }
            HStack(spacing: 12) { mobileToggle; activeCAMenu; mobileAdd }
            HStack(spacing: 12) { mobileToggle; activeCAMenu }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var mobileToggle: some View {
        Button {
            compactPage = compactPage == .canvas ? .panels : .canvas
        } label: {
            Label(compactPage == .canvas ? "Panels" : "Canvas", systemImage: compactPage == .canvas ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.bordered)
    }

    private var mobileAdd: some View {
        AddLayerMenu(project: $project, selectedID: $selectedID, mobileMode: true)
            .frame(width: 40, height: 40).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private var mobileStates: some View {
        Menu {
            Button("Base State") { project.activeState = "Base State" }
            ForEach(["Locked", "Unlock", "Sleep"].filter { project.states.contains($0) }, id: \.self) { state in
                Button(state) { project.activeState = state }
            }
        } label: { Image(systemName: "circle.circle").frame(width: 40, height: 40) }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .accessibilityLabel("States")
    }

    @ViewBuilder private var activeCAMenu: some View {
        if project.gyroEnabled {
            Text("Wallpaper").font(.subheadline).padding(.horizontal, 12).frame(height: 36)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator)).opacity(0.65)
        } else {
            Menu {
                Section("Choose Active CA") {
                    if project.activeCA == .floating { Toggle("Show background", isOn: $showBackground) }
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
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    private var settingsDrawer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { settingsOpen = false }
                EditorSettingsPanel(
                    isOpen: $settingsOpen,
                    leftWidth: $leftWidth,
                    rightWidth: $rightWidth,
                    statesHeight: $statesHeight,
                    showLeft: showLayers,
                    showRight: showInspector,
                    showOnboarding: { settingsOpen = false; onboardingOpen = true }
                )
                .frame(width: min(geometry.size.width, geometry.size.width < 700 ? geometry.size.width : 600))
                .frame(maxHeight: .infinity)
                .background(CATheme.background(scheme))
                .shadow(radius: 24)
            }
        }
        .transition(.opacity)
        .zIndex(50)
    }

    private var onboardingOverlay: some View {
        EditorOnboardingOverlay(
            isOpen: $onboardingOpen,
            showLeft: showLayers,
            showRight: showInspector,
            frames: onboardingFrames
        ) {
            onboardingSeen = true
        }
        .zIndex(60)
    }

    private var renameDialog: some View {
        NavigationStack {
            Form {
                Section { TextField("Project name", text: $renameValue) }
                Section { Text("Update the name of your project.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Rename Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renameOpen = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        project.name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        renameOpen = false
                    }
                    .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(250)])
    }

    private func toggleLeft() {
        showLayers.toggle()
        if autoClosePanels && showLayers && showInspector { showInspector = false }
        if onboardingOpen && (!showLayers || !showInspector) { onboardingOpen = false }
    }

    private func toggleRight() {
        showInspector.toggle()
        if autoClosePanels && showInspector && showLayers { showLayers = false }
        if onboardingOpen && (!showLayers || !showInspector) { onboardingOpen = false }
    }

    private func manualSave() {
        saveTask?.cancel()
        store.update(project)
        saving = false
        lastSavedAt = .now
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
            lastSavedAt = .now
        }
    }

    private func sendCanvas(_ action: EditorCanvasAction) { canvasCommand = .init(action: action) }

    private func runTimelineClock() async {
        guard timelinePlaying else { return }
        while !Task.isCancelled && timelinePlaying {
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled || !timelinePlaying { return }
            timelineTime += 0.016
            if timelineTime >= 600 { timelineTime = 0 }
        }
    }
}

private struct EditorSettingsPanel: View {
    @Binding var isOpen: Bool
    @Binding var leftWidth: Double
    @Binding var rightWidth: Double
    @Binding var statesHeight: Double
    let showLeft: Bool
    let showRight: Bool
    let showOnboarding: () -> Void

    @AppStorage("caplay_settings_snap_edges") private var snapEdges = true
    @AppStorage("caplay_settings_snap_layers") private var snapLayers = true
    @AppStorage("caplay_settings_snap_resize") private var snapResize = true
    @AppStorage("caplay_settings_snap_rotation") private var snapRotation = true
    @AppStorage("caplay_settings_snap_threshold") private var snapThreshold = 12.0
    @AppStorage("caplay_preview_anchor_point") private var showAnchorPoint = false
    @AppStorage("caplay_settings_auto_close_panels") private var autoClosePanels = true
    @AppStorage("caplay_settings_pinch_zoom_sensitivity") private var pinchZoomSensitivity = 1.0
    @AppStorage("caplay_settings_show_geometry_resize") private var showGeometryResize = false
    @AppStorage("caplay_settings_show_align_buttons") private var showAlignButtons = false
    @AppStorage("caplay_settings_ui_density") private var uiDensity = "default"
    @AppStorage("caplay_settings_drag_sensitivity") private var dragSensitivity = 3.0
    @State private var latestVersion: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editor Settings").font(.headline)
                Spacer()
                Button { isOpen = false } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("Close settings")
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("Interface Density") {
                        HStack(spacing: 12) {
                            densityCard("Default", detail: "Standard spacing and sizes", value: "default")
                            densityCard("Compact", detail: "Maximizes screen real estate", value: "compact")
                        }
                    }
                    section("Snapping") {
                        Toggle("Snap to canvas edges", isOn: $snapEdges)
                        Toggle("Snap to other layers", isOn: $snapLayers)
                        Toggle("Snap when resizing", isOn: $snapResize)
                        Toggle("Snap rotation (0°, 90°, 180°, 270°)", isOn: $snapRotation)
                        sliderRow("Sensitivity", value: $snapThreshold, range: 3...25, step: 1, reset: 12)
                    }
                    section("Layer Controls") {
                        Toggle("Show geometry resize buttons", isOn: $showGeometryResize)
                        Toggle("Show align buttons", isOn: $showAlignButtons)
                        sliderRow("Drag-to-change sensitivity", value: $dragSensitivity, range: 0.5...10, step: 0.5, reset: 3)
                        Text("Adjusts how fast values change when dragging numeric fields in the inspector.").font(.caption2).foregroundStyle(.secondary)
                    }
                    section("Preview") {
                        Toggle("Show anchor point", isOn: $showAnchorPoint)
                        sliderRow("Pinch to zoom sensitivity", value: $pinchZoomSensitivity, range: 0.5...2, step: 0.1, reset: 1)
                    }
                    section("Keyboard Shortcuts") { keyboardShortcuts }
                    section("Panels") {
                        Toggle("Auto-close right panel on narrow screens", isOn: $autoClosePanels)
                        settingValue("Left panel width", "\(Int(leftWidth)) px")
                        settingValue("Right panel width", "\(Int(rightWidth)) px")
                        settingValue("States panel height", "\(Int(statesHeight)) px")
                        Button("Reset to defaults") { leftWidth = 320; rightWidth = 400; statesHeight = 350 }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                    Button("Show onboarding") { showOnboarding() }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        .disabled(!showLeft || !showRight)
                    Divider()
                    Text("Version: \(latestVersion ?? "...")").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
            }
        }
        .task { latestVersion = await fetchLatestVersion() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func densityCard(_ title: String, detail: String, value: String) -> some View {
        Button { uiDensity = value } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        HStack(spacing: value == "compact" ? 4 : 7) {
                            VStack(spacing: value == "compact" ? 3 : 6) {
                                ForEach(0..<(value == "compact" ? 5 : 3), id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.18)).frame(height: value == "compact" ? 6 : 10) }
                            }.frame(width: value == "compact" ? 34 : 50)
                            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08))
                        }.padding(value == "compact" ? 6 : 10)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(uiDensity == value ? CATheme.accent : Color.clear, lineWidth: 2))
                Text(title).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, reset: Double) -> some View {
        VStack(spacing: 8) {
            HStack { Text(title).font(.subheadline); Spacer(); Button("Reset") { value.wrappedValue = reset }.buttonStyle(.bordered).controlSize(.small) }
            Slider(value: value, in: range, step: step)
        }
    }

    private func settingValue(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Text(value).font(.caption.monospaced()).foregroundStyle(.secondary) }
    }

    private var keyboardShortcuts: some View {
        VStack(spacing: 7) {
            shortcut("Undo", "⌘ + Z"); shortcut("Redo", "⌘ + Shift + Z")
            shortcut("Zoom In", "⌘ + +"); shortcut("Zoom Out", "⌘ + -"); shortcut("Reset Zoom", "⌘ + 0")
            shortcut("Export", "⌘ + E"); shortcut("Pan", "Shift + Drag or Middle Click")
            shortcut("Toggle Left Panel", "⌘ + Shift + L"); shortcut("Toggle Right Panel", "⌘ + Shift + I")
            shortcut("Bring Forward", "⌘ + ]"); shortcut("Send Backward", "⌘ + [")
            shortcut("Bring to Front", "⌘ + Shift + ]"); shortcut("Send to Back", "⌘ + Shift + [")
            shortcut("Delete Layer", "Delete"); shortcut("Resize from Center", "Alt + Drag Handle"); shortcut("Maintain Aspect Ratio", "Shift + Drag Handle")
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Text(keys).font(.caption.monospaced()).foregroundStyle(.secondary) }
    }

    private func fetchLatestVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/CAPlayground/CAPlayground/tags?per_page=100") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let tags = try JSONDecoder().decode([Tag].self, from: data)
            return tags.first?.name
        } catch { return nil }
    }

    private struct Tag: Decodable { let name: String }
}

private enum EditorTourTarget: Hashable {
    case layers, states, canvas, inspector, settings
}

private struct EditorTourFramePreferenceKey: PreferenceKey {
    static var defaultValue: [EditorTourTarget: CGRect] = [:]
    static func reduce(value: inout [EditorTourTarget: CGRect], nextValue: () -> [EditorTourTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func editorTourTarget(_ target: EditorTourTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: EditorTourFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("editor-tour"))]
                )
            }
        }
    }
}

private struct EditorOnboardingOverlay: View {
    private enum Placement { case top, bottom, left, right }
    private struct Step {
        let target: EditorTourTarget
        let title: String
        let body: String
        let placement: Placement
    }

    @Binding var isOpen: Bool
    let showLeft: Bool
    let showRight: Bool
    let frames: [EditorTourTarget: CGRect]
    let finished: () -> Void
    @State private var index = 0

    private let allSteps: [Step] = [
        .init(target: .layers, title: "Layers", body: "Manage the layers in your wallpaper. Click a layer to select, duplicate or delete.", placement: .right),
        .init(target: .states, title: "States", body: "Switch between states of what the wallpaper is in, like when your phone is in Locked, Unlocked, or in Sleep state. You can make state transitions here.", placement: .right),
        .init(target: .canvas, title: "Canvas", body: "Drag, resize, and preview your layers. Use ⌘/+ / ⌘/- to zoom, Shift+Drag to pan.", placement: .bottom),
        .init(target: .inspector, title: "Inspector", body: "Edit geometry, compositing, content, text, images, and animations for the selected layer.", placement: .left),
        .init(target: .settings, title: "Settings", body: "Configure snapping behavior, see keyboard shortcuts, and reset this onboarding to view it again.", placement: .bottom)
    ]

    private var steps: [Step] {
        allSteps.filter { step in
            if step.target == .layers || step.target == .states { return showLeft }
            if step.target == .inspector { return showRight }
            return true
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let safeIndex = min(max(index, 0), max(steps.count - 1, 0))
            let step = steps[safeIndex]
            let target = frames[step.target]
            let tooltip = tooltipOrigin(for: target, placement: step.placement, size: geometry.size)

            ZStack(alignment: .topLeading) {
                if let target {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addRoundedRect(in: target.insetBy(dx: -4, dy: -4), cornerSize: CGSize(width: 6, height: 6))
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        .frame(width: target.width + 8, height: target.height + 8)
                        .offset(x: target.minX - 4, y: target.minY - 4)
                        .allowsHitTesting(false)
                } else {
                    Color.black.opacity(0.5).ignoresSafeArea()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(step.title).font(.subheadline.weight(.semibold))
                    Text(step.body).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Back") { index = max(0, index - 1) }
                            .buttonStyle(.bordered).controlSize(.small)
                        Spacer()
                        if safeIndex < steps.count - 1 {
                            Button("Skip") { finish() }
                                .buttonStyle(.borderless).controlSize(.small)
                        } else {
                            Link("Documentation", destination: URL(string: "https://docs.enkei64.xyz")!)
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        Button(safeIndex == steps.count - 1 ? "Done" : "Next") {
                            if safeIndex == steps.count - 1 { finish() }
                            else { index = min(steps.count - 1, index + 1) }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .padding(12)
                .frame(width: min(320, geometry.size.width - 16), alignment: .leading)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
                .shadow(radius: 16)
                .offset(x: tooltip.x, y: tooltip.y)
            }
        }
        .ignoresSafeArea()
        .onChange(of: showLeft) { _, visible in if !visible { isOpen = false } }
        .onChange(of: showRight) { _, visible in if !visible { isOpen = false } }
    }

    private func tooltipOrigin(for target: CGRect?, placement: Placement, size: CGSize) -> CGPoint {
        let pad: CGFloat = 8
        let width = min(320, size.width - 16)
        let estimatedHeight: CGFloat = 160
        guard let target else { return CGPoint(x: pad, y: pad) }
        var x: CGFloat
        var y: CGFloat
        switch placement {
        case .bottom:
            x = target.minX
            y = target.maxY + pad
        case .top:
            x = target.minX
            y = target.minY - estimatedHeight - pad
        case .left:
            x = target.minX - width - pad
            y = target.minY
        case .right:
            x = target.maxX + pad
            y = target.minY
        }
        x = min(max(pad, x), max(pad, size.width - width - pad))
        y = min(max(pad, y), max(pad, size.height - estimatedHeight - pad))
        return CGPoint(x: x, y: y)
    }

    private func finish() {
        isOpen = false
        finished()
    }
}

private final class UndoBox: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
}
