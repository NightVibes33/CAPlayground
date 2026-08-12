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
            Text("Normal").tag("normalBlendMode"); Text("Color").tag("colorBlendMode"); Text("Color Burn").tag("colorBurnBlendMode"); Text("Color Dodge").tag("colorDodgeBlendMode")
            Text("Darken").tag("darkenBlendMode"); Text("Difference").tag("differenceBlendMode"); Text("Exclusion").tag("exclusionBlendMode"); Text("Hue").tag("hueBlendMode")
            Text("Lighten").tag("lightenBlendMode"); Text("Luminosity").tag("luminosityBlendMode"); Text("Multiply").tag("multiplyBlendMode"); Text("Overlay").tag("overlayBlendMode")
            Text("Saturation").tag("saturationBlendMode"); Text("Screen").tag("screenBlendMode")
        }
        Text("Opacity").font(.caption).foregroundStyle(.secondary)
        HStack { Slider(value: value(\.opacity, layer.opacity), in: 0...1); Text(layer.opacity.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit() }
        Text("Opacity affects the entire layer (content, background, and sublayers). Use Content → Background opacity to fade only the fill behind the content.").font(.caption2).foregroundStyle(.secondary)
        field("Corner Radius", layer.cornerRadius, \.cornerRadius)
        Toggle("Clip contents", isOn: value(\.masksToBounds, layer.masksToBounds)).disabled(project.activeState != "Base State")
        Text(project.activeState == "Base State" ? "Masks this layer's sublayers to its bounds." : "Not supported for state transitions").font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder private func content(_ layer: LayerModel) -> some View {
        colorField("Background colour", layer.backgroundColor ?? "#000000", \.backgroundColor)
        Text("Background opacity").font(.caption).foregroundStyle(.secondary)
        Slider(value: value(\.backgroundOpacity, layer.backgroundOpacity), in: 0...1)
        colorField("Border colour", layer.borderColor ?? "#000000", \.borderColor)
        field("Border width", layer.borderWidth, \.borderWidth)
        if layer.kind == .shape {
            Picker("Shape", selection: optionalString(\.shape, layer.shape ?? "rect")) { Text("Rectangle").tag("rect"); Text("Circle").tag("circle"); Text("Rounded Rectangle").tag("rounded-rect") }
            colorField("Fill", layer.fillColor ?? "#FFFFFF", \.fillColor); colorField("Stroke", layer.strokeColor ?? "#000000", \.strokeColor)
            optionalField("Stroke Width", layer.strokeWidth ?? 0, \.strokeWidth)
            if layer.shape == "rounded-rect" { field("Radius", layer.cornerRadius, \.cornerRadius) }
        }
    }

    @ViewBuilder private func text(_ layer: LayerModel) -> some View {
        TextField("Text", text: optionalString(\.text, layer.text ?? ""), axis: .vertical).textFieldStyle(.roundedBorder)
        optionalField("Font size", layer.fontSize ?? 32, \.fontSize)
        colorField("Color", layer.textColor ?? "#FFFFFF", \.textColor)
        Picker("Font", selection: optionalString(\.fontFamily, layer.fontFamily ?? "SFProText-Regular")) {
            Text("System Default (SF Pro)").tag("SFProText-Regular"); Text("Times New Roman").tag("TimesNewRomanPSMT"); Text("Copperplate").tag("Copperplate"); Text("Courier New").tag("CourierNewPSMT"); Text("Futura").tag("Futura-Medium"); Text("Georgia").tag("Georgia"); Text("Papyrus").tag("Papyrus"); Text("Verdana").tag("Verdana")
        }
        Picker("Alignment", selection: optionalString(\.textAlignment, layer.textAlignment ?? "left")) { Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right"); Text("Justified").tag("justified") }.pickerStyle(.segmented)
        Toggle("Wrap lines", isOn: optionalBool(\.wrapsText, layer.wrapsText ?? true))
    }

    @ViewBuilder private func gradient(_ layer: LayerModel) -> some View {
        Picker("Type", selection: optionalString(\.gradientType, layer.gradientType ?? "axial")) { Text("Axial (Linear)").tag("axial"); Text("Radial").tag("radial"); Text("Conic").tag("conic") }
        pointEditor("Start Point", keyPath: \.gradientStart, point: layer.gradientStart ?? .init(x: 0, y: 0)); pointEditor("End Point", keyPath: \.gradientEnd, point: layer.gradientEnd ?? .init(x: 1, y: 1))
        HStack { Text("Colors").font(.subheadline.weight(.medium)); Spacer(); Button("Add", systemImage: "plus") { update { ($0.gradientStops ?? []).isEmpty ? ($0.gradientStops = [.init(color: "#FFFFFF", opacity: 1)]) : ($0.gradientStops?.append(.init(color: "#FFFFFF", opacity: 1))) } } }
        ForEach(Array((layer.gradientStops ?? []).enumerated()), id: \.offset) { index, stop in
            HStack { ColorPicker("", selection: colorBinding(stop.color) { hex in update { $0.gradientStops?[index].color = hex } }).labelsHidden(); Slider(value: Binding(get: { stop.opacity }, set: { v in update { $0.gradientStops?[index].opacity = v } }), in: 0...1); Button(role: .destructive) { update { $0.gradientStops?.remove(at: index) } } label: { Image(systemName: "trash") } }
        }
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
        LabeledContent("Frames", value: "\(layer.frameCount ?? 0)"); optionalField("FPS", layer.framesPerSecond ?? 30, \.framesPerSecond)
        Picker("Calculation Mode", selection: optionalString(\.calculationMode, layer.calculationMode ?? "linear")) { Text("Linear").tag("linear"); Text("Discrete").tag("discrete") }
        Toggle("Auto Reverses", isOn: optionalBool(\.autoReverses, layer.autoReverses ?? false)); Toggle("Sync with state transition", isOn: optionalBool(\.syncWithState, layer.syncWithState ?? false)); optionalIntegerField("Current Frame", layer.currentFrameIndex ?? 0, \.currentFrameIndex)
        if layer.syncWithState ?? false { ForEach(["Locked", "Unlock", "Sleep"], id: \.self) { state in Picker("\(state) Frame", selection: syncFrameBinding(state, layer.syncStateFrameMode?[state] ?? "beginning")) { Text("Beginning").tag("beginning"); Text("End").tag("end") } } }
    }

    @ViewBuilder private func animations(_ layer: LayerModel) -> some View {
    AnimationInspectorPanel(project: $project, selectedID: $selectedID)
}

    @ViewBuilder private func gyro(_ layer: LayerModel) -> some View {
        Text("Configure how this layer responds to device tilt. You can add up to 10 dictionaries.").font(.caption).foregroundStyle(.secondary)
        Button("Add Gyro Dictionary", systemImage: "plus") { update { if ($0.gyroDictionaries?.count ?? 0) < 10 { $0.gyroDictionaries = ($0.gyroDictionaries ?? []) + [.init(layerName: $0.name)] } } }
        ForEach(layer.gyroDictionaries ?? []) { dictionary in
            DisclosureGroup(dictionary.title) {
                Picker("Axis", selection: gyroBinding(dictionary.id, \.axis, dictionary.axis)) { Text("X").tag("x"); Text("Y").tag("y") }; TextField("Title", text: gyroBinding(dictionary.id, \.title, dictionary.title)).textFieldStyle(.roundedBorder); TextField("Layer Name", text: gyroBinding(dictionary.id, \.layerName, dictionary.layerName)).textFieldStyle(.roundedBorder); TextField("Key Path", text: gyroBinding(dictionary.id, \.keyPath, dictionary.keyPath)).textFieldStyle(.roundedBorder)
                LabeledContent("Map Minimum") { TextField("Minimum", value: gyroBinding(dictionary.id, \.mapMinTo, dictionary.mapMinTo), format: .number).textFieldStyle(.roundedBorder) }; LabeledContent("Map Maximum") { TextField("Maximum", value: gyroBinding(dictionary.id, \.mapMaxTo, dictionary.mapMaxTo), format: .number).textFieldStyle(.roundedBorder) }
                Button("Remove", role: .destructive) { update { $0.gyroDictionaries?.removeAll { $0.id == dictionary.id } } }
            }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
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
        optionalIntegerField("Instance Count", layer.instanceCount ?? 1, \.instanceCount); optionalField("Translation X", layer.instanceTranslationX ?? 0, \.instanceTranslationX); optionalField("Translation Y", layer.instanceTranslationY ?? 0, \.instanceTranslationY); optionalField("Translation Z", layer.instanceTranslationZ ?? 0, \.instanceTranslationZ); optionalField("Instance Rotation (Z axis, degrees)", layer.instanceRotation ?? 0, \.instanceRotation); optionalField("Instance Delay (seconds)", layer.instanceDelay ?? 0, \.instanceDelay)
    }

    @ViewBuilder private func filters(_ layer: LayerModel) -> some View {
        Menu("Add filter") { Button("Gaussian Blur") { addFilter(type: "gaussianBlur", value: 10) }; Button("Contrast") { addFilter(type: "colorContrast", value: 1) }; Button("Hue Rotate") { addFilter(type: "colorHueRotate", value: 0) }; Button("Invert") { addFilter(type: "colorInvert", value: 0) }; Button("Saturate") { addFilter(type: "colorSaturate", value: 0) }; Button("Sepia") { addFilter(type: "CISepiaTone", value: 1) } }
        ForEach(layer.filters) { filter in
            VStack(alignment: .leading, spacing: 10) {
                HStack { Toggle(filterName(filter.type), isOn: filterBinding(filter.id, \.enabled, filter.enabled)); Spacer(); Button(role: .destructive) { update { $0.filters.removeAll { $0.id == filter.id } } } label: { Image(systemName: "xmark") }.buttonStyle(.bordered).controlSize(.small).accessibilityLabel("Remove filter") }
                if filter.type == "colorHueRotate" { Text("Angle").font(.caption).foregroundStyle(.secondary); HStack { Slider(value: filterBinding(filter.id, \.value, filter.value), in: -180...180, step: 1); Text("\(Int(filter.value.rounded()))°").monospacedDigit().frame(width: 52, alignment: .trailing) } }
                else if filter.type != "colorInvert" { LabeledContent(filterValueLabel(filter.type)) { TextField(filterValueLabel(filter.type), value: filterBinding(filter.id, \.value, filter.value), format: .number).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(maxWidth: 120) } }
            }.padding(10).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    private func addFilter(type: String, value: Double) { update { $0.filters.append(.init(type: type, value: value)) } }
    private func filterName(_ type: String) -> String { switch type { case "gaussianBlur": "Gaussian Blur"; case "colorContrast": "Contrast"; case "colorHueRotate": "Hue Rotate"; case "colorInvert": "Invert"; case "colorSaturate": "Saturate"; case "CISepiaTone": "Sepia"; default: type } }
    private func filterValueLabel(_ type: String) -> String { switch type { case "gaussianBlur": "Radius"; case "colorContrast", "colorSaturate": "Amount"; case "CISepiaTone": "Intensity"; case "colorHueRotate": "Angle"; default: "Value" } }
    private func update(_ mutation: (inout LayerModel) -> Void) { guard let selectedID else { return }; project.root.update(id: selectedID, mutation: mutation) }

    @MainActor private func importImage(_ url: URL) async { do { let imported = try await NativeImageAssetLoader.load(url); let name = project.uniqueAssetName(imported.filename, defaultExtension: "png"); project.setAsset(imported.data, named: name); update { $0.imageName = name } } catch { } }
    @MainActor private func importEmitterCellImage(_ url: URL, targetID: UUID?) async { do { let imported = try await NativeImageAssetLoader.load(url); let name = project.uniqueAssetName(imported.filename, defaultExtension: "png"); project.setAsset(imported.data, named: name); update { layer in if let targetID, let index = layer.emitterCells?.firstIndex(where: { $0.id == targetID }) { layer.emitterCells?[index].imageName = name } else { var cells = layer.emitterCells ?? []; var cell = EmitterCellModel(); cell.imageName = name; cells.append(cell); layer.emitterCells = cells } } } catch { } }

    private func selectedImage(_ layer: LayerModel) -> UIImage? { guard let name = layer.imageName, let data = project.assetData(named: name) else { return nil }; return UIImage(data: data) }
    private func resetImageBounds(_ layer: LayerModel) { guard let image = selectedImage(layer) else { return }; let width = Double(image.cgImage?.width ?? Int(image.size.width * image.scale)), height = Double(image.cgImage?.height ?? Int(image.size.height * image.scale)); updateSelectedSize(width: width, height: height) }
    private func updateSelectedSize(width: Double, height: Double) { guard let selectedID else { return }; project.updateStateAware(targetID: selectedID, values: ["bounds.size.width": width, "bounds.size.height": height]) { $0.size = .init(width: width, height: height) } }

    private func applyCrop(to layer: LayerModel, crop: CGRect, maintainBounds: Bool) {
        guard let image = selectedImage(layer), let source = image.cgImage else { return }
        let width = CGFloat(source.width), height = CGFloat(source.height)
        let pixelRect = CGRect(x: crop.minX * width, y: crop.minY * height, width: crop.width * width, height: crop.height * height).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixelRect.width > 0, pixelRect.height > 0, let cropped = source.cropping(to: pixelRect) else { return }
        let edited = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        storeEditedImage(edited, originalName: layer.imageName ?? "image.png", suffix: "cropped")
        if !maintainBounds { updateSelectedSize(width: Double(cropped.width), height: Double(cropped.height)) }
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
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onApply: (CGRect, Bool) -> Void
    @State private var x = 0.10
    @State private var y = 0.10
    @State private var width = 0.80
    @State private var height = 0.80
    @State private var maintainBounds = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Adjust the crop area and apply to replace the current image.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        let fit = aspectFitRect(image: image, in: geo.size)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                            Rectangle().fill(Color.black.opacity(0.18)).overlay(Rectangle().stroke(CATheme.accent, lineWidth: 2))
                                .frame(width: fit.width * width, height: fit.height * height)
                                .offset(x: fit.minX + fit.width * x, y: fit.minY + fit.height * y)
                        }
                    }.frame(height: 320).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).clipShape(RoundedRectangle(cornerRadius: 8))
                    cropSlider("X", value: $x, max: max(0, 1 - width)); cropSlider("Y", value: $y, max: max(0, 1 - height)); cropSlider("Width", value: Binding(get: { width }, set: { width = min(max($0, 0.05), 1 - x) }), max: max(0.05, 1 - x)); cropSlider("Height", value: Binding(get: { height }, set: { height = min(max($0, 0.05), 1 - y) }), max: max(0.05, 1 - y))
                    let pixels = pixelSize
                    Text("Crop size: \(pixels.width) × \(pixels.height) px").font(.caption).foregroundStyle(.secondary)
                    Toggle("Maintain original bounds", isOn: $maintainBounds)
                    Text(maintainBounds ? "Keeps the layer's current width and height after replacing the image." : "Updates the layer bounds to the cropped pixel dimensions.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Crop image").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply Crop") { onApply(.init(x: x, y: y, width: width, height: height), maintainBounds); dismiss() } } }
        }
    }

    private var pixelSize: (width: Int, height: Int) { let w = image.cgImage?.width ?? Int(image.size.width * image.scale), h = image.cgImage?.height ?? Int(image.size.height * image.scale); return (Int((Double(w) * width).rounded()), Int((Double(h) * height).rounded())) }
    private func cropSlider(_ title: String, value: Binding<Double>, max: Double) -> some View { VStack(alignment: .leading, spacing: 4) { HStack { Text(title).font(.caption); Spacer(); Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.caption).monospacedDigit() }; Slider(value: value, in: 0...Swift.max(max, 0.001), step: 0.01) } }
    private func aspectFitRect(image: UIImage, in size: CGSize) -> CGRect { let source = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1)); let scale = min(size.width / source.width, size.height / source.height); let fitted = CGSize(width: source.width * scale, height: source.height * scale); return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height) }
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
