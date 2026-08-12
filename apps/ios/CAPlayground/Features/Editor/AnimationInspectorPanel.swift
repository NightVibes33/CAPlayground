import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AnimationInspectorPanel: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?

    private var layer: LayerModel? { selectedID.flatMap { project.root.find(id: $0) } }

    private var availableKeyPaths: [String] {
        guard let layer else { return [] }
        var paths = [
            "position", "position.x", "position.y",
            "transform.rotation.x", "transform.rotation.y", "transform.rotation.z",
            "opacity", "bounds", "backgroundColor"
        ]
        if layer.kind == .gradient { paths.append("colors") }
        let existing = Set(layer.animations.map(\.keyPath))
        return paths.filter { !existing.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(availableKeyPaths, id: \.self) { keyPath in
                    Button(keyPath) { addAnimation(keyPath) }
                }
            } label: {
                HStack {
                    Text("Add animation")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 36)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(.separator)))
            }
            .buttonStyle(.plain)
            .disabled(availableKeyPaths.isEmpty)

            if let layer {
                ForEach(layer.animations) { animation in
                    WebsiteAnimationItem(project: $project, selectedID: selectedID, animationID: animation.id)
                }
            }
        }
    }

    private func addAnimation(_ keyPath: String) {
        guard let selectedID else { return }
        project.root.update(id: selectedID) { layer in
            guard !layer.animations.contains(where: { $0.keyPath == keyPath }) else { return }
            layer.animations.append(.init(
                keyPath: keyPath,
                numericValues: [],
                values: [],
                keyTimes: [],
                duration: 1
            ))
        }
    }
}

private struct WebsiteAnimationItem: View {
    @Binding var project: CAProjectDocument
    let selectedID: UUID?
    let animationID: UUID

    @State private var expanded = false
    @State private var showAdvanced = false
    @State private var useCustomKeyTimes: Bool
    @State private var bulkOpen = false
    @State private var bulkText = ""
    @State private var bulkError: String?
    @State private var bulkFileOpen = false
    @State private var bulkFileName = ""
    @State private var exportDocument: AnimationValuesTextDocument?
    @State private var exportOpen = false

    init(project: Binding<CAProjectDocument>, selectedID: UUID?, animationID: UUID) {
        _project = project
        self.selectedID = selectedID
        self.animationID = animationID
        let layer = selectedID.flatMap { project.wrappedValue.root.find(id: $0) }
        let animation = layer?.animations.first(where: { $0.id == animationID })
        _useCustomKeyTimes = State(initialValue: !(animation?.keyTimes.isEmpty ?? true))
    }

    private var layer: LayerModel? { selectedID.flatMap { project.root.find(id: $0) } }
    private var animation: KeyframeAnimationModel? { layer?.animations.first(where: { $0.id == animationID }) }
    private var values: [AnimationValue] {
        guard let animation else { return [] }
        return currentValues(animation)
    }

    var body: some View {
        if let animation {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        updateAnimation { $0.enabled.toggle() }
                    } label: {
                        Image(systemName: animation.enabled ? "checkmark.square.fill" : "square")
                            .foregroundStyle(animation.enabled ? CATheme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enable animation")

                    Button {
                        expanded.toggle()
                    } label: {
                        HStack {
                            Text(animation.keyPath).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)

                if expanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        primaryControls(animation)
                        advancedControls(animation)
                        keyframes(animation)
                        actionButtons(animation)
                    }
                    .padding(10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
            .fileImporter(
                isPresented: $bulkFileOpen,
                allowedContentTypes: [.plainText, UTType(filenameExtension: "csv") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    bulkText = try String(contentsOf: url, encoding: .utf8)
                    bulkFileName = url.lastPathComponent
                    bulkError = parseBulk(bulkText, keyPath: animation.keyPath).error
                } catch {
                    bulkError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $exportOpen,
                document: exportDocument,
                contentType: .plainText,
                defaultFilename: "animation-values-\(animation.keyPath).txt"
            ) { _ in }
            .sheet(isPresented: $bulkOpen) { bulkSheet(animation) }
        }
    }

    @ViewBuilder private func primaryControls(_ animation: KeyframeAnimationModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Duration (s)").font(.caption)
                    TextField("Duration (s)", value: positive(\.duration, animation.duration, 1), format: .number)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Loop").font(.caption)
                    HStack(spacing: 7) {
                        Toggle("", isOn: binding(\.repeats, animation.repeats)).labelsHidden()
                        Text("Infinite").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(height: 36)
                }
            }

            if !animation.repeats {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Repeat for (s)").font(.caption)
                    TextField("Repeat for (s)", value: repeatDuration(animation), format: .number)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .disabled(!animation.enabled)
        .opacity(animation.enabled ? 1 : 0.5)
    }

    @ViewBuilder private func advancedControls(_ animation: KeyframeAnimationModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Button {
                showAdvanced.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                    Text("Advanced options")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!animation.enabled)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Speed").font(.caption)
                            TextField("Speed", value: positive(\.speed, animation.speed, 1), format: .number)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Autoreverse").font(.caption)
                            Toggle("", isOn: binding(\.autoreverses, animation.autoreverses))
                                .labelsHidden()
                                .frame(height: 36, alignment: .leading)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Calculation Mode").font(.caption)
                            Picker("Calculation Mode", selection: binding(\.calculationMode, animation.calculationMode)) {
                                Text("Linear").tag("linear")
                                Text("Discrete").tag("discrete")
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Timing Function").font(.caption)
                            Picker("Timing Function", selection: binding(\.timingFunction, animation.timingFunction)) {
                                Text("Linear").tag("linear")
                                Text("Ease In").tag("easeIn")
                                Text("Ease Out").tag("easeOut")
                                Text("Ease In-Out").tag("easeInEaseOut")
                            }
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Custom Key Times").font(.caption)
                        HStack(spacing: 7) {
                            Toggle("", isOn: Binding(
                                get: { useCustomKeyTimes },
                                set: { enabled in
                                    useCustomKeyTimes = enabled
                                    updateAnimation { changed in
                                        changed.keyTimes = enabled ? distributedTimes(currentValues(changed).count) : []
                                    }
                                }
                            ))
                            .labelsHidden()
                            Text("Custom timing per keyframe").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!animation.enabled)
                .opacity(animation.enabled ? 1 : 0.5)
            }
        }
    }

    @ViewBuilder private func keyframes(_ animation: KeyframeAnimationModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyframes").font(.subheadline.weight(.medium))
                Spacer()
                Button("+ Add") { addCurrentValue(animation) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!animation.enabled)
                if animation.keyPath != "backgroundColor" {
                    Button {
                        bulkText = formatBulk(values, keyPath: animation.keyPath)
                        bulkError = nil
                        bulkFileName = ""
                        bulkOpen = true
                    } label: { Label("Bulk", systemImage: "bolt.fill") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!animation.enabled)
                }
            }

            if values.isEmpty {
                Text("No keyframes yet. Click \"+ Add\" to create one.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    header(animation)
                    ForEach(values.indices, id: \.self) { index in
                        AnimationKeyframeRow(
                            project: $project,
                            selectedID: selectedID,
                            animationID: animationID,
                            index: index,
                            customTimes: useCustomKeyTimes
                        )
                        if index != values.indices.last { Divider() }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                .opacity(animation.enabled ? 1 : 0.5)
            }
        }
    }

    @ViewBuilder private func header(_ animation: KeyframeAnimationModel) -> some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 20, alignment: .leading)
            switch animation.keyPath {
            case "position":
                Text("X").frame(maxWidth: .infinity, alignment: .leading)
                Text("Y").frame(maxWidth: .infinity, alignment: .leading)
            case "bounds":
                Text("W").frame(maxWidth: .infinity, alignment: .leading)
                Text("H").frame(maxWidth: .infinity, alignment: .leading)
            case "colors": Text("Color Stops").frame(maxWidth: .infinity, alignment: .leading)
            case "position.x": Text("X").frame(maxWidth: .infinity, alignment: .leading)
            case "position.y": Text("Y").frame(maxWidth: .infinity, alignment: .leading)
            case "opacity": Text("Opacity").frame(maxWidth: .infinity, alignment: .leading)
            case "backgroundColor": Text("Color").frame(maxWidth: .infinity, alignment: .leading)
            default: Text("Deg").frame(maxWidth: .infinity, alignment: .leading)
            }
            if useCustomKeyTimes { Text("Time").frame(width: 54, alignment: .leading) }
            Color.clear.frame(width: 22)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Color.secondary.opacity(0.08))
    }

    @ViewBuilder private func actionButtons(_ animation: KeyframeAnimationModel) -> some View {
        HStack {
            if animation.enabled && !values.isEmpty {
                Button {
                    exportDocument = .init(text: exportText(values, keyPath: animation.keyPath))
                    exportOpen = true
                } label: {
                    Label("Export", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button("Remove", role: .destructive) {
                guard let selectedID else { return }
                project.root.update(id: selectedID) { layer in
                    layer.animations.removeAll { $0.id == animationID }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func bulkSheet(_ animation: KeyframeAnimationModel) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(formatHelp(animation.keyPath))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Animation Values").font(.subheadline.weight(.medium))
                    TextEditor(text: $bulkText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                        .onChange(of: bulkText) { _, text in
                            bulkError = parseBulk(text, keyPath: animation.keyPath).error
                        }

                    if let bulkError {
                        Label(bulkError, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import from File").font(.subheadline.weight(.medium))
                        HStack {
                            Button("Choose file") { bulkFileOpen = true }.buttonStyle(.bordered)
                            Text(bulkFileName.isEmpty ? "No file chosen" : bulkFileName)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    HStack {
                        Text("\(bulkCount) values")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        Spacer()
                        Button("Cancel") { bulkOpen = false }.buttonStyle(.bordered)
                        Button("Apply Values") { applyBulk(animation) }
                            .buttonStyle(.borderedProminent)
                            .disabled(bulkError != nil || bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Bulk Animation Values - \(animation.keyPath)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var bulkCount: Int {
        bulkText.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private func addCurrentValue(_ animation: KeyframeAnimationModel) {
        guard let layer else { return }
        let next: AnimationValue
        switch animation.keyPath {
        case "position": next = .point(layer.position)
        case "position.x": next = .number(layer.position.x)
        case "position.y": next = .number(layer.position.y)
        case "transform.rotation.x": next = .number(layer.rotationX)
        case "transform.rotation.y": next = .number(layer.rotationY)
        case "transform.rotation.z": next = .number(layer.rotation)
        case "opacity": next = .number(layer.opacity)
        case "bounds": next = .size(layer.size)
        case "colors":
            let stops = layer.gradientStops ?? []
            next = .colors(stops.isEmpty ? [.init(color: "#ffffff", opacity: 1)] : stops)
        case "backgroundColor": next = .color(layer.backgroundColor ?? "#ffffff")
        default: return
        }

        updateAnimation { changed in
            var nextValues = currentValues(changed)
            nextValues.append(next)
            setValues(nextValues, on: &changed)
            if useCustomKeyTimes {
                var times = normalizedTimes(changed.keyTimes, count: nextValues.count - 1)
                times.append(nextValues.count <= 1 ? 0 : 1)
                changed.keyTimes = times
            }
        }
    }

    private func applyBulk(_ animation: KeyframeAnimationModel) {
        let parsed = parseBulk(bulkText, keyPath: animation.keyPath)
        guard parsed.error == nil, !parsed.values.isEmpty else { bulkError = parsed.error; return }
        updateAnimation { changed in
            setValues(parsed.values, on: &changed)
            if useCustomKeyTimes { changed.keyTimes = distributedTimes(parsed.values.count) }
        }
        bulkOpen = false
    }

    private func parseBulk(_ text: String, keyPath: String) -> (values: [AnimationValue], error: String?) {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var output: [AnimationValue] = []
        for line in lines {
            if keyPath == "position" || keyPath == "bounds" {
                let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else {
                    let pair = keyPath == "position" ? "x, y" : "w, h"
                    return ([], "Invalid format for \(keyPath). Expected \"\(pair)\" format.")
                }
                guard let first = Double(parts[0]), let second = Double(parts[1]) else {
                    return ([], "Invalid numbers in line: \(line)")
                }
                output.append(keyPath == "position"
                    ? .point(.init(x: first.rounded(), y: second.rounded()))
                    : .size(.init(width: first.rounded(), height: second.rounded())))
            } else {
                guard let number = Double(line) else { return ([], "Invalid number: \(line)") }
                output.append(.number(keyPath == "opacity"
                    ? min(100, max(0, number.rounded())) / 100
                    : number.rounded()))
            }
        }
        return (output, nil)
    }

    private func formatBulk(_ values: [AnimationValue], keyPath: String) -> String {
        values.compactMap { value -> String? in
            switch value {
            case .number(let n): return keyPath == "opacity" ? "\(Int((n * 100).rounded()))" : "\(Int(n.rounded()))"
            case .point(let p): return "\(Int(p.x.rounded())), \(Int(p.y.rounded()))"
            case .size(let s): return "\(Int(s.width.rounded())), \(Int(s.height.rounded()))"
            case .color, .colors: return nil
            }
        }.joined(separator: "\n")
    }

    private func formatHelp(_ keyPath: String) -> String {
        switch keyPath {
        case "position": "Format: x, y (one per line)\nExample:\n100, 50\n200, 100\n300, 150"
        case "bounds": "Format: width, height (one per line)\nExample:\n100, 50\n150, 75\n200, 100"
        case "opacity": "Format: percentage (one per line)\nExample:\n0\n50\n100"
        default: "Format: \(keyPath.contains("rotation") ? "degrees" : "number") (one per line)\nExample:\n0\n45\n90"
        }
    }

    private func exportText(_ values: [AnimationValue], keyPath: String) -> String {
        values.map { value in
            switch value {
            case .color(let color): color
            case .number(let n): keyPath == "opacity" ? "\(Int((n * 100).rounded()))" : "\(Int(n.rounded()))"
            case .point(let p): "\(Int(p.x.rounded())), \(Int(p.y.rounded()))"
            case .size(let s): "\(Int(s.width.rounded())), \(Int(s.height.rounded()))"
            case .colors: ""
            }
        }.joined(separator: "\n")
    }

    private func updateAnimation(_ mutation: (inout KeyframeAnimationModel) -> Void) {
        guard let selectedID else { return }
        project.root.update(id: selectedID) { layer in
            guard let index = layer.animations.firstIndex(where: { $0.id == animationID }) else { return }
            mutation(&layer.animations[index])
        }
    }

    private func currentValues(_ animation: KeyframeAnimationModel) -> [AnimationValue] {
        animation.values ?? animation.numericValues.map(AnimationValue.number)
    }

    private func setValues(_ values: [AnimationValue], on animation: inout KeyframeAnimationModel) {
        animation.values = values
        animation.numericValues = values.compactMap { if case .number(let n) = $0 { n } else { nil } }
    }

    private func distributedTimes(_ count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [0] }
        return (0..<count).map { Double($0) / Double(count - 1) }
    }

    private func normalizedTimes(_ times: [Double], count: Int) -> [Double] {
        times.count == count ? times : distributedTimes(count)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<KeyframeAnimationModel, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { animation?[keyPath: keyPath] ?? fallback },
            set: { value in updateAnimation { $0[keyPath: keyPath] = value } }
        )
    }

    private func positive(
        _ keyPath: WritableKeyPath<KeyframeAnimationModel, Double>,
        _ fallback: Double,
        _ defaultValue: Double
    ) -> Binding<Double> {
        Binding(
            get: { animation?[keyPath: keyPath] ?? fallback },
            set: { value in updateAnimation { $0[keyPath: keyPath] = value.isFinite && value > 0 ? value : defaultValue } }
        )
    }

    private func repeatDuration(_ animation: KeyframeAnimationModel) -> Binding<Double> {
        Binding(
            get: { animation.repeatDurationSeconds ?? max(animation.duration, 1) },
            set: { value in
                let fallback = animation.duration > 0 ? animation.duration : 1
                updateAnimation { $0.repeatDurationSeconds = value.isFinite && value > 0 ? value : fallback }
            }
        )
    }
}

private struct AnimationKeyframeRow: View {
    @Binding var project: CAProjectDocument
    let selectedID: UUID?
    let animationID: UUID
    let index: Int
    let customTimes: Bool

    @State private var timeOpen = false

    private var layer: LayerModel? { selectedID.flatMap { project.root.find(id: $0) } }
    private var animation: KeyframeAnimationModel? { layer?.animations.first(where: { $0.id == animationID }) }
    private var values: [AnimationValue] {
        guard let animation else { return [] }
        return currentValues(animation)
    }

    var body: some View {
        if let animation, values.indices.contains(index) {
            HStack(spacing: 6) {
                Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
                valueEditor(animation)

                if customTimes {
                    Button("\(displayTime(animation))%") { if index != 0 { timeOpen = true } }
                        .font(.system(size: 10, design: .monospaced))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .frame(width: 54)
                        .disabled(!animation.enabled || index == 0)
                        .popover(isPresented: $timeOpen) {
                            keyTimePopover(animation).presentationCompactAdaptation(.popover)
                        }
                }

                Button(role: .destructive) { removeValue(animation) } label: {
                    Image(systemName: "xmark").frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!animation.enabled)
                .accessibilityLabel("Remove keyframe")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder private func valueEditor(_ animation: KeyframeAnimationModel) -> some View {
        let value = values[index]
        switch animation.keyPath {
        case "colors":
            if case .colors(let stops) = value {
                HStack(spacing: 6) {
                    ForEach(stops.indices, id: \.self) { stop in
                        ColorPicker("", selection: color(stops[stop].color) { hex in
                            updateValue(animation) { existing in
                                guard case .colors(var changed) = existing, changed.indices.contains(stop) else { return existing }
                                changed[stop].color = hex
                                return .colors(changed)
                            }
                        })
                        .labelsHidden()
                        .frame(width: 28)
                    }
                    Spacer(minLength: 0)
                }
            } else { Text("—").frame(maxWidth: .infinity, alignment: .leading) }

        case "position":
            if case .point(let p) = value {
                numberField("X", p.x) { x in updateValue(animation) { _ in .point(.init(x: x, y: p.y)) } }
                numberField("Y", p.y) { y in updateValue(animation) { _ in .point(.init(x: p.x, y: y)) } }
            }

        case "bounds":
            if case .size(let s) = value {
                numberField("W", s.width) { w in updateValue(animation) { _ in .size(.init(width: w, height: s.height)) } }
                numberField("H", s.height) { h in updateValue(animation) { _ in .size(.init(width: s.width, height: h)) } }
            }

        case "backgroundColor":
            if case .color(let hex) = value {
                ColorPicker("", selection: color(hex) { changed in
                    updateValue(animation) { _ in .color(changed) }
                })
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case "opacity":
            let n = number(value, 1)
            HStack(spacing: 4) {
                TextField("Opacity", value: Binding(
                    get: { Int((n * 100).rounded()) },
                    set: { percent in
                        let p = max(0, min(100, percent))
                        updateValue(animation) { _ in .number(Double(p) / 100) }
                    }
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                Text("%").font(.caption).foregroundStyle(.secondary)
            }

        default:
            numberField("Value", number(value, 0)) { n in updateValue(animation) { _ in .number(n) } }
        }
    }

    private func numberField(_ label: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        TextField(label, value: Binding(get: { value.rounded() }, set: { set($0.rounded()) }), format: .number)
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func keyTimePopover(_ animation: KeyframeAnimationModel) -> some View {
        let range = timeRange(animation)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keyframe Time").font(.caption.weight(.medium))
                Spacer()
                Text("\(displayTime(animation))%").font(.caption.monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { Double(displayTime(animation)) },
                    set: { setTime(animation, Int($0.rounded())) }
                ),
                in: Double(range.min)...Double(range.max),
                step: 1
            )
            Text("Range: \(range.min)% – \(range.max)%").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 220)
    }

    private func displayTime(_ animation: KeyframeAnimationModel) -> Int {
        if index == 0 { return 0 }
        let times = normalizedTimes(animation)
        return times.indices.contains(index) ? Int((times[index] * 100).rounded()) : 0
    }

    private func timeRange(_ animation: KeyframeAnimationModel) -> (min: Int, max: Int) {
        let times = normalizedTimes(animation)
        let previous = index > 0 && times.indices.contains(index - 1) ? times[index - 1] : 0
        let next = index + 1 < times.count ? times[index + 1] : 1
        let minimum = index == 0 ? 0 : Int((previous * 100).rounded()) + 1
        let maximum = index == values.count - 1 ? 100 : Int((next * 100).rounded()) - 1
        return (minimum, max(minimum, maximum))
    }

    private func setTime(_ animation: KeyframeAnimationModel, _ percent: Int) {
        let range = timeRange(animation)
        let clamped = max(range.min, min(range.max, percent))
        updateAnimation { changed in
            var times = normalizedTimes(changed)
            guard times.indices.contains(index) else { return }
            times[index] = Double(clamped) / 100
            changed.keyTimes = times
        }
    }

    private func removeValue(_ animation: KeyframeAnimationModel) {
        let timesBefore = normalizedTimes(animation)
        updateAnimation { changed in
            var next = currentValues(changed)
            guard next.indices.contains(index) else { return }
            next.remove(at: index)
            setValues(next, on: &changed)
            if customTimes {
                var times = timesBefore
                if times.indices.contains(index) { times.remove(at: index) }
                changed.keyTimes = times
            }
        }
    }

    private func updateValue(_ animation: KeyframeAnimationModel, transform: (AnimationValue) -> AnimationValue) {
        updateAnimation { changed in
            var next = currentValues(changed)
            guard next.indices.contains(index) else { return }
            next[index] = transform(next[index])
            setValues(next, on: &changed)
        }
    }

    private func updateAnimation(_ mutation: (inout KeyframeAnimationModel) -> Void) {
        guard let selectedID else { return }
        project.root.update(id: selectedID) { layer in
            guard let i = layer.animations.firstIndex(where: { $0.id == animationID }) else { return }
            mutation(&layer.animations[i])
        }
    }

    private func currentValues(_ animation: KeyframeAnimationModel) -> [AnimationValue] {
        animation.values ?? animation.numericValues.map(AnimationValue.number)
    }

    private func setValues(_ values: [AnimationValue], on animation: inout KeyframeAnimationModel) {
        animation.values = values
        animation.numericValues = values.compactMap { if case .number(let n) = $0 { n } else { nil } }
    }

    private func normalizedTimes(_ animation: KeyframeAnimationModel) -> [Double] {
        let count = currentValues(animation).count
        guard count > 0 else { return [] }
        if animation.keyTimes.count == count { return animation.keyTimes }
        if count == 1 { return [0] }
        return (0..<count).map { Double($0) / Double(count - 1) }
    }

    private func number(_ value: AnimationValue, _ fallback: Double) -> Double {
        if case .number(let n) = value { return n }
        return fallback
    }

    private func color(_ hex: String, set: @escaping (String) -> Void) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(caHex: hex) ?? .white) },
            set: { value in
                guard let c = UIColor(value).cgColor.components, c.count >= 3 else { return }
                set(String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255)))
            }
        )
    }
}

private struct AnimationValuesTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
