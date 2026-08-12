import SwiftUI

struct StatePanel: View {
    @Binding var project: CAProjectDocument
    @State private var viewAllOpen = false

    private var current: AnimationDocument { project.documents[project.activeCA]! }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("States").font(.headline)
                Spacer()
                Button { viewAllOpen = true } label: { Label("View All", systemImage: "eye") }
                    .font(.caption).buttonStyle(.plain)
                if !project.gyroEnabled {
                    Menu {
                        Toggle("Light/Dark per state", isOn: Binding(
                            get: { current.appearanceSplit },
                            set: { toggleAppearanceSplit($0) }
                        ))
                        Text("Light/Dark per state will make wallpaper not usable on iOS 16")
                    } label: { Image(systemName: "gearshape").frame(width: 28, height: 28) }
                }
            }
            .padding(12)
            Divider()
            List(["Base State"] + project.states, id: \.self) { state in
                HStack {
                    Image(systemName: state == project.activeState ? "circle.inset.filled" : "circle")
                        .foregroundStyle(state == project.activeState ? CATheme.accent : .secondary)
                    Text(state)
                    Spacer()
                    Text("\(project.stateOverrides[state]?.count ?? 0)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .tag(state)
                .contentShape(Rectangle())
                .onTapGesture { project.activeState = state }
            }
            .listStyle(.plain)
        }
        .caPanel()
        .sheet(isPresented: $viewAllOpen) { stateOverview }
    }

    private var stateOverview: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Available States").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(["Base State"] + project.states, id: \.self) { state in
                                Text(state)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(state == project.activeState ? CATheme.accent : Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    let grouped = groupedOverrides()
                    if grouped.isEmpty {
                        ContentUnavailableView("No state transitions configured yet.", systemImage: "arrow.triangle.branch", description: Text("Select a state and modify layer properties to create transitions."))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("State Overrides by Layer").font(.headline)
                            ForEach(grouped.keys.sorted(by: { layerName($0) < layerName($1) }), id: \.self) { layerID in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(layerName(layerID)).font(.subheadline.weight(.semibold))
                                    ForEach(grouped[layerID]!.keys.sorted(), id: \.self) { state in
                                        Text(state).font(.caption.weight(.semibold))
                                        ForEach(Array(grouped[layerID]![state]!.enumerated()), id: \.offset) { _, override in
                                            HStack {
                                                Text(override.keyPath).font(.caption.monospaced()).padding(3).background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                                Image(systemName: "arrow.right")
                                                Text(display(override.value)).font(.caption.monospaced())
                                            }.foregroundStyle(.secondary)
                                        }
                                    }
                                }.padding(12).caPanel()
                            }
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("State Transitions Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { viewAllOpen = false } } }
        }
    }

    private func toggleAppearanceSplit(_ checked: Bool) {
        let base = ["Locked", "Unlock", "Sleep"]
        let light = base.map { "\($0) Light" }
        let dark = base.map { "\($0) Dark" }
        var document = current
        var overrides: [String: [StateOverride]] = [:]
        if checked {
            for index in base.indices {
                let values = document.stateOverrides[base[index]] ?? []
                overrides[light[index]] = document.stateOverrides[light[index]] ?? values
                overrides[dark[index]] = document.stateOverrides[dark[index]] ?? values
            }
            if document.activeState != "Base State", base.contains(document.activeState) {
                document.activeState += document.appearanceMode == "dark" ? " Dark" : " Light"
            }
            document.states = light + dark
        } else {
            let suffix = document.appearanceMode == "dark" ? "Dark" : "Light"
            for state in base { overrides[state] = document.stateOverrides["\(state) \(suffix)"] ?? document.stateOverrides[state] ?? [] }
            document.activeState = document.activeState.replacingOccurrences(of: #"\s(Light|Dark)$"#, with: "", options: .regularExpression)
            document.states = base
        }
        document.appearanceSplit = checked
        document.stateOverrides = overrides
        project.documents[project.activeCA] = document
    }

    private func groupedOverrides() -> [UUID: [String: [StateOverride]]] {
        var result: [UUID: [String: [StateOverride]]] = [:]
        for (state, values) in project.stateOverrides {
            for value in values { result[value.targetID, default: [:]][state, default: []].append(value) }
        }
        return result
    }

    private func layerName(_ id: UUID) -> String { project.root.find(id: id)?.name ?? "Unknown Layer" }
    private func display(_ value: OverrideValue) -> String { switch value { case .number(let number): number.formatted(); case .string(let string): string } }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: .init(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 320
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (.init(width: width, height: y + rowHeight), points)
    }
}
