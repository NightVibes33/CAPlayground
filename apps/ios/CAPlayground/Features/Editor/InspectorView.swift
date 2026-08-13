import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import ImageIO

struct InspectorView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case geometry = "Geometry", compositing = "Compositing", content = "Content"
        case text = "Text", gradient = "Gradient", image = "Image", video = "Video"
        case animations = "Animations", gyro = "Gyro (Parallax)", emitter = "Emitter"
        case replicator = "Replicator", filters = "Filters"
        var id: String { rawValue }
        var symbol: String { switch self {
        case .geometry: "cube"; case .compositing: "square.3.layers.3d"; case .content: "paintpalette"
        case .text: "textformat"; case .gradient: "circle.lefthalf.filled"; case .image: "photo"
        case .video: "film"; case .animations: "play"; case .gyro: "iphone.gen3.radiowaves.left.and.right"
        case .emitter: "gearshape"; case .replicator: "square.on.square"; case .filters: "camera.filters"
        } }
    }

    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @State private var activeTab: Tab = .geometry
    @State private var imageImporterOpen = false
    @State private var imageCropOpen = false
    @State private var imageBlurOpen = false
    @State private var emitterImageImporterOpen = false
    @State private var emitterImageTargetID: UUID?
    @AppStorage("caplay_settings_show_geometry_resize") private var showGeometryResize = false
    @AppStorage("caplay_settings_show_align_buttons") private var showAlignButtons = false
    @AppStorage("caplay_settings_align_target") private var alignTarget = "parent"
    @State private var geometryResizePercentage = 10.0
    @State private var geometryUseCustomAnchor = false
    @State private var geometryAnchorLayerID: UUID?

    private var selected: LayerModel? { selectedID.flatMap { project.root.find(id: $0) } }
    private var tabs: [Tab] {
        guard let layer = selected else { return [] }
        if layer.id == project.root.id { return [.geometry] }
        if layer.kind == .emitter { return [.geometry, .compositing, .emitter] }
        if layer.kind == .replicator { return [.geometry, .compositing, .replicator, .animations, .filters] }
        var values: [Tab] = [.geometry, .compositing, .content]
        switch layer.kind {
        case .text: values.append(.text)
        case .gradient: values.append(.gradient)
        case .image: values.append(.image)
        case .video: values.append(.video)
        default: break
        }
        if layer.kind != .video { values.append(.animations) }
        if project.gyroEnabled && layer.kind == .transform { values.append(.gyro) }
        if layer.kind != .transform { values.append(.filters) }
        return values
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector").font(.headline)
                Spacer()
                if selected != nil { Button("Deselect") { selectedID = nil }.font(.caption) }
            }.padding(.horizontal, 12).frame(height: 44)
            Divider()
            if let layer = selected {
                HStack(spacing: 0) {
                    ScrollView(.vertical) {
                        VStack(spacing: 4) {
                            ForEach(tabs) { tab in
                                Button { activeTab = tab } label: {
                                    Image(systemName: tab.symbol).frame(width: 36, height: 36)
                                        .background(activeTab == tab ? CATheme.accent.opacity(0.2) : .clear)
                                        .foregroundStyle(activeTab == tab ? CATheme.accent : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain).accessibilityLabel(tab.rawValue)
                            }
                        }.padding(6)
                    }.frame(width: 50).overlay(alignment: .trailing) { Divider() }
                    ScrollView { tabContent(layer).padding(12) }
                }
                .onChange(of: layer.kind) { _, _ in if !tabs.contains(activeTab) { activeTab = tabs.first ?? .geometry } }
            } else {
                ContentUnavailableView("Select a layer to edit its properties.", systemImage: "square.slash")
            }
        }
        .caPanel()
        .fileImporter(isPresented: $imageImporterOpen, allowedContentTypes: NativeImageAssetLoader.allowedTypes, allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await importImage(url) }
        }
        .fileImporter(isPresented: $emitterImageImporterOpen, allowedContentTypes: NativeImageAssetLoader.allowedTypes, allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { emitterImageTargetID = nil; return }
            let target = emitterImageTargetID
            emitterImageTargetID = nil
            Task { await importEmitterCellImage(url, targetID: target) }
        }
        .sheet(isPresented: $imageCropOpen) {
            if let layer = selected, let preview = selectedImage(layer) {
                NativeImageCropSheet(image: preview) { crop, maintainBounds in
                    applyCrop(to: layer, crop: crop, maintainBounds: maintainBounds)
                }
            }
        }
        .sheet(isPresented: $imageBlurOpen) {
            if let layer = selected, let preview = selectedImage(layer) {
                NativeImageBlurSheet(image: preview) { amount in applyBlur(to: layer, amount: amount) }
            }
        }
    }

    @ViewBuilder private func tabContent(_ layer: LayerModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activeTab.rawValue).font(.headline)
            switch activeTab {
            case .geometry: geometry(layer)
            case .compositing: compositing(layer)
            case .content: content(layer)
            case .text: text(layer)
            case .gradient: gradient(layer)
            case .image: image(layer)
            case .video: video(layer)
            case .animations: animations(layer)
            case .gyro: gyro(layer)
            case .emitter: emitter(layer)
            case .replicator: replicator(layer)
            case .filters: filters(layer)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func geometry(_ layer: LayerModel) -> some View {
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

    @ViewBuilder private func compositing(_ layer: LayerModel) -> some View {
        let inState = project.activeState != "Base State"
        Picker("Blending", selection: optionalString(\.blendMode, layer.blendMode ?? "normalBlendMode")) {
            Text("Normal").tag("normalBlendMode"); Text("Color").tag("colorBlendMode"); Text("Color Burn").tag("colorBurnBlendMode"); Text("Color Dodge").tag("colorDodgeBlendMode")
            Text("Darken").tag("darkenBlendMode"); Text("Difference").tag("differenceBlendMode"); Text("Exclusion").tag("exclusionBlendMode"); Text("Hue").tag("hueBlendMode")
            Text("Lighten").tag("lightenBlendMode"); Text("Luminosity").tag("luminosityBlendMode"); Text("Multiply").tag("multiplyBlendMode"); Text("Overlay").tag("overlayBlendMode")
            Text("Saturation").tag("saturationBlendMode"); Text("Screen").tag("screenBlendMode")
        }
        VStack(alignment: .leading, spacing: 7) {
            Text("Opacity").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: value(\.opacity, layer.opacity), in: 0...1, step: 0.01)
                TextField("Opacity", value: opacityPercentBinding(layer), format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 68)
                Text("%").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text("Opacity affects the entire layer (content, background, and sublayers). If you only want to fade the background fill behind the content, use")
                Button("Content → Background opacity") { activeTab = .content }.buttonStyle(.plain)
                Text(".")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        geometryField("Corner Radius", layer.cornerRadius, \.cornerRadius)
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Clip contents", isOn: value(\.masksToBounds, layer.masksToBounds)).disabled(inState)
            Text("Masks this layer's sublayers to its bounds.").font(.caption2).foregroundStyle(.secondary)
            if inState { Text("Not supported for state transitions").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func opacityPercentBinding(_ layer: LayerModel) -> Binding<Double> {
        let opacity = value(\.opacity, layer.opacity)
        return Binding(get: { opacity.wrappedValue * 100 }, set: { opacity.wrappedValue = min(100, max(0, $0)) / 100 })
    }

    @ViewBuilder private func content(_ layer: LayerModel) -> some View {
        let inState = project.activeState != "Base State"
        if layer.kind != .gradient {
            colorField("Background colour", layer.backgroundColor ?? "#FFFFFF", \.backgroundColor)
            if inState { Text("(\(project.activeState))").font(.caption2).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 7) {
                Text("Background opacity").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Slider(value: backgroundOpacityBinding(layer), in: 0...1, step: 0.01).disabled(inState)
                    TextField("Background opacity", value: backgroundOpacityPercentBinding(layer), format: .number.precision(.fractionLength(0)))
                        .multilineTextAlignment(.trailing).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 68).disabled(inState)
                    Text("%").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Text("Background opacity affects only this layer's background color fill (behind the content). For overall layer opacity (affects images, text, and sublayers), use")
                    Button("Compositing → Opacity") { activeTab = .compositing }.buttonStyle(.plain)
                    Text(".")
                }
                .font(.caption2).foregroundStyle(.secondary)
                if inState { Text("Not supported for state transitions").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        ColorPicker("Border colour", selection: colorBinding(layer.borderColor ?? "#000000") { hex in update { $0.borderColor = hex } })
            .disabled(inState)
        LabeledContent("Border width") {
            TextField("Border width", value: borderWidthBinding(layer), format: .number.precision(.fractionLength(2)))
                .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120).disabled(inState)
        }
        if inState { Text("Border controls are not supported for state transitions").font(.caption2).foregroundStyle(.secondary) }
    }

    private func backgroundOpacityBinding(_ layer: LayerModel) -> Binding<Double> {
        Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?.backgroundOpacity ?? layer.backgroundOpacity }, set: { new in update { $0.backgroundOpacity = min(1, max(0, new)) } })
    }

    private func backgroundOpacityPercentBinding(_ layer: LayerModel) -> Binding<Double> {
        let opacity = backgroundOpacityBinding(layer)
        return Binding(get: { opacity.wrappedValue * 100 }, set: { opacity.wrappedValue = min(100, max(0, $0)) / 100 })
    }

    private func borderWidthBinding(_ layer: LayerModel) -> Binding<Double> {
        Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?.borderWidth ?? layer.borderWidth }, set: { new in update { $0.borderWidth = max(0, new) } })
    }

    @ViewBuilder private func text(_ layer: LayerModel) -> some View {
        let inState = project.activeState != "Base State"
        VStack(alignment: .leading, spacing: 12) {
            Text("Text").font(.caption).foregroundStyle(.secondary)
            TextField("Text", text: optionalString(\.text, layer.text ?? "")).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                LabeledContent("Font size") {
                    TextField("Font size", value: optionalDoubleBinding(\.fontSize, layer.fontSize ?? 32), format: .number)
                        .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120).disabled(inState)
                }
                ColorPicker("Color", selection: colorBinding(layer.textColor ?? "#FFFFFF") { hex in update { $0.textColor = hex } }).disabled(inState)
            }
            Picker("Font", selection: optionalString(\.fontFamily, layer.fontFamily ?? "SFProText-Regular")) {
                Text("System Default (SF Pro)").tag("SFProText-Regular"); Text("Times New Roman").tag("TimesNewRomanPSMT"); Text("Copperplate").tag("Copperplate"); Text("Courier New").tag("CourierNewPSMT"); Text("Futura").tag("Futura-Medium"); Text("Georgia").tag("Georgia"); Text("Papyrus").tag("Papyrus"); Text("Verdana").tag("Verdana")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Alignment").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    textAlignmentButton("text.alignleft", value: "left", current: layer.textAlignment ?? "center", disabled: inState, label: "Align left")
                    textAlignmentButton("text.aligncenter", value: "center", current: layer.textAlignment ?? "center", disabled: inState, label: "Align center")
                    textAlignmentButton("text.alignright", value: "right", current: layer.textAlignment ?? "center", disabled: inState, label: "Align right")
                    textAlignmentButton("text.justify", value: "justified", current: layer.textAlignment ?? "center", disabled: inState, label: "Justify")
                }
            }
            Toggle("Wrap lines", isOn: optionalBool(\.wrapsText, layer.wrapsText ?? true)).disabled(inState)
            Text("When on, drag horizontal bounds to wrap text.").font(.caption2).foregroundStyle(.secondary)
            if inState { Text("Font size, color, alignment, and wrapping are not supported for state transitions.").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func optionalDoubleBinding(_ keyPath: WritableKeyPath<LayerModel, Double?>, _ fallback: Double) -> Binding<Double> {
        Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } })
    }

    private func textAlignmentButton(_ symbol: String, value alignment: String, current: String, disabled: Bool, label: String) -> some View {
        Button { update { $0.textAlignment = alignment } } label: {
            Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 28)
                .background(current == alignment ? Color.secondary.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).disabled(disabled).accessibilityLabel(label)
    }

    @ViewBuilder private func gradient(_ layer: LayerModel) -> some View {
        Picker("Type", selection: optionalString(\.gradientType, layer.gradientType ?? "axial")) { Text("Axial (Linear)").tag("axial"); Text("Radial").tag("radial"); Text("Conic").tag("conic") }
        gradientPointPercentControl("Start Point X", keyPath: \.gradientStart, axis: .x, fallback: layer.gradientStart ?? .init(x: 0, y: 0))
        gradientPointPercentControl("Start Point Y", keyPath: \.gradientStart, axis: .y, fallback: layer.gradientStart ?? .init(x: 0, y: 0))
        gradientPointPercentControl("End Point X", keyPath: \.gradientEnd, axis: .x, fallback: layer.gradientEnd ?? .init(x: 1, y: 1))
        gradientPointPercentControl("End Point Y", keyPath: \.gradientEnd, axis: .y, fallback: layer.gradientEnd ?? .init(x: 1, y: 1))
        HStack { Text("Colors").font(.subheadline.weight(.medium)); Spacer(); Button("+ Add color") { update { ($0.gradientStops ?? []).isEmpty ? ($0.gradientStops = [.init(color: "#FFFFFF", opacity: 1)]) : ($0.gradientStops?.append(.init(color: "#FFFFFF", opacity: 1))) } }.buttonStyle(.bordered) }
        ForEach(Array((layer.gradientStops ?? []).enumerated()), id: \.offset) { index, stop in
            HStack(spacing: 8) {
                ColorPicker("", selection: colorBinding(stop.color) { hex in update { $0.gradientStops?[index].color = hex } }).labelsHidden().frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Slider(value: Binding(get: { stop.opacity }, set: { v in update { $0.gradientStops?[index].opacity = v } }), in: 0...1, step: 0.01)
                        Text("\(Int(((stop.opacity) * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary).frame(width: 36)
                    }
                }
                Button(role: .destructive) { update { $0.gradientStops?.remove(at: index) } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Remove color")
            }
            .padding(8).overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
        }
    }

    private enum GradientPointAxis: Equatable { case x, y }

    private func gradientPointPercentControl(_ title: String, keyPath: WritableKeyPath<LayerModel, Vector2?>, axis: GradientPointAxis, fallback: Vector2) -> some View {
        let binding = gradientPointPercentBinding(keyPath, axis: axis, fallback: fallback)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: binding, in: 0...100, step: 1)
                TextField(title, value: binding, format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 68)
                Text("%").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func gradientPointPercentBinding(_ keyPath: WritableKeyPath<LayerModel, Vector2?>, axis: GradientPointAxis, fallback: Vector2) -> Binding<Double> {
        Binding(get: {
            let point = selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback
            return (axis == .x ? point.x : point.y) * 100
        }, set: { percent in
            let normalized = min(100, max(0, percent)) / 100
            update { layer in
                var point = layer[keyPath: keyPath] ?? fallback
                if axis == .x { point.x = normalized } else { point.y = normalized }
                layer[keyPath: keyPath] = point
            }
        })
    }

    @ViewBuilder private func image(_ layer: LayerModel) -> some View {
        let inState = project.activeState != "Base State"
        let preview = selectedImage(layer)
        Text("Image").font(.caption).foregroundStyle(.secondary)
        if let preview {
            Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 200).frame(maxWidth: .infinity).padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        VStack(spacing: 8) {
            Button("Replace Image…") { imageImporterOpen = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(inState)
            Button("Reset Bounds") { resetImageBounds(layer) }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(preview == nil)
        }
        Divider()
        Text("Edit").font(.caption).foregroundStyle(.secondary)
        VStack(spacing: 8) {
            Button("Crop") { imageCropOpen = true }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(preview == nil || inState)
            Button("Blur") { imageBlurOpen = true }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(preview == nil || inState)
        }
        if inState { Text("Image replacement and destructive edits are not supported for state transitions.").font(.caption2).foregroundStyle(.secondary) }
    }

    @ViewBuilder private func video(_ layer: LayerModel) -> some View {
        let syncing = layer.syncWithState ?? false
        let frameCount = layer.frameCount ?? 0
        let fps = layer.framesPerSecond ?? 30
        let duration = layer.videoDuration ?? (Double(frameCount) / max(fps, 1))

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Video Properties").font(.subheadline.weight(.medium))
                Text("Frames: \(frameCount)")
                Text("FPS: \(fps.formatted(.number.precision(.fractionLength(0))))")
                Text("Duration: \(duration.formatted(.number.precision(.fractionLength(2))))s")
            }
            .font(.subheadline).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Picker("Calculation Mode", selection: optionalString(\.calculationMode, layer.calculationMode ?? "linear")) {
                    Text("Linear").tag("linear")
                    Text("Discrete").tag("discrete")
                }
                .disabled(syncing)
                Text("Linear blends frame values smoothly. Discrete jumps from one frame to the next with no interpolation.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Auto Reverses", isOn: optionalBool(\.autoReverses, layer.autoReverses ?? false))
                    .disabled(syncing)
                Text("When enabled, the video will play forward then backward in a loop.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Sync with state transition", isOn: videoSyncBinding(layer))
                    .disabled(frameCount <= 0 || layer.framePrefix == nil)
                Text("When enabled, the video will sync with state transitions.")
                    .font(.caption2).foregroundStyle(.secondary)

                if syncing {
                    ForEach(["Locked", "Unlock", "Sleep"], id: \.self) { state in
                        Picker("\(state) Frame", selection: videoStateFrameBinding(state, layer: layer)) {
                            Text("Beginning").tag("beginning")
                            Text("End").tag("end")
                        }
                    }
                }
            }
        }
    }

    private func videoSyncBinding(_ layer: LayerModel) -> Binding<Bool> {
        Binding(
            get: { selectedID.flatMap { project.root.find(id: $0) }?.syncWithState ?? layer.syncWithState ?? false },
            set: { enabled in setVideoStateSync(enabled, snapshot: layer) }
        )
    }

    private func setVideoStateSync(_ enabled: Bool, snapshot: LayerModel) {
        guard let selectedID, let current = project.root.find(id: selectedID) else { return }
        let oldFrameIDs = Set(current.children.map(\.id))
        removeVideoFrameOverrides(targetIDs: oldFrameIDs)

        guard enabled else {
            project.root.update(id: selectedID) { video in
                video.syncWithState = false
                video.children = []
                video.syncStateFrameMode = [:]
            }
            return
        }

        let count = current.frameCount ?? snapshot.frameCount ?? 0
        guard count > 0, let prefix = current.framePrefix ?? snapshot.framePrefix else { return }
        let rawExtension = current.frameExtension ?? snapshot.frameExtension ?? ".jpg"
        let ext = rawExtension.hasPrefix(".") ? rawExtension : ".\(rawExtension)"
        var children: [LayerModel] = []
        for index in 0..<count {
            var child = LayerModel(
                id: UUID(),
                name: "\(current.id.uuidString)_frame_\(index)",
                kind: .image,
                position: .init(x: current.size.width / 2, y: current.size.height / 2),
                size: current.size
            )
            child.imageName = "\(prefix)\(index)\(ext)"
            child.contentMode = "fill"
            child.zPosition = videoInitialZ(index)
            children.append(child)
        }
        let modes = ["Locked": "beginning", "Unlock": "end", "Sleep": "beginning"]
        project.root.update(id: selectedID) { video in
            video.syncWithState = true
            video.children = children
            video.syncStateFrameMode = modes
        }
        applyVideoFrameOverrides(children: children, modes: modes)
    }

    private func videoStateFrameBinding(_ state: String, layer: LayerModel) -> Binding<String> {
        Binding(
            get: {
                let current = selectedID.flatMap { project.root.find(id: $0) }
                let fallback = state == "Unlock" ? "end" : "beginning"
                return current?.syncStateFrameMode?[state] ?? layer.syncStateFrameMode?[state] ?? fallback
            },
            set: { mode in setVideoStateFrameMode(state: state, mode: mode) }
        )
    }

    private func setVideoStateFrameMode(state: String, mode: String) {
        guard let selectedID, let current = project.root.find(id: selectedID), current.syncWithState == true else { return }
        project.root.update(id: selectedID) { video in
            var modes = video.syncStateFrameMode ?? ["Locked": "beginning", "Unlock": "end", "Sleep": "beginning"]
            modes[state] = mode
            video.syncStateFrameMode = modes
        }
        applyVideoFrameOverrides(children: current.children, state: state, mode: mode)
    }

    private func removeVideoFrameOverrides(targetIDs: Set<UUID>) {
        guard !targetIDs.isEmpty else { return }
        var all = project.stateOverrides
        for state in Array(all.keys) {
            all[state]?.removeAll { targetIDs.contains($0.targetID) && $0.keyPath == "zPosition" }
        }
        project.stateOverrides = all
    }

    private func applyVideoFrameOverrides(children: [LayerModel], modes: [String: String]) {
        for state in ["Locked", "Unlock", "Sleep"] {
            let fallback = state == "Unlock" ? "end" : "beginning"
            applyVideoFrameOverrides(children: children, state: state, mode: modes[state] ?? fallback)
        }
    }

    private func applyVideoFrameOverrides(children: [LayerModel], state: String, mode: String) {
        let ids = Set(children.map(\.id))
        var all = project.stateOverrides
        var values = all[state] ?? []
        values.removeAll { ids.contains($0.targetID) && $0.keyPath == "zPosition" }
        let count = children.count
        for (index, child) in children.enumerated() {
            let z = mode == "end" ? videoFinalZ(index, count: count) : videoInitialZ(index)
            values.append(.init(targetID: child.id, keyPath: "zPosition", value: .number(z)))
        }
        all[state] = values
        project.stateOverrides = all
    }

    private func videoInitialZ(_ index: Int) -> Double {
        -Double(index * (index + 1)) / 2
    }

    private func videoFinalZ(_ index: Int, count: Int) -> Double {
        Double(index * (2 * count - 1 - index)) / 2
    }

    @ViewBuilder private func animations(_ layer: LayerModel) -> some View {
    AnimationInspectorPanel(project: $project, selectedID: $selectedID)
}

    @ViewBuilder private func gyro(_ layer: LayerModel) -> some View {
        let dictionaries = layer.gyroDictionaries ?? []
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Gyro Dictionaries").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("+ Add Dictionary") {
                        update { target in
                            var values = target.gyroDictionaries ?? []
                            guard values.count < 10 else { return }
                            values.append(.init(
                                id: UUID(), axis: "x", keyPath: "position.x", layerName: target.name,
                                mapMinTo: -50, mapMaxTo: 50, title: "New Gyro Effect", view: "Wallpaper"
                            ))
                            target.gyroDictionaries = values
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(dictionaries.count >= 10)
                }
                Text("Configure how this layer responds to device tilt. You can add up to 10 dictionaries (2 axes × 5 keyPaths) for this layer. (\(dictionaries.count)/10)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if dictionaries.isEmpty {
                Text("No gyro dictionaries yet. Click \"+ Add Dictionary\" to create one.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            } else {
                ForEach(dictionaries) { dictionary in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("e.g., Tilt Effect", text: gyroBinding(dictionary.id, \.title, dictionary.title))
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                update { $0.gyroDictionaries?.removeAll { $0.id == dictionary.id } }
                            } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove gyro dictionary")
                        }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Axis").font(.caption).foregroundStyle(.secondary)
                                Picker("Axis", selection: gyroBinding(dictionary.id, \.axis, dictionary.axis)) {
                                    Text("X (Left/Right)").tag("x")
                                    Text("Y (Up/Down)").tag("y")
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Key Path").font(.caption).foregroundStyle(.secondary)
                                Picker("Key Path", selection: gyroBinding(dictionary.id, \.keyPath, dictionary.keyPath)) {
                                    Text("position.x").tag("position.x")
                                    Text("position.y").tag("position.y")
                                    Text("transform.translation.x").tag("transform.translation.x")
                                    Text("transform.translation.y").tag("transform.translation.y")
                                    Text("transform.rotation.x").tag("transform.rotation.x")
                                    Text("transform.rotation.y").tag("transform.rotation.y")
                                    Text("transform.rotation.z").tag("transform.rotation.z")
                                    Text("anchorPoint.x").tag("anchorPoint.x")
                                    Text("anchorPoint.y").tag("anchorPoint.y")
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Map Min To").font(.caption).foregroundStyle(.secondary)
                                TextField("e.g., -50", value: gyroBinding(dictionary.id, \.mapMinTo, dictionary.mapMinTo), format: .number)
                                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                                Text("Min value (radians for rotation, px for position)").font(.caption2).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Map Max To").font(.caption).foregroundStyle(.secondary)
                                TextField("e.g., 50", value: gyroBinding(dictionary.id, \.mapMaxTo, dictionary.mapMaxTo), format: .number)
                                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                                Text("Max value (radians for rotation, px for position)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                }
            }
        }
    }

    @ViewBuilder private func emitter(_ layer: LayerModel) -> some View {
        let inState = project.activeState != "Base State"
        pointEditor("Emitter Position", keyPath: \.emitterPosition, point: layer.emitterPosition ?? .init(x: 0, y: 0)); sizeEditor("Emitter Size", keyPath: \.emitterSize, size: layer.emitterSize ?? .init(width: 1, height: 1))
        Picker("Render Mode", selection: optionalString(\.renderMode, layer.renderMode ?? "unordered")) { Text("unordered").tag("unordered"); Text("additive").tag("additive") }; Picker("Shape", selection: optionalString(\.emitterShape, layer.emitterShape ?? "point")) { Text("point").tag("point"); Text("line").tag("line"); Text("rectangle").tag("rectangle") }; Picker("Mode", selection: optionalString(\.emitterMode, layer.emitterMode ?? "volume")) { Text("volume").tag("volume"); Text("outline").tag("outline"); Text("surface").tag("surface") }
        VStack(alignment: .leading, spacing: 6) { HStack { Text("Speed").font(.caption).foregroundStyle(.secondary); Spacer(); Text(layer.speed.formatted(.number.precision(.fractionLength(2)))).monospacedDigit() }; Slider(value: value(\.speed, layer.speed), in: -2...2, step: 0.01).disabled(inState); HStack { ForEach([-2.0, -1, 0, 1, 2], id: \.self) { mark in Text(mark.formatted(.number.precision(.fractionLength(0)))).font(.caption2).foregroundStyle(.secondary); if mark != 2 { Spacer() } } } }
        HStack { Text("Cells").fontWeight(.medium); Spacer(); Button("+ Add Cell") { emitterImageTargetID = nil; emitterImageImporterOpen = true }.buttonStyle(.bordered).disabled(inState) }
        ForEach(Array((layer.emitterCells ?? []).enumerated()), id: \.element.id) { index, cell in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) { emitterCellThumbnail(cell); Button("Change Image") { emitterImageTargetID = cell.id; emitterImageImporterOpen = true }.buttonStyle(.bordered).disabled(inState) }
                    emitterSlider("Contents Scale", cell, \.contentsScale, range: 0...4, step: 0.01, disabled: inState); emitterField("Birth Rate", cell, \.birthRate, disabled: inState); emitterField("Lifetime", cell, \.lifetime, disabled: inState); emitterField("Lifetime Range", cell, \.lifetimeRange, disabled: inState); emitterField("Velocity", cell, \.velocity, disabled: inState); emitterField("Velocity Range", cell, \.velocityRange, disabled: inState)
                    emitterAngle("Emission Longitude", cell, \.emissionLongitude, disabled: inState); emitterAngle("Emission Latitude", cell, \.emissionLatitude, disabled: inState); emitterAngle("Emission Range", cell, \.emissionRange, disabled: inState); emitterAngle("Spin", cell, \.spin, disabled: inState); emitterAngle("Spin Range", cell, \.spinRange, disabled: inState)
                    emitterSlider("Scale", cell, \.scale, range: 0...4, step: 0.01, disabled: inState); emitterSlider("Scale Range", cell, \.scaleRange, range: 0...4, step: 0.01, disabled: inState); emitterSlider("Scale Speed", cell, \.scaleSpeed, range: -4...4, step: 0.01, disabled: inState); emitterSlider("Alpha", cell, \.alpha, range: 0...1, step: 0.01, disabled: inState); emitterSlider("Alpha Range", cell, \.alphaRange, range: -1...1, step: 0.01, disabled: inState); emitterSlider("Alpha Speed", cell, \.alphaSpeed, range: -1...1, step: 0.01, disabled: inState)
                    emitterField("X Acceleration", cell, \.xAcceleration, disabled: inState); emitterField("Y Acceleration", cell, \.yAcceleration, disabled: inState)
                    DisclosureGroup("Advanced Color Controls") { VStack(alignment: .leading, spacing: 12) { ColorPicker("Color", selection: emitterColorBinding(cell)).disabled(inState); emitterSlider("Red Range", cell, \.redRange, range: -1...1, step: 0.01, disabled: inState); emitterSlider("Red Speed", cell, \.redSpeed, range: -1...1, step: 0.01, disabled: inState); emitterSlider("Green Range", cell, \.greenRange, range: -1...1, step: 0.01, disabled: inState); emitterSlider("Green Speed", cell, \.greenSpeed, range: -1...1, step: 0.01, disabled: inState); emitterSlider("Blue Range", cell, \.blueRange, range: -1...1, step: 0.01, disabled: inState); emitterSlider("Blue Speed", cell, \.blueSpeed, range: -1...1, step: 0.01, disabled: inState) }.padding(.top, 8) }
                    Button("Remove Cell", role: .destructive) { update { $0.emitterCells?.removeAll { $0.id == cell.id } } }.disabled(inState)
                }.padding(.top, 8)
            } label: { HStack(spacing: 8) { emitterCellThumbnail(cell); Text("Cell \(index + 1)") } }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        if inState { Text("Emitter speed and cell controls are not supported for state transitions.").font(.caption2).foregroundStyle(.secondary) }
    }

    @ViewBuilder private func replicator(_ layer: LayerModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Instance Count").font(.caption).foregroundStyle(.secondary)
                TextField("Instance Count", value: replicatorCountBinding(layer), format: .number)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Text("Number of replicated instances (including the original layer)").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Instance Translation").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    replicatorNumberField("X (px)", \.instanceTranslationX, layer.instanceTranslationX ?? 0)
                    replicatorNumberField("Y (px)", \.instanceTranslationY, layer.instanceTranslationY ?? 0)
                    replicatorNumberField("Z (px)", \.instanceTranslationZ, layer.instanceTranslationZ ?? 0)
                }
                Text("Translation offset for each replicated instance").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Instance Rotation (Z axis, degrees)").font(.caption).foregroundStyle(.secondary)
                TextField("Instance Rotation", value: replicatorDoubleBinding(\.instanceRotation, fallback: layer.instanceRotation ?? 0), format: .number)
                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                Text("Rotation offset for each replicated instance").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Instance Delay (seconds)").font(.caption).foregroundStyle(.secondary)
                TextField("Instance Delay", value: replicatorDelayBinding(layer), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                Text("Delay between each instance appearing (for animations)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func replicatorCountBinding(_ layer: LayerModel) -> Binding<Int> {
        Binding(
            get: { selectedID.flatMap { project.root.find(id: $0) }?.instanceCount ?? layer.instanceCount ?? 1 },
            set: { new in update { $0.instanceCount = min(100, max(1, new)) } }
        )
    }

    private func replicatorDelayBinding(_ layer: LayerModel) -> Binding<Double> {
        Binding(
            get: { selectedID.flatMap { project.root.find(id: $0) }?.instanceDelay ?? layer.instanceDelay ?? 0 },
            set: { new in update { $0.instanceDelay = max(0, new) } }
        )
    }

    private func replicatorDoubleBinding(_ keyPath: WritableKeyPath<LayerModel, Double?>, fallback: Double) -> Binding<Double> {
        Binding(
            get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback },
            set: { new in update { $0[keyPath: keyPath] = new } }
        )
    }

    private func replicatorNumberField(_ title: String, _ keyPath: WritableKeyPath<LayerModel, Double?>, _ fallback: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, value: replicatorDoubleBinding(keyPath, fallback: fallback), format: .number)
                .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func filters(_ layer: LayerModel) -> some View {
        Menu("Add filter") {
            Button("Gaussian Blur") { addFilter(type: "gaussianBlur", value: 10) }
            Button("Contrast") { addFilter(type: "colorContrast", value: 1) }
            Button("Hue Rotate") { addFilter(type: "colorHueRotate", value: 0) }
            Button("Invert") { addFilter(type: "colorInvert", value: 0) }
            Button("Saturate") { addFilter(type: "colorSaturate", value: 0) }
            Button("Sepia") { addFilter(type: "CISepiaTone", value: 1) }
        }
        ForEach(layer.filters) { filter in
            VStack(alignment: .leading, spacing: 10) {
                Divider().padding(.vertical, 4)
                HStack(spacing: 8) {
                    Button {
                        let enabled = filterBinding(filter.id, \.enabled, filter.enabled)
                        enabled.wrappedValue.toggle()
                    } label: {
                        Image(systemName: filter.enabled ? "checkmark.square.fill" : "square")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enable filter")
                    Text(filterDisplayName(filter, in: layer.filters)).font(.caption)
                    Spacer()
                    Button(role: .destructive) { update { $0.filters.removeAll { $0.id == filter.id } } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderedProminent).controlSize(.mini).accessibilityLabel("Remove filter")
                }
                if filter.type == "colorHueRotate" {
                    filterHueKnob(binding: filterBinding(filter.id, \.value, filter.value))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                } else if filter.type != "colorInvert" {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(filterValueLabel(filter.type)).font(.caption).foregroundStyle(.secondary)
                        TextField(filterValueLabel(filter.type), value: filterBinding(filter.id, \.value, filter.value), format: .number)
                            .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private func addFilter(type: String, value: Double) {
        let count = selected?.filters.filter { $0.type == type }.count ?? 0
        let name = "\(filterName(type)) \(count + 1)"
        update { $0.filters.append(.init(type: type, name: name, value: value)) }
    }

    private func filterDisplayName(_ filter: FilterModel, in filters: [FilterModel]) -> String {
        if let name = filter.name, !name.isEmpty { return name }
        var occurrence = 0
        for item in filters where item.type == filter.type {
            occurrence += 1
            if item.id == filter.id { break }
        }
        return "\(filterName(filter.type)) \(max(occurrence, 1))"
    }

    private func filterHueKnob(binding: Binding<Double>) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08))
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                Capsule().fill(CATheme.accent).frame(width: 2, height: 22).offset(y: -12)
                    .rotationEffect(.degrees(binding.wrappedValue))
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let dx = gesture.location.x - 36
                let dy = gesture.location.y - 36
                binding.wrappedValue = (atan2(dx, -dy) * 180 / .pi).rounded()
            })
            Text("Angle").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField("Angle", value: binding, format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 64)
                Text("°").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func filterName(_ type: String) -> String { switch type { case "gaussianBlur": "Gaussian Blur"; case "colorContrast": "Contrast"; case "colorHueRotate": "Hue Rotate"; case "colorInvert": "Invert"; case "colorSaturate": "Saturate"; case "CISepiaTone": "Sepia"; default: type } }
    private func filterValueLabel(_ type: String) -> String { switch type { case "gaussianBlur": "Radius"; case "colorContrast", "colorSaturate": "Amount"; case "CISepiaTone": "Intensity"; case "colorHueRotate": "Angle"; default: "Value" } }

    private func update(_ mutation: (inout LayerModel) -> Void) {
        guard let selectedID else { return }
        project.root.update(id: selectedID, mutation: mutation)
    }

    @MainActor private func importImage(_ url: URL) async {
        do {
            let imported = try await NativeImageAssetLoader.load(url)
            let name = project.uniqueAssetName(imported.filename, defaultExtension: "png")
            project.setAsset(imported.data, named: name)
            update { $0.imageName = name }
        } catch { }
    }

    @MainActor private func importEmitterCellImage(_ url: URL, targetID: UUID?) async {
        do {
            let imported = try await NativeImageAssetLoader.load(url)
            let name = project.uniqueAssetName(imported.filename, defaultExtension: "png")
            project.setAsset(imported.data, named: name)
            update { layer in
                if let targetID, let index = layer.emitterCells?.firstIndex(where: { $0.id == targetID }) {
                    layer.emitterCells?[index].imageName = name
                } else {
                    var cells = layer.emitterCells ?? []
                    var cell = EmitterCellModel()
                    cell.imageName = name
                    cells.append(cell)
                    layer.emitterCells = cells
                }
            }
        } catch { }
    }

    private func selectedImage(_ layer: LayerModel) -> UIImage? {
        guard let name = layer.imageName, let data = project.assetData(named: name) else { return nil }
        return UIImage(data: data)
    }

    private func resetImageBounds(_ layer: LayerModel) {
        guard let image = selectedImage(layer) else { return }
        let width = Double(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let height = Double(image.cgImage?.height ?? Int(image.size.height * image.scale))
        updateSelectedSize(width: width, height: height)
    }

    private func updateSelectedSize(width: Double, height: Double) {
        guard let selectedID else { return }
        project.updateStateAware(
            targetID: selectedID,
            values: ["bounds.size.width": width, "bounds.size.height": height]
        ) { $0.size = .init(width: width, height: height) }
    }

    private func applyCrop(to layer: LayerModel, crop: CGRect, maintainBounds: Bool) {
        guard let image = selectedImage(layer), let source = image.cgImage else { return }
        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        let pixelRect = CGRect(
            x: crop.minX * sourceWidth,
            y: crop.minY * sourceHeight,
            width: crop.width * sourceWidth,
            height: crop.height * sourceHeight
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        guard pixelRect.width > 0, pixelRect.height > 0, let cropped = source.cropping(to: pixelRect) else { return }
        let edited = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        storeEditedImage(edited, originalName: layer.imageName ?? "image.png", suffix: "cropped")
        if !maintainBounds {
            updateSelectedSize(width: Double(cropped.width), height: Double(cropped.height))
        }
    }

    private func applyBlur(to layer: LayerModel, amount: Double) {
        guard let image = selectedImage(layer), let cgImage = image.cgImage else { return }
        let source = CIImage(cgImage: cgImage), filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(source, forKey: kCIInputImageKey); filter?.setValue(amount, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage?.cropped(to: source.extent), let rendered = CIContext(options: nil).createCGImage(output, from: source.extent) else { return }
        storeEditedImage(UIImage(cgImage: rendered), originalName: layer.imageName ?? "image.png", suffix: "blur")
    }

    private func storeEditedImage(_ image: UIImage, originalName: String, suffix: String) {
        guard let encoded = encodeEditedImage(image, preferredExtension: URL(fileURLWithPath: originalName).pathExtension) else { return }
        let originalBase = URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent
        let cleanBase = originalBase.replacingOccurrences(of: "-(cropped|blur)-[0-9]+$", with: "", options: .regularExpression)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let proposed = "\(cleanBase.isEmpty ? "image" : cleanBase)-\(suffix)-\(stamp).\(encoded.ext)"
        let name = project.uniqueAssetName(proposed, defaultExtension: encoded.ext)
        project.setAsset(encoded.data, named: name)
        update { $0.imageName = name }
    }

    private func encodeEditedImage(_ image: UIImage, preferredExtension: String) -> (data: Data, ext: String)? {
        guard let cgImage = image.cgImage else { return nil }
        let ext = preferredExtension.lowercased()
        let preferred: (UTType, String) = switch ext {
        case "jpg", "jpeg": (.jpeg, ext == "jpg" ? "jpg" : "jpeg")
        case "webp": (UTType(filenameExtension: "webp") ?? .png, "webp")
        case "bmp": (UTType(filenameExtension: "bmp") ?? .png, "bmp")
        default: (.png, "png")
        }
        if let data = encodeCGImage(cgImage, type: preferred.0, lossyQuality: preferred.0 == .jpeg ? 0.9 : nil) { return (data, preferred.1) }
        guard let fallback = encodeCGImage(cgImage, type: .png, lossyQuality: nil) else { return nil }
        return (fallback, "png")
    }

    private func encodeCGImage(_ image: CGImage, type: UTType, lossyQuality: Double?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let options: CFDictionary? = lossyQuality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    @ViewBuilder private func emitterCellThumbnail(_ cell: EmitterCellModel) -> some View { if let name = cell.imageName, let data = project.assetData(named: name), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 4)) } else { Image(systemName: "photo").frame(width: 24, height: 24).foregroundStyle(.secondary) } }
    private func emitterColorBinding(_ cell: EmitterCellModel) -> Binding<Color> { colorBinding(cell.color) { hex in update { layer in if let index = layer.emitterCells?.firstIndex(where: { $0.id == cell.id }) { layer.emitterCells?[index].color = hex } } } }
    private func emitterSlider(_ title: String, _ cell: EmitterCellModel, _ keyPath: WritableKeyPath<EmitterCellModel, Double>, range: ClosedRange<Double>, step: Double, disabled: Bool) -> some View { VStack(alignment: .leading, spacing: 6) { HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Text(cell[keyPath: keyPath].formatted(.number.precision(.fractionLength(2)))).monospacedDigit() }; Slider(value: emitterBinding(cell.id, keyPath, cell[keyPath: keyPath]), in: range, step: step).disabled(disabled) } }
    private func emitterAngle(_ title: String, _ cell: EmitterCellModel, _ keyPath: WritableKeyPath<EmitterCellModel, Double>, disabled: Bool) -> some View { VStack(alignment: .leading, spacing: 6) { HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(Int(cell[keyPath: keyPath].rounded()))°").monospacedDigit() }; Slider(value: emitterBinding(cell.id, keyPath, cell[keyPath: keyPath]), in: -360...360, step: 1).disabled(disabled) } }

    private func value<T>(_ keyPath: WritableKeyPath<LayerModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { if let selectedID, let stateKey = stateKey(for: keyPath), case .number(let number) = project.overrideValue(targetID: selectedID, keyPath: stateKey), let typed = number as? T { return typed }; return selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in if let selectedID, project.activeState != "Base State", let stateKey = stateKey(for: keyPath), let number = new as? Double { project.setOverride(targetID: selectedID, keyPath: stateKey, value: .number(number)) } else { update { $0[keyPath: keyPath] = new } } }) }
    private func optionalString(_ keyPath: WritableKeyPath<LayerModel, String?>, _ fallback: String) -> Binding<String> { Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }) }
    private func optionalBool(_ keyPath: WritableKeyPath<LayerModel, Bool?>, _ fallback: Bool) -> Binding<Bool> { Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }) }
    private func field(_ title: String, _ fallback: Double, _ keyPath: WritableKeyPath<LayerModel, Double>) -> some View { LabeledContent(title) { TextField(title, value: value(keyPath, fallback), format: .number).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func optionalField(_ title: String, _ fallback: Double, _ keyPath: WritableKeyPath<LayerModel, Double?>) -> some View { LabeledContent(title) { TextField(title, value: Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }), format: .number).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func optionalIntegerField(_ title: String, _ fallback: Int, _ keyPath: WritableKeyPath<LayerModel, Int?>) -> some View { LabeledContent(title) { TextField(title, value: Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }), format: .number).multilineTextAlignment(.trailing).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func colorField(_ title: String, _ fallback: String, _ keyPath: WritableKeyPath<LayerModel, String?>) -> some View { let displayed: String = { if let selectedID, keyPath == \.backgroundColor, case .string(let value) = project.overrideValue(targetID: selectedID, keyPath: "backgroundColor") { return value }; return selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }(); return ColorPicker(title, selection: colorBinding(displayed) { hex in if let selectedID, project.activeState != "Base State", keyPath == \.backgroundColor { project.setOverride(targetID: selectedID, keyPath: "backgroundColor", value: .string(hex)) } else { update { $0[keyPath: keyPath] = hex } } }) }
    private func colorBinding(_ hex: String, set: @escaping (String) -> Void) -> Binding<Color> { Binding(get: { Color(uiColor: UIColor(caHex: hex) ?? .white) }, set: { color in if let components = UIColor(color).cgColor.components, components.count >= 3 { set(String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))) } }) }
    private func pointEditor(_ title: String, keyPath: WritableKeyPath<LayerModel, Vector2?>, point: Vector2) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); HStack { TextField("X", value: Binding(get: { point.x }, set: { v in update { var p = $0[keyPath: keyPath] ?? point; p.x = v; $0[keyPath: keyPath] = p } }), format: .number).textFieldStyle(.roundedBorder); TextField("Y", value: Binding(get: { point.y }, set: { v in update { var p = $0[keyPath: keyPath] ?? point; p.y = v; $0[keyPath: keyPath] = p } }), format: .number).textFieldStyle(.roundedBorder) } } }
    private func sizeEditor(_ title: String, keyPath: WritableKeyPath<LayerModel, LayerSize?>, size: LayerSize) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); HStack { TextField("Width", value: Binding(get: { size.width }, set: { v in update { var s = $0[keyPath: keyPath] ?? size; s.width = v; $0[keyPath: keyPath] = s } }), format: .number).textFieldStyle(.roundedBorder); TextField("Height", value: Binding(get: { size.height }, set: { v in update { var s = $0[keyPath: keyPath] ?? size; s.height = v; $0[keyPath: keyPath] = s } }), format: .number).textFieldStyle(.roundedBorder) } } }
    private func animationBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<KeyframeAnimationModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selected?.animations.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { new in update { layer in if let i = layer.animations.firstIndex(where: { $0.id == id }) { layer.animations[i][keyPath: keyPath] = new } } }) }
    private func animationField(_ title: String, _ id: UUID, _ keyPath: WritableKeyPath<KeyframeAnimationModel, Double>, _ fallback: Double) -> some View { LabeledContent(title) { TextField(title, value: animationBinding(id, keyPath, fallback), format: .number).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func optionalAnimationField(_ title: String, _ id: UUID, _ keyPath: WritableKeyPath<KeyframeAnimationModel, Double?>, _ fallback: Double) -> some View { LabeledContent(title) { TextField(title, value: Binding(get: { selected?.animations.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { value in update { layer in if let index = layer.animations.firstIndex(where: { $0.id == id }) { layer.animations[index][keyPath: keyPath] = value } } }), format: .number).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func numericArrayBinding(_ id: UUID, _ keyPath: WritableKeyPath<KeyframeAnimationModel, [Double]>, _ fallback: [Double]) -> Binding<String> { Binding(get: { (selected?.animations.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback).map { $0.formatted() }.joined(separator: ", ") }, set: { text in let values = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }; update { layer in if let index = layer.animations.firstIndex(where: { $0.id == id }), !values.isEmpty { layer.animations[index][keyPath: keyPath] = values } } }) }
    private func animationValuePrompt(_ keyPath: String) -> String { switch keyPath { case "position": "Values: x,y; x,y"; case "bounds": "Values: width,height; width,height"; case "backgroundColor": "Values: #hex, #hex"; case "colors": "Frames: #hex|#hex; #hex|#hex"; default: "Values (comma separated)" } }
    private func animationValuesBinding(_ animation: KeyframeAnimationModel) -> Binding<String> { Binding(get: { let current = selected?.animations.first(where: { $0.id == animation.id }) ?? animation; return formatAnimationValues(current.values ?? current.numericValues.map(AnimationValue.number)) }, set: { text in guard let values = parseAnimationValues(text, keyPath: animation.keyPath), !values.isEmpty else { return }; update { layer in if let index = layer.animations.firstIndex(where: { $0.id == animation.id }) { layer.animations[index].values = values; layer.animations[index].numericValues = values.compactMap { if case .number(let value) = $0 { value } else { nil } } } } }) }
    private func formatAnimationValues(_ values: [AnimationValue]) -> String { let structured = values.contains { value in switch value { case .point, .size, .colors: true; default: false } }; return values.map { value in switch value { case .number(let number): number.formatted(); case .point(let point): "\(point.x.formatted()),\(point.y.formatted())"; case .size(let size): "\(size.width.formatted()),\(size.height.formatted())"; case .color(let color): color; case .colors(let stops): stops.map(\.color).joined(separator: "|") } }.joined(separator: structured ? "; " : ", ") }
    private func parseAnimationValues(_ text: String, keyPath: String) -> [AnimationValue]? { if keyPath == "position" || keyPath == "bounds" { return text.split(separator: ";").compactMap { pair in let numbers = pair.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }; guard numbers.count == 2 else { return nil }; return keyPath == "position" ? .point(.init(x: numbers[0], y: numbers[1])) : .size(.init(width: numbers[0], height: numbers[1])) } }; if keyPath == "backgroundColor" { return text.split(separator: ",").map { .color($0.trimmingCharacters(in: .whitespaces)) } }; if keyPath == "colors" { return text.split(separator: ";").map { frame in .colors(frame.split(separator: "|").map { .init(color: $0.trimmingCharacters(in: .whitespaces), opacity: 1) }) } }; let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }; return numbers.isEmpty ? nil : numbers.map(AnimationValue.number) }
    private func gyroBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<GyroDictionaryModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selected?.gyroDictionaries?.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { value in update { layer in if let index = layer.gyroDictionaries?.firstIndex(where: { $0.id == id }) { layer.gyroDictionaries?[index][keyPath: keyPath] = value } } }) }
    private func emitterBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<EmitterCellModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selected?.emitterCells?.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { value in update { layer in if let index = layer.emitterCells?.firstIndex(where: { $0.id == id }) { layer.emitterCells?[index][keyPath: keyPath] = value } } }) }
    private func emitterField(_ title: String, _ cell: EmitterCellModel, _ keyPath: WritableKeyPath<EmitterCellModel, Double>, disabled: Bool = false) -> some View { LabeledContent(title) { TextField(title, value: emitterBinding(cell.id, keyPath, cell[keyPath: keyPath]), format: .number).textFieldStyle(.roundedBorder).frame(maxWidth: 120).disabled(disabled) } }
    private func syncFrameBinding(_ state: String, _ fallback: String) -> Binding<String> { Binding(get: { selected?.syncStateFrameMode?[state] ?? fallback }, set: { value in update { var modes = $0.syncStateFrameMode ?? [:]; modes[state] = value; $0.syncStateFrameMode = modes } }) }
    private func filterBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<FilterModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selected?.filters.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { new in update { layer in if let i = layer.filters.firstIndex(where: { $0.id == id }) { layer.filters[i][keyPath: keyPath] = new } } }) }
    private func stateKey<T>(for keyPath: WritableKeyPath<LayerModel, T>) -> String? { let path = keyPath as AnyKeyPath; if path == \LayerModel.position.x { return "position.x" }; if path == \LayerModel.position.y { return "position.y" }; if path == \LayerModel.zPosition { return "zPosition" }; if path == \LayerModel.size.width { return "bounds.size.width" }; if path == \LayerModel.size.height { return "bounds.size.height" }; if path == \LayerModel.scale { return "transform.scale.xy" }; if path == \LayerModel.rotation { return "transform.rotation.z" }; if path == \LayerModel.rotationX { return "transform.rotation.x" }; if path == \LayerModel.rotationY { return "transform.rotation.y" }; if path == \LayerModel.opacity { return "opacity" }; if path == \LayerModel.cornerRadius { return "cornerRadius" }; return nil }
}

private struct NativeImageCropSheet: View {
    private enum DragMode { case move, nw, ne, sw, se }

    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onApply: (CGRect, Bool) -> Void
    @State private var x = 0.10
    @State private var y = 0.10
    @State private var width = 0.80
    @State private var height = 0.80
    @State private var maintainBounds = true
    @State private var dragMode: DragMode?
    @State private var dragStartCrop: CGRect?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Adjust the crop area and apply to replace the current image.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geo in
                    let fit = aspectFitRect(image: image, in: geo.size)
                    let cropRect = CGRect(
                        x: fit.minX + CGFloat(x) * fit.width,
                        y: fit.minY + CGFloat(y) * fit.height,
                        width: CGFloat(width) * fit.width,
                        height: CGFloat(height) * fit.height
                    )
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        Rectangle()
                            .fill(Color.black.opacity(0.20))
                            .overlay(Rectangle().stroke(Color.green, lineWidth: 2))
                            .frame(width: cropRect.width, height: cropRect.height)
                            .position(x: cropRect.midX, y: cropRect.midY)
                            .contentShape(Rectangle())
                            .gesture(cropGesture(.move, fit: fit))

                        cropHandle(.nw, at: CGPoint(x: cropRect.minX, y: cropRect.minY), fit: fit)
                        cropHandle(.ne, at: CGPoint(x: cropRect.maxX, y: cropRect.minY), fit: fit)
                        cropHandle(.sw, at: CGPoint(x: cropRect.minX, y: cropRect.maxY), fit: fit)
                        cropHandle(.se, at: CGPoint(x: cropRect.maxX, y: cropRect.maxY), fit: fit)
                    }
                }
                .frame(height: 340)
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Toggle("Maintain bounds after crop", isOn: $maintainBounds)
                        Spacer()
                        Text("Crop size: \(pixelSize.width) x \(pixelSize.height)px")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Maintain bounds after crop", isOn: $maintainBounds)
                        Text("Crop size: \(pixelSize.width) x \(pixelSize.height)px")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Apply crop") {
                        onApply(.init(x: x, y: y, width: width, height: height), maintainBounds)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .navigationTitle("Crop image")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cropHandle(_ mode: DragMode, at point: CGPoint, fit: CGRect) -> some View {
        Circle()
            .fill(Color.green)
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .frame(width: 12, height: 12)
            .position(point)
            .contentShape(Circle().inset(by: -10))
            .gesture(cropGesture(mode, fit: fit))
    }

    private func cropGesture(_ mode: DragMode, fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard fit.width > 0, fit.height > 0 else { return }
                if dragMode != mode || dragStartCrop == nil {
                    dragMode = mode
                    dragStartCrop = CGRect(x: x, y: y, width: width, height: height)
                }
                guard let base = dragStartCrop else { return }
                let dx = Double(value.translation.width / fit.width)
                let dy = Double(value.translation.height / fit.height)
                applyDrag(mode, base: base, dx: dx, dy: dy)
            }
            .onEnded { _ in
                dragMode = nil
                dragStartCrop = nil
            }
    }

    private func applyDrag(_ mode: DragMode, base: CGRect, dx: Double, dy: Double) {
        let minSize = 0.05
        var nextX = Double(base.minX)
        var nextY = Double(base.minY)
        var nextW = Double(base.width)
        var nextH = Double(base.height)

        switch mode {
        case .move:
            nextX = clamp(Double(base.minX) + dx, 0, 1 - Double(base.width))
            nextY = clamp(Double(base.minY) + dy, 0, 1 - Double(base.height))
        case .se:
            nextW = clamp(Double(base.width) + dx, minSize, 1 - Double(base.minX))
            nextH = clamp(Double(base.height) + dy, minSize, 1 - Double(base.minY))
        case .sw:
            let newX = clamp(Double(base.minX) + dx, 0, Double(base.maxX) - minSize)
            nextW = clamp(Double(base.width) + (Double(base.minX) - newX), minSize, 1 - newX)
            nextX = newX
            nextH = clamp(Double(base.height) + dy, minSize, 1 - Double(base.minY))
        case .ne:
            let newY = clamp(Double(base.minY) + dy, 0, Double(base.maxY) - minSize)
            nextH = clamp(Double(base.height) + (Double(base.minY) - newY), minSize, 1 - newY)
            nextY = newY
            nextW = clamp(Double(base.width) + dx, minSize, 1 - Double(base.minX))
        case .nw:
            let newX = clamp(Double(base.minX) + dx, 0, Double(base.maxX) - minSize)
            let newY = clamp(Double(base.minY) + dy, 0, Double(base.maxY) - minSize)
            nextW = clamp(Double(base.width) + (Double(base.minX) - newX), minSize, 1 - newX)
            nextH = clamp(Double(base.height) + (Double(base.minY) - newY), minSize, 1 - newY)
            nextX = newX
            nextY = newY
        }

        nextX = clamp(nextX, 0, 1 - nextW)
        nextY = clamp(nextY, 0, 1 - nextH)
        x = nextX
        y = nextY
        width = nextW
        height = nextH
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }

    private var pixelSize: (width: Int, height: Int) {
        let w = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let h = image.cgImage?.height ?? Int(image.size.height * image.scale)
        return (Int((Double(w) * width).rounded()), Int((Double(h) * height).rounded()))
    }

    private func aspectFitRect(image: UIImage, in size: CGSize) -> CGRect {
        let source = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        let scale = min(size.width / source.width, size.height / source.height)
        let fitted = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}

private struct NativeImageBlurSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onApply: (Double) -> Void
    @State private var amount = 0.0
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Adjust the blur amount and apply to replace the current image.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Image(uiImage: image).resizable().scaledToFit().blur(radius: amount).frame(maxHeight: 320).frame(maxWidth: .infinity).padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).clipShape(RoundedRectangle(cornerRadius: 8))
                HStack { Text("Blur Amount: \(Int(amount.rounded()))px").font(.subheadline); Spacer() }
                Slider(value: $amount, in: 0...50, step: 1)
                Spacer()
            }.padding(20)
            .navigationTitle("Blur Image").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply Blur") { onApply(amount); dismiss() } } }
        }
    }
}
