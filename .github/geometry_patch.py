from pathlib import Path
import re

path = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = path.read_text()

anchor = '''    @State private var emitterImageImporterOpen = false
    @State private var emitterImageTargetID: UUID?
'''
props = '''    @State private var emitterImageImporterOpen = false
    @State private var emitterImageTargetID: UUID?
    @AppStorage("caplay_settings_show_geometry_resize") private var showGeometryResize = false
    @AppStorage("caplay_settings_show_align_buttons") private var showAlignButtons = false
    @AppStorage("caplay_settings_align_target") private var alignTarget = "parent"
    @State private var geometryResizePercentage = 10.0
    @State private var geometryUseCustomAnchor = false
    @State private var geometryAnchorLayerID: UUID?
'''
if s.count(anchor) != 1:
    raise SystemExit(f'property anchor count={s.count(anchor)}')
s = s.replace(anchor, props, 1)

pattern = re.compile(r'''    @ViewBuilder private func geometry\(_ layer: LayerModel\) -> some View \{.*?\n    \}\n\n    @ViewBuilder private func compositing''', re.S)
replacement = r'''    @ViewBuilder private func geometry(_ layer: LayerModel) -> some View {
        let inState = project.activeState != "Base State"
        let lockX = geometryAnimationLocked(layer, keys: ["position", "position.x"])
        let lockY = geometryAnimationLocked(layer, keys: ["position", "position.y"])
        let lockZ = geometryAnimationLocked(layer, keys: ["zPosition"])
        let lockRX = geometryAnimationLocked(layer, keys: ["transform.rotation.x"])
        let lockRY = geometryAnimationLocked(layer, keys: ["transform.rotation.y"])
        let lockRZ = geometryAnimationLocked(layer, keys: ["transform.rotation.z", "rotation"])

        VStack(alignment: .leading, spacing: 14) {
            if lockX || lockY || lockRX || lockRY || lockRZ {
                Text("Position and rotation fields are disabled because this layer has keyframe animations enabled. The values shown update live during playback.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
            }

            HStack(spacing: 8) {
                geometryField("X", layer.position.x, \.position.x, disabled: lockX)
                geometryField("Y", layer.position.y, \.position.y, disabled: lockY)
            }
            geometryField("Z", layer.zPosition, \.zPosition, disabled: lockZ)

            if showAlignButtons {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Align").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("Align target", selection: $alignTarget) {
                            Text("To Canvas").tag("root")
                            Text("To Parent").tag("parent")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    HStack(spacing: 5) {
                        geometryAlignButton("L", "Align left", disabled: lockX) { alignGeometry(layer, horizontal: .min, vertical: nil) }
                        geometryAlignButton("C", "Align horizontal center", disabled: lockX) { alignGeometry(layer, horizontal: .mid, vertical: nil) }
                        geometryAlignButton("R", "Align right", disabled: lockX) { alignGeometry(layer, horizontal: .max, vertical: nil) }
                        geometryAlignButton("T", "Align top", disabled: lockY) { alignGeometry(layer, horizontal: nil, vertical: .min) }
                        geometryAlignButton("M", "Align vertical center", disabled: lockY) { alignGeometry(layer, horizontal: nil, vertical: .mid) }
                        geometryAlignButton("B", "Align bottom", disabled: lockY) { alignGeometry(layer, horizontal: nil, vertical: .max) }
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 6) {
                    geometryField("Width", layer.size.width, \.size.width, disabled: layer.kind == .text && !(layer.wrapsText ?? true))
                    if showGeometryResize { geometryResizeControls(\.size.width, current: layer.size.width, disabled: layer.kind == .text && !(layer.wrapsText ?? true)) }
                }
                VStack(spacing: 6) {
                    geometryField("Height", layer.size.height, \.size.height, disabled: layer.kind == .text)
                    if showGeometryResize { geometryResizeControls(\.size.height, current: layer.size.height, disabled: layer.kind == .text) }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Scale").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Slider(value: value(\.scale, layer.scale), in: 0...4, step: 0.01)
                    TextField("Scale", value: geometryScalePercentBinding(layer), format: .number.precision(.fractionLength(0)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                    Text("%").font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rotation (deg)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    geometryRotationKnob("X", binding: value(\.rotationX, layer.rotationX), disabled: lockRX)
                    geometryRotationKnob("Y", binding: value(\.rotationY, layer.rotationY), disabled: lockRY)
                    geometryRotationKnob("Z", binding: value(\.rotation, layer.rotation), disabled: lockRZ)
                }
            }

            if layer.kind != .emitter {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anchor Point").font(.caption).foregroundStyle(.secondary)
                    if geometryUseCustomAnchor {
                        geometryAnchorSlider("X", keyPath: \.anchorPoint.x, value: layer.anchorPoint.x, disabled: inState)
                        geometryAnchorSlider("Y", keyPath: \.anchorPoint.y, value: layer.anchorPoint.y, disabled: inState)
                    } else {
                        VStack(spacing: 5) {
                            ForEach([1.0, 0.5, 0.0], id: \.self) { ay in
                                HStack(spacing: 5) {
                                    ForEach([0.0, 0.5, 1.0], id: \.self) { ax in
                                        Button {
                                            guard !inState else { return }
                                            update { $0.anchorPoint = .init(x: ax, y: ay) }
                                        } label: {
                                            Text("\(ax.formatted(.number.precision(.fractionLength(1)))),\(ay.formatted(.number.precision(.fractionLength(1))))")
                                                .font(.system(size: 9, design: .monospaced))
                                                .frame(maxWidth: .infinity, minHeight: 28)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(abs(layer.anchorPoint.x - ax) < 0.001 && abs(layer.anchorPoint.y - ay) < 0.001 ? CATheme.accent : nil)
                                        .disabled(inState)
                                    }
                                }
                            }
                        }
                    }
                    Toggle("Use custom anchor point", isOn: Binding(
                        get: { geometryUseCustomAnchor },
                        set: { enabled in
                            geometryUseCustomAnchor = enabled
                            guard !inState, !enabled else { return }
                            let standard = [0.0, 0.5, 1.0]
                            let x = standard.min(by: { abs($0 - layer.anchorPoint.x) < abs($1 - layer.anchorPoint.x) }) ?? 0.5
                            let y = standard.min(by: { abs($0 - layer.anchorPoint.y) < abs($1 - layer.anchorPoint.y) }) ?? 0.5
                            update { $0.anchorPoint = .init(x: x, y: y) }
                        }
                    ))
                    .font(.caption)
                    .disabled(inState)
                    if inState { Text("Not supported for state transitions").font(.caption2).foregroundStyle(.secondary) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Flip Geometry", isOn: value(\.geometryFlipped, layer.geometryFlipped))
                    .disabled(inState)
                Text(inState ? "Not supported for state transitions" : "Affects this layer's sublayers' coordinate system.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if layer.kind == .transform || layer.kind == .replicator {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Perspective") {
                        TextField("Perspective", value: Binding(
                            get: { selectedID.flatMap { project.root.find(id: $0) }?.perspective ?? 0 },
                            set: { new in update { $0.perspective = new } }
                        ), format: .number.precision(.fractionLength(0)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                        .disabled(inState)
                    }
                    Text(inState ? "Not supported for state transitions" : "Controls how the layer is projected in 3D space.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { syncGeometryAnchorMode(layer) }
        .onChange(of: layer.id) { _, _ in syncGeometryAnchorMode(layer) }
    }

    private enum GeometryAxisAlignment { case min, mid, max }

    private func geometryAnimationLocked(_ layer: LayerModel, keys: Set<String>) -> Bool {
        layer.animations.contains { $0.enabled && keys.contains($0.keyPath) }
    }

    private func geometryField(_ title: String, _ fallback: Double, _ keyPath: WritableKeyPath<LayerModel, Double>, disabled: Bool = false) -> some View {
        LabeledContent(title) {
            TextField(title, value: value(keyPath, fallback), format: .number.precision(.fractionLength(2)))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
                .disabled(disabled)
        }
    }

    private func geometryScalePercentBinding(_ layer: LayerModel) -> Binding<Double> {
        let scale = value(\.scale, layer.scale)
        return Binding(get: { scale.wrappedValue * 100 }, set: { scale.wrappedValue = max(0, $0) / 100 })
    }

    private func geometryResizeControls(_ keyPath: WritableKeyPath<LayerModel, Double>, current: Double, disabled: Bool) -> some View {
        HStack(spacing: 4) {
            Button { resizeGeometry(keyPath, current: current, factor: max(0, 1 - geometryResizePercentage / 100)) } label: { Image(systemName: "minus").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.mini).disabled(disabled)
            TextField("%", value: $geometryResizePercentage, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 48).controlSize(.mini)
            Button { resizeGeometry(keyPath, current: current, factor: 1 + geometryResizePercentage / 100) } label: { Image(systemName: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.mini).disabled(disabled)
        }
    }

    private func resizeGeometry(_ keyPath: WritableKeyPath<LayerModel, Double>, current: Double, factor: Double) {
        let binding = value(keyPath, current)
        binding.wrappedValue = max(0, current * factor)
    }

    private func geometryAlignButton(_ text: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 26) }
            .buttonStyle(.bordered).controlSize(.small).disabled(disabled).accessibilityLabel(label)
    }

    private func alignGeometry(_ layer: LayerModel, horizontal: GeometryAxisAlignment?, vertical: GeometryAxisAlignment?) {
        guard let selectedID else { return }
        let target: LayerModel? = alignTarget == "parent" ? parentLayer(of: selectedID, in: project.root) : project.root
        let targetWidth = target?.size.width ?? project.width
        let targetHeight = target?.size.height ?? project.height
        var x = layer.position.x
        var y = layer.position.y
        if let horizontal {
            switch horizontal {
            case .min: x = layer.anchorPoint.x * layer.size.width
            case .mid: x = targetWidth / 2
            case .max: x = targetWidth - (1 - layer.anchorPoint.x) * layer.size.width
            }
        }
        if let vertical {
            switch vertical {
            case .min: y = layer.anchorPoint.y * layer.size.height
            case .mid: y = targetHeight / 2
            case .max: y = targetHeight - (1 - layer.anchorPoint.y) * layer.size.height
            }
        }
        project.updateStateAware(targetID: selectedID, values: ["position.x": x, "position.y": y]) { value in
            value.position = .init(x: x, y: y)
        }
    }

    private func parentLayer(of id: UUID, in root: LayerModel) -> LayerModel? {
        for child in root.children {
            if child.id == id { return root }
            if let found = parentLayer(of: id, in: child) { return found }
        }
        return nil
    }

    private func geometryRotationKnob(_ label: String, binding: Binding<Double>, disabled: Bool) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08))
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                Capsule().fill(disabled ? Color.secondary : CATheme.accent).frame(width: 2, height: 19).offset(y: -10)
                    .rotationEffect(.degrees(binding.wrappedValue))
            }
            .frame(width: 58, height: 58)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard !disabled else { return }
                let dx = gesture.location.x - 29
                let dy = gesture.location.y - 29
                var degrees = atan2(dx, -dy) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                binding.wrappedValue = degrees.rounded()
            })
            Text(label).font(.caption.bold())
            TextField(label, value: binding, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 64).disabled(disabled)
        }
        .frame(maxWidth: .infinity)
        .opacity(disabled ? 0.55 : 1)
    }

    private func geometryAnchorSlider(_ label: String, keyPath: WritableKeyPath<LayerModel, Double>, value current: Double, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label) (\(Int((current * 100).rounded()))%)").font(.caption2)
            Slider(value: Binding(
                get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? current },
                set: { new in update { $0[keyPath: keyPath] = new } }
            ), in: 0...1, step: 0.01)
            .disabled(disabled)
        }
    }

    private func syncGeometryAnchorMode(_ layer: LayerModel) {
        guard geometryAnchorLayerID != layer.id else { return }
        geometryAnchorLayerID = layer.id
        let standard = [0.0, 0.5, 1.0]
        geometryUseCustomAnchor = !standard.contains(where: { abs($0 - layer.anchorPoint.x) < 0.001 }) || !standard.contains(where: { abs($0 - layer.anchorPoint.y) < 0.001 })
    }

    @ViewBuilder private func compositing'''

s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'geometry replacement count={count}')
path.write_text(s2)
Path('.github/geometry_patch.py').unlink()
Path('.github/workflows/geometry-parity.yml').unlink()
