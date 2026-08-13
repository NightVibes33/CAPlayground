from pathlib import Path
import re

path = Path('apps/ios/CAPlayground/Features/Editor/EditorView.swift')
s = path.read_text()

# Store measured target frames.
old = '''    @State private var settingsOpen = false
    @State private var onboardingOpen = false
    @State private var saveTask: Task<Void, Never>?
'''
new = '''    @State private var settingsOpen = false
    @State private var onboardingOpen = false
    @State private var onboardingFrames: [EditorTourTarget: CGRect] = [:]
    @State private var saveTask: Task<Void, Never>?
'''
if s.count(old) != 1:
    raise SystemExit(f'onboarding state anchor count={s.count(old)}')
s = s.replace(old, new, 1)

# Named coordinate space and frame collection.
old = '''        .navigationBarHidden(true)
        .sheet(isPresented: $showExport) { ExportView(project: project) }
'''
new = '''        .coordinateSpace(name: "editor-tour")
        .onPreferenceChange(EditorTourFramePreferenceKey.self) { onboardingFrames = $0 }
        .navigationBarHidden(true)
        .sheet(isPresented: $showExport) { ExportView(project: project) }
'''
if s.count(old) != 1:
    raise SystemExit(f'body modifier anchor count={s.count(old)}')
s = s.replace(old, new, 1)

# Regular layout target anchors.
replacements = [
    (
        '''                    LayerPanel(project: $project, selectedID: $selectedID)
                        .frame(maxHeight: .infinity)''',
        '''                    LayerPanel(project: $project, selectedID: $selectedID)
                        .editorTourTarget(.layers)
                        .frame(maxHeight: .infinity)'''
    ),
    (
        '''                    StatePanel(project: $project)
                        .frame(height: min(max(CGFloat(statesHeight), 120), 560))''',
        '''                    StatePanel(project: $project)
                        .editorTourTarget(.states)
                        .frame(height: min(max(CGFloat(statesHeight), 120), 560))'''
    ),
    (
        '''            canvas
                .padding(.horizontal, 4)''',
        '''            canvas
                .editorTourTarget(.canvas)
                .padding(.horizontal, 4)'''
    ),
    (
        '''                InspectorView(project: $project, selectedID: $selectedID)
                    .frame(width: min(max(CGFloat(rightWidth), 260), 560))''',
        '''                InspectorView(project: $project, selectedID: $selectedID)
                    .editorTourTarget(.inspector)
                    .frame(width: min(max(CGFloat(rightWidth), 260), 560))'''
    ),
]
for old, new in replacements:
    if s.count(old) != 1:
        raise SystemExit(f'regular target anchor count={s.count(old)}: {old[:60]!r}')
    s = s.replace(old, new, 1)

# Settings target.
old = '''            Button { settingsOpen = true } label: { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .accessibilityLabel("Settings")
'''
new = '''            Button { settingsOpen = true } label: { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                .buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .accessibilityLabel("Settings")
                .editorTourTarget(.settings)
'''
if s.count(old) != 1:
    raise SystemExit(f'settings target anchor count={s.count(old)}')
s = s.replace(old, new, 1)

# Pass frames into overlay.
old = '''        EditorOnboardingOverlay(isOpen: $onboardingOpen, showLeft: showLayers, showRight: showInspector) {
            onboardingSeen = true
        }
'''
new = '''        EditorOnboardingOverlay(
            isOpen: $onboardingOpen,
            showLeft: showLayers,
            showRight: showInspector,
            frames: onboardingFrames
        ) {
            onboardingSeen = true
        }
'''
if s.count(old) != 1:
    raise SystemExit(f'overlay call anchor count={s.count(old)}')
s = s.replace(old, new, 1)

# Close tour when panels are hidden, without marking it seen.
old = '''    private func toggleLeft() {
        showLayers.toggle()
        if autoClosePanels && showLayers && showInspector { showInspector = false }
    }

    private func toggleRight() {
        showInspector.toggle()
        if autoClosePanels && showInspector && showLayers { showLayers = false }
    }
'''
new = '''    private func toggleLeft() {
        showLayers.toggle()
        if autoClosePanels && showLayers && showInspector { showInspector = false }
        if onboardingOpen && (!showLayers || !showInspector) { onboardingOpen = false }
    }

    private func toggleRight() {
        showInspector.toggle()
        if autoClosePanels && showInspector && showLayers { showLayers = false }
        if onboardingOpen && (!showLayers || !showInspector) { onboardingOpen = false }
    }
'''
if s.count(old) != 1:
    raise SystemExit(f'toggle anchor count={s.count(old)}')
s = s.replace(old, new, 1)

# Replace generic modal overlay with measured target onboarding.
pattern = re.compile(r'''private struct EditorOnboardingOverlay: View \{.*?\n\}\n\nprivate final class UndoBox''', re.S)
replacement = r'''private enum EditorTourTarget: Hashable {
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

private final class UndoBox'''
s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'onboarding overlay replacement count={count}')
path.write_text(s2)
Path('.github/onboarding_parity_patch.py').unlink()
Path('.github/workflows/onboarding-parity.yml').unlink()
