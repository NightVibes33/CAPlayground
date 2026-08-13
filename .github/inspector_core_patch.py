from pathlib import Path
import re

path = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = path.read_text()

def replace_func(name, next_name, replacement):
    global s
    pattern = re.compile(rf'''    @ViewBuilder private func {name}\(_ layer: LayerModel\) -> some View \{{.*?\n    \}}\n\n    @ViewBuilder private func {next_name}''', re.S)
    s2, count = pattern.subn(replacement + f'\n\n    @ViewBuilder private func {next_name}', s, count=1)
    if count != 1:
        raise SystemExit(f'{name} replacement count={count}')
    s = s2

replace_func('compositing', 'content', r'''    @ViewBuilder private func compositing(_ layer: LayerModel) -> some View {
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
                Button("Content → Background opacity") { activeTab = .content }.buttonStyle(.plain).underline()
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
    }''')

replace_func('content', 'text', r'''    @ViewBuilder private func content(_ layer: LayerModel) -> some View {
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
                    Button("Compositing → Opacity") { activeTab = .compositing }.buttonStyle(.plain).underline()
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
    }''')

replace_func('text', 'gradient', r'''    @ViewBuilder private func text(_ layer: LayerModel) -> some View {
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
    }''')

replace_func('gradient', 'image', r'''    @ViewBuilder private func gradient(_ layer: LayerModel) -> some View {
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
                        Slider(value: Binding(get: { selected?.gradientStops?[safe: index]?.opacity ?? stop.opacity }, set: { v in update { $0.gradientStops?[index].opacity = v } }), in: 0...1, step: 0.01)
                        Text("\(Int(((selected?.gradientStops?[safe: index]?.opacity ?? stop.opacity) * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary).frame(width: 36)
                    }
                }
                Button(role: .destructive) { update { $0.gradientStops?.remove(at: index) } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Remove color")
            }
            .padding(8).overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
        }
    }

    private enum GradientPointAxis { case x, y }

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
    }''')

path.write_text(s)
Path('.github/inspector_core_patch.py').unlink()
Path('.github/workflows/inspector-core-parity.yml').unlink()
