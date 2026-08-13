from pathlib import Path
import re

# Filter model: preserve website filter identity while decoding older native projects.
model = Path('apps/ios/CAPlayground/Model/CAProject.swift')
s = model.read_text()
old = 'struct FilterModel: Codable, Hashable, Identifiable { var id = UUID(); var type: String; var value: Double; var enabled = true }'
new = 'struct FilterModel: Codable, Hashable, Identifiable { var id = UUID(); var type: String; var name: String? = nil; var value: Double; var enabled = true }'
if s.count(old) != 1:
    raise SystemExit(f'FilterModel marker count={s.count(old)}')
model.write_text(s.replace(old, new, 1))

# CAML export: preserve unique filter name and match parameterless colorInvert.
serializer = Path('apps/ios/CAPlayground/Export/CAMLSerializer.swift')
s = serializer.read_text()
pattern = re.compile(r'''    private static func filters\(_ filters: \[FilterModel\], indent: Int\) -> String \{.*?\n    \}\n\n    private static func animations''', re.S)
replacement = r'''    private static func filters(_ filters: [FilterModel], indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var counts: [String: Int] = [:]
        let items = filters.map { filter -> String in
            counts[filter.type, default: 0] += 1
            let exportName = filter.name ?? "\(filterDisplayName(filter.type)) \(counts[filter.type] ?? 1)"
            let enabled = filter.enabled ? "true" : "false"
            switch filter.type {
            case "gaussianBlur": return "\n\(pad)  <CAFilter filter=\"gaussianBlur\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\" inputRadius=\"\(number(filter.value))\"/>"
            case "colorContrast", "colorSaturate": return "\n\(pad)  <CAFilter filter=\"\(escape(filter.type))\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\" inputAmount=\"\(number(filter.value))\"/>"
            case "colorHueRotate": return "\n\(pad)  <CAFilter filter=\"colorHueRotate\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\" inputAngle=\"\(number(filter.value * .pi / 180))\"/>"
            case "colorInvert": return "\n\(pad)  <CAFilter filter=\"colorInvert\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\"/>"
            case "CISepiaTone": return "\n\(pad)  <CIFilter filter=\"CISepiaTone\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\"><inputIntensity type=\"real\" value=\"\(number(filter.value))\"/></CIFilter>"
            default: return "\n\(pad)  <CAFilter filter=\"\(escape(filter.type))\" name=\"\(escape(exportName))\" enabled=\"\(enabled)/>"
            }
        }.joined()
        return "\n\(pad)<filters>\(items)\n\(pad)</filters>"
    }

    private static func filterDisplayName(_ type: String) -> String {
        switch type {
        case "gaussianBlur": "Gaussian Blur"
        case "colorContrast": "Contrast"
        case "colorHueRotate": "Hue Rotate"
        case "colorInvert": "Invert"
        case "colorSaturate": "Saturate"
        case "CISepiaTone": "Sepia"
        default: type
        }
    }

    private static func animations'''
s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'filter serializer replacement count={count}')
serializer.write_text(s2)

# CAML import: preserve website filter name and correct parameterless invert default.
importer = Path('apps/ios/CAPlayground/Export/CAArchiveImporter.swift')
s = importer.read_text()
old_value = '''        else if type == "colorHueRotate" { rawValue = (number(attributes["inputAngle"]) ?? 0) * 180 / .pi }
        else { rawValue = number(attributes["inputIntensity"]) ?? 1 }
        layerStack[index].layer.filters.append(.init(
            type: type,
            value: rawValue,
            enabled: attributes["enabled"].map(bool) ?? true
        ))'''
new_value = '''        else if type == "colorHueRotate" { rawValue = (number(attributes["inputAngle"]) ?? 0) * 180 / .pi }
        else if type == "colorInvert" { rawValue = 0 }
        else { rawValue = number(attributes["inputIntensity"]) ?? 1 }
        layerStack[index].layer.filters.append(.init(
            type: type,
            name: attributes["name"],
            value: rawValue,
            enabled: attributes["enabled"].map(bool) ?? true
        ))'''
if s.count(old_value) != 1:
    raise SystemExit(f'filter importer marker count={s.count(old_value)}')
importer.write_text(s.replace(old_value, new_value, 1))

# Inspector: match website Replicator layout/constraints and Filter identity/controls.
inspector = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = inspector.read_text()
pattern = re.compile(r'''    @ViewBuilder private func replicator\(_ layer: LayerModel\) -> some View \{.*?\n    private func filterValueLabel\(_ type: String\) -> String \{.*?\n    \}\n''', re.S)
replacement = r'''    @ViewBuilder private func replicator(_ layer: LayerModel) -> some View {
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
'''
s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'Inspector replicator/filter replacement count={count}')
inspector.write_text(s2)

# Round-trip website filter name and parameterless Invert.
tests = Path('apps/ios/CAPlaygroundTests/ModelTests.swift')
t = tests.read_text()
insert_at = t.rfind('\n}')
if insert_at < 0:
    raise SystemExit('test class closing brace not found')
new_test = r'''

    func testFilterNamesAndParameterlessInvertRoundTrip() throws {
        var project = CAProjectDocument.blank(name: "Filters")
        let layerID = UUID()
        var layer = LayerModel(id: layerID, name: "Filtered", kind: .basic,
                               position: .init(x: 100, y: 100), size: .init(width: 100, height: 100))
        layer.filters = [
            FilterModel(type: "gaussianBlur", name: "Gaussian Blur 1", value: 10),
            FilterModel(type: "gaussianBlur", name: "Gaussian Blur 2", value: 20),
            FilterModel(type: "colorInvert", name: "Invert 1", value: 0)
        ]
        project.root.children = [layer]

        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let entries = try ZIPArchive.extract(archive)
        let caml = try XCTUnwrap(entries.first(where: { $0.path == "Floating.ca/main.caml" }))
        let xml = try XCTUnwrap(String(data: caml.data, encoding: .utf8))
        XCTAssertTrue(xml.contains("name=\"Gaussian Blur 1\""))
        XCTAssertTrue(xml.contains("name=\"Gaussian Blur 2\""))
        XCTAssertTrue(xml.contains("filter=\"colorInvert\" name=\"Invert 1\" enabled=\"true\"/>"))
        XCTAssertFalse(xml.contains("filter=\"colorInvert\" name=\"Invert 1\" enabled=\"true\" inputAmount"))

        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Filters.ca")
        let importedLayer = try XCTUnwrap(imported.documents[.floating]?.root.find(id: layerID))
        XCTAssertEqual(importedLayer.filters.map(\.name), ["Gaussian Blur 1", "Gaussian Blur 2", "Invert 1"])
        XCTAssertEqual(importedLayer.filters.last?.value, 0)
    }
'''
tests.write_text(t[:insert_at] + new_test + t[insert_at:])

Path('.github/final_inspector_patch.py').unlink()
Path('.github/workflows/final-inspector-parity.yml').unlink()
