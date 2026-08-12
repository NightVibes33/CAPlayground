import SwiftUI

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
        }.caPanel()
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
        field("X", layer.position.x, \.position.x); field("Y", layer.position.y, \.position.y)
        field("Z", layer.zPosition, \.zPosition)
        Divider(); field("Width", layer.size.width, \.size.width); field("Height", layer.size.height, \.size.height)
        Divider(); field("Scale", layer.scale, \.scale); field("Rotation (deg)", layer.rotation, \.rotation)
        field("Rotation X", layer.rotationX, \.rotationX); field("Rotation Y", layer.rotationY, \.rotationY)
        Text("Anchor Point").font(.caption).foregroundStyle(.secondary)
        HStack { field("X", layer.anchorPoint.x, \.anchorPoint.x); field("Y", layer.anchorPoint.y, \.anchorPoint.y) }
        Toggle("Flip Geometry", isOn: value(\.geometryFlipped, layer.geometryFlipped))
        if layer.kind == .transform || layer.kind == .replicator { optionalField("Perspective", layer.perspective ?? 0, \.perspective) }
    }

    @ViewBuilder private func compositing(_ layer: LayerModel) -> some View {
        Picker("Blending", selection: optionalString(\.blendMode, layer.blendMode ?? "normalBlendMode")) {
            Text("Normal").tag("normalBlendMode"); Text("Multiply").tag("multiplyBlendMode")
            Text("Screen").tag("screenBlendMode"); Text("Overlay").tag("overlayBlendMode")
        }
        Text("Opacity").font(.caption).foregroundStyle(.secondary)
        HStack { Slider(value: value(\.opacity, layer.opacity), in: 0...1); Text(layer.opacity.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit() }
        field("Corner Radius", layer.cornerRadius, \.cornerRadius)
        Toggle("Clip contents", isOn: value(\.masksToBounds, layer.masksToBounds))
    }

    @ViewBuilder private func content(_ layer: LayerModel) -> some View {
        colorField("Background colour", layer.backgroundColor ?? "#000000", \.backgroundColor)
        Text("Background opacity").font(.caption).foregroundStyle(.secondary)
        Slider(value: value(\.backgroundOpacity, layer.backgroundOpacity), in: 0...1)
        colorField("Border colour", layer.borderColor ?? "#000000", \.borderColor)
        field("Border width", layer.borderWidth, \.borderWidth)
    }

    @ViewBuilder private func text(_ layer: LayerModel) -> some View {
        TextField("Text", text: optionalString(\.text, layer.text ?? ""), axis: .vertical).textFieldStyle(.roundedBorder)
        optionalField("Font size", layer.fontSize ?? 32, \.fontSize)
        colorField("Color", layer.textColor ?? "#FFFFFF", \.textColor)
        Picker("Font", selection: optionalString(\.fontFamily, layer.fontFamily ?? "SFProText-Regular")) {
            Text("System Default (SF Pro)").tag("SFProText-Regular"); Text("Times New Roman").tag("TimesNewRomanPSMT")
            Text("Copperplate").tag("Copperplate"); Text("Courier New").tag("CourierNewPSMT")
            Text("Futura").tag("Futura-Medium"); Text("Georgia").tag("Georgia"); Text("Papyrus").tag("Papyrus"); Text("Verdana").tag("Verdana")
        }
        Picker("Alignment", selection: optionalString(\.textAlignment, layer.textAlignment ?? "left")) {
            Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right"); Text("Justified").tag("justified")
        }.pickerStyle(.segmented)
        Toggle("Wrap lines", isOn: optionalBool(\.wrapsText, layer.wrapsText ?? true))
    }

    @ViewBuilder private func gradient(_ layer: LayerModel) -> some View {
        Picker("Type", selection: optionalString(\.gradientType, layer.gradientType ?? "axial")) {
            Text("Axial (Linear)").tag("axial"); Text("Radial").tag("radial"); Text("Conic").tag("conic")
        }
        pointEditor("Start Point", keyPath: \.gradientStart, point: layer.gradientStart ?? .init(x: 0, y: 0))
        pointEditor("End Point", keyPath: \.gradientEnd, point: layer.gradientEnd ?? .init(x: 1, y: 1))
        HStack { Text("Colors").font(.subheadline.weight(.medium)); Spacer(); Button("Add", systemImage: "plus") { update { ($0.gradientStops ?? []).isEmpty ? ($0.gradientStops = [.init(color: "#FFFFFF", opacity: 1)]) : ($0.gradientStops?.append(.init(color: "#FFFFFF", opacity: 1))) } } }
        ForEach(Array((layer.gradientStops ?? []).enumerated()), id: \.offset) { index, stop in
            HStack { ColorPicker("", selection: colorBinding(stop.color) { hex in update { $0.gradientStops?[index].color = hex } }).labelsHidden(); Slider(value: Binding(get: { stop.opacity }, set: { v in update { $0.gradientStops?[index].opacity = v } }), in: 0...1); Button(role: .destructive) { update { $0.gradientStops?.remove(at: index) } } label: { Image(systemName: "trash") } }
        }
    }

    @ViewBuilder private func image(_ layer: LayerModel) -> some View {
        Label(layer.imageName ?? "No image selected", systemImage: "photo")
        Button("Replace Image…") { }
        Picker("Fit", selection: optionalString(\.contentMode, layer.contentMode ?? "fill")) { Text("Cover").tag("cover"); Text("Contain").tag("contain"); Text("Fill").tag("fill"); Text("None").tag("none") }
    }

    @ViewBuilder private func video(_ layer: LayerModel) -> some View {
        LabeledContent("Frames", value: "\(layer.frameCount ?? 0)"); optionalField("FPS", layer.framesPerSecond ?? 30, \.framesPerSecond)
        Picker("Calculation Mode", selection: optionalString(\.calculationMode, layer.calculationMode ?? "linear")) { Text("Linear").tag("linear"); Text("Discrete").tag("discrete") }
        Toggle("Auto Reverses", isOn: optionalBool(\.autoReverses, layer.autoReverses ?? false))
        Toggle("Sync with state transition", isOn: optionalBool(\.syncWithState, layer.syncWithState ?? false))
    }

    @ViewBuilder private func animations(_ layer: LayerModel) -> some View {
        Menu("Add animation") { ForEach(["position", "position.x", "position.y", "transform.rotation.x", "transform.rotation.y", "transform.rotation.z", "opacity", "bounds", "backgroundColor"], id: \.self) { key in Button(key) { update { $0.animations.append(.init(keyPath: key, numericValues: [0, 1], keyTimes: [0, 1], duration: 1)) } } } }
        ForEach(layer.animations) { animation in
            DisclosureGroup(animation.keyPath) {
                Toggle("Enabled", isOn: animationBinding(animation.id, \.enabled, animation.enabled))
                animationField("Duration (s)", animation.id, \.duration, animation.duration)
                Toggle("Loop", isOn: animationBinding(animation.id, \.repeats, animation.repeats))
                Toggle("Autoreverse", isOn: animationBinding(animation.id, \.autoreverses, animation.autoreverses))
                Picker("Calculation Mode", selection: animationBinding(animation.id, \.calculationMode, animation.calculationMode)) { Text("Linear").tag("linear"); Text("Discrete").tag("discrete") }
                Picker("Timing Function", selection: animationBinding(animation.id, \.timingFunction, animation.timingFunction)) { Text("Linear").tag("linear"); Text("Ease In").tag("easeIn"); Text("Ease Out").tag("easeOut"); Text("Ease In-Out").tag("easeInEaseOut") }
                Button("Delete Animation", role: .destructive) { update { $0.animations.removeAll { $0.id == animation.id } } }
            }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    @ViewBuilder private func gyro(_ layer: LayerModel) -> some View {
        Text("Configure how this layer responds to device tilt. You can add up to 10 dictionaries.").font(.caption).foregroundStyle(.secondary)
        Button("Add Gyro Dictionary", systemImage: "plus") { update { if ($0.gyroDictionaries?.count ?? 0) < 10 { $0.gyroDictionaries = ($0.gyroDictionaries ?? []) + [.init(layerName: $0.name)] } } }
        ForEach(layer.gyroDictionaries ?? []) { dictionary in
            VStack { Text(dictionary.title).fontWeight(.medium); LabeledContent("Axis", value: dictionary.axis.uppercased()); LabeledContent("Key Path", value: dictionary.keyPath); LabeledContent("Range", value: "\(dictionary.mapMinTo) … \(dictionary.mapMaxTo)") }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    @ViewBuilder private func emitter(_ layer: LayerModel) -> some View {
        pointEditor("Emitter Position", keyPath: \.emitterPosition, point: layer.emitterPosition ?? .init(x: 0, y: 0))
        sizeEditor("Emitter Size", keyPath: \.emitterSize, size: layer.emitterSize ?? .init(width: 1, height: 1))
        Picker("Render Mode", selection: optionalString(\.renderMode, layer.renderMode ?? "unordered")) { Text("unordered").tag("unordered"); Text("additive").tag("additive") }
        Picker("Shape", selection: optionalString(\.emitterShape, layer.emitterShape ?? "point")) { Text("point").tag("point"); Text("line").tag("line"); Text("rectangle").tag("rectangle") }
        Picker("Mode", selection: optionalString(\.emitterMode, layer.emitterMode ?? "volume")) { Text("volume").tag("volume"); Text("outline").tag("outline"); Text("surface").tag("surface") }
        HStack { Text("Cells").fontWeight(.medium); Spacer(); Button("Add", systemImage: "plus") { update { $0.emitterCells = ($0.emitterCells ?? []) + [.init()] } } }
        ForEach(layer.emitterCells ?? []) { cell in LabeledContent(cell.name, value: "Birth \(cell.birthRate.formatted()) · Life \(cell.lifetime.formatted())") }
    }

    @ViewBuilder private func replicator(_ layer: LayerModel) -> some View {
        optionalIntegerField("Instance Count", layer.instanceCount ?? 1, \.instanceCount)
        optionalField("Translation X", layer.instanceTranslationX ?? 0, \.instanceTranslationX); optionalField("Translation Y", layer.instanceTranslationY ?? 0, \.instanceTranslationY); optionalField("Translation Z", layer.instanceTranslationZ ?? 0, \.instanceTranslationZ)
        optionalField("Instance Rotation (Z axis, degrees)", layer.instanceRotation ?? 0, \.instanceRotation)
        optionalField("Instance Delay (seconds)", layer.instanceDelay ?? 0, \.instanceDelay)
    }

    @ViewBuilder private func filters(_ layer: LayerModel) -> some View {
        Menu("Add filter") { ForEach(["gaussianBlur", "colorContrast", "colorHueRotate", "colorInvert", "colorSaturate", "CISepiaTone"], id: \.self) { type in Button(type) { update { $0.filters.append(.init(type: type, value: type == "colorContrast" || type == "colorSaturate" ? 1 : 0)) } } } }
        ForEach(layer.filters) { filter in
            VStack(alignment: .leading) {
                Toggle(filter.type, isOn: filterBinding(filter.id, \.enabled, filter.enabled))
                HStack { Slider(value: filterBinding(filter.id, \.value, filter.value), in: filter.type == "gaussianBlur" ? 0...100 : 0...2); Text(filter.value.formatted(.number.precision(.fractionLength(2)))).monospacedDigit() }
                Button("Remove", role: .destructive) { update { $0.filters.removeAll { $0.id == filter.id } } }
            }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    private func update(_ mutation: (inout LayerModel) -> Void) { guard let selectedID else { return }; project.root.update(id: selectedID, mutation: mutation) }
    private func value<T>(_ keyPath: WritableKeyPath<LayerModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }) }
    private func optionalString(_ keyPath: WritableKeyPath<LayerModel, String?>, _ fallback: String) -> Binding<String> { Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }) }
    private func optionalBool(_ keyPath: WritableKeyPath<LayerModel, Bool?>, _ fallback: Bool) -> Binding<Bool> { Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }) }
    private func field(_ title: String, _ fallback: Double, _ keyPath: WritableKeyPath<LayerModel, Double>) -> some View { LabeledContent(title) { TextField(title, value: value(keyPath, fallback), format: .number).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func optionalField(_ title: String, _ fallback: Double, _ keyPath: WritableKeyPath<LayerModel, Double?>) -> some View { LabeledContent(title) { TextField(title, value: Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }), format: .number).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func optionalIntegerField(_ title: String, _ fallback: Int, _ keyPath: WritableKeyPath<LayerModel, Int?>) -> some View { LabeledContent(title) { TextField(title, value: Binding(get: { selectedID.flatMap { project.root.find(id: $0) }?[keyPath: keyPath] ?? fallback }, set: { new in update { $0[keyPath: keyPath] = new } }), format: .number).multilineTextAlignment(.trailing).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func colorField(_ title: String, _ fallback: String, _ keyPath: WritableKeyPath<LayerModel, String?>) -> some View { ColorPicker(title, selection: colorBinding(fallback) { hex in update { $0[keyPath: keyPath] = hex } }) }
    private func colorBinding(_ hex: String, set: @escaping (String) -> Void) -> Binding<Color> { Binding(get: { Color(uiColor: UIColor(caHex: hex) ?? .white) }, set: { color in if let components = UIColor(color).cgColor.components, components.count >= 3 { set(String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))) } }) }
    private func pointEditor(_ title: String, keyPath: WritableKeyPath<LayerModel, Vector2?>, point: Vector2) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); HStack { TextField("X", value: Binding(get: { point.x }, set: { v in update { var p = $0[keyPath: keyPath] ?? point; p.x = v; $0[keyPath: keyPath] = p } }), format: .number).textFieldStyle(.roundedBorder); TextField("Y", value: Binding(get: { point.y }, set: { v in update { var p = $0[keyPath: keyPath] ?? point; p.y = v; $0[keyPath: keyPath] = p } }), format: .number).textFieldStyle(.roundedBorder) } } }
    private func sizeEditor(_ title: String, keyPath: WritableKeyPath<LayerModel, LayerSize?>, size: LayerSize) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); HStack { TextField("Width", value: Binding(get: { size.width }, set: { v in update { var s = $0[keyPath: keyPath] ?? size; s.width = v; $0[keyPath: keyPath] = s } }), format: .number).textFieldStyle(.roundedBorder); TextField("Height", value: Binding(get: { size.height }, set: { v in update { var s = $0[keyPath: keyPath] ?? size; s.height = v; $0[keyPath: keyPath] = s } }), format: .number).textFieldStyle(.roundedBorder) } } }
    private func animationBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<KeyframeAnimationModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selected?.animations.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { new in update { layer in if let i = layer.animations.firstIndex(where: { $0.id == id }) { layer.animations[i][keyPath: keyPath] = new } } }) }
    private func animationField(_ title: String, _ id: UUID, _ keyPath: WritableKeyPath<KeyframeAnimationModel, Double>, _ fallback: Double) -> some View { LabeledContent(title) { TextField(title, value: animationBinding(id, keyPath, fallback), format: .number).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
    private func filterBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<FilterModel, T>, _ fallback: T) -> Binding<T> { Binding(get: { selected?.filters.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { new in update { layer in if let i = layer.filters.firstIndex(where: { $0.id == id }) { layer.filters[i][keyPath: keyPath] = new } } }) }
}
