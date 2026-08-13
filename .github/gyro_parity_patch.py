from pathlib import Path
import re

# 1) Native Gyro Inspector UI parity.
inspector = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = inspector.read_text()
pattern = re.compile(r'''    @ViewBuilder private func gyro\(_ layer: LayerModel\) -> some View \{.*?\n    \}\n\n    @ViewBuilder private func emitter''', re.S)
replacement = r'''    @ViewBuilder private func gyro(_ layer: LayerModel) -> some View {
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

    @ViewBuilder private func emitter'''
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'gyro inspector replacement count={count}')
inspector.write_text(s)

# 2) Export wallpaper style at the root, including parallax and property groups.
serializer = Path('apps/ios/CAPlayground/Export/CAMLSerializer.swift')
s = serializer.read_text()
old = '''        let wallpaper = kind == .wallpaper
        let serializedRoot = wallpaper ? layer(document.root, indent: 1) : wrapper(root: document.root)
        let stateXML = wallpaper ? "" : states(document)
'''
new = '''        let wallpaper = kind == .wallpaper
        let dictionaries = wallpaper ? document.root.flattened().flatMap { $0.gyroDictionaries ?? [] } : []
        let rootStyle = wallpaper ? wallpaperStyle(root: document.root, dictionaries: dictionaries, stateOverrides: document.stateOverrides, indent: 2) : nil
        let serializedRoot = wallpaper ? layer(document.root, indent: 1, rootStyle: rootStyle) : wrapper(root: document.root)
        let stateXML = wallpaper ? "" : states(document)
'''
if s.count(old) != 1:
    raise SystemExit(f'serializer header anchor count={s.count(old)}')
s = s.replace(old, new, 1)
old_sig = '    private static func layer(_ model: LayerModel, indent: Int) -> String {'
new_sig = '    private static func layer(_ model: LayerModel, indent: Int, rootStyle: String? = nil) -> String {'
if s.count(old_sig) != 1:
    raise SystemExit(f'layer signature count={s.count(old_sig)}')
s = s.replace(old_sig, new_sig, 1)
old_nested = '        if let gyro = model.gyroDictionaries, !gyro.isEmpty { children += style(gyro, indent: indent + 1) }\n'
if s.count(old_nested) != 1:
    raise SystemExit(f'nested gyro style count={s.count(old_nested)}')
s = s.replace(old_nested, '', 1)
old_children = '        if !model.children.isEmpty { children += "\\n\\(pad)  <sublayers>" + model.children.map { "\\n" + layer($0, indent: indent + 2) }.joined() + "\\n\\(pad)  </sublayers>" }\n'
new_children = '        if let rootStyle { children += rootStyle }\n        if !model.children.isEmpty { children += "\\n\\(pad)  <sublayers>" + model.children.map { "\\n" + layer($0, indent: indent + 2) }.joined() + "\\n\\(pad)  </sublayers>" }\n'
if s.count(old_children) != 1:
    raise SystemExit(f'sublayer anchor count={s.count(old_children)}')
s = s.replace(old_children, new_children, 1)
style_pattern = re.compile(r'''    private static func style\(_ dictionaries: \[GyroDictionaryModel\], indent: Int\) -> String \{.*?\n    \}\n\n    private static func liquidGlass''', re.S)
style_replacement = r'''    private static func wallpaperStyle(
        root: LayerModel,
        dictionaries: [GyroDictionaryModel],
        stateOverrides: [String: [StateOverride]],
        indent: Int
    ) -> String {
        let pad = String(repeating: "  ", count: indent)
        let parallax = dictionaries.map { item -> String in
            let maxType = item.mapMaxTo.rounded() == item.mapMaxTo ? "integer" : "real"
            let minType = item.mapMinTo.rounded() == item.mapMinTo ? "integer" : "real"
            let view = wallpaperView(layerName: item.layerName, root: root)
            return "\n\(pad)    <NSDictionary>" +
                "<axis type=\"string\" value=\"\(escape(item.axis))\"/>" +
                "<image type=\"string\" value=\"null\"/>" +
                "<keyPath type=\"string\" value=\"\(escape(item.keyPath))\"/>" +
                "<layerName type=\"string\" value=\"\(escape(item.layerName))\"/>" +
                "<mapMaxTo type=\"\(maxType)\" value=\"\(number(item.mapMaxTo))\"/>" +
                "<mapMinTo type=\"\(minType)\" value=\"\(number(item.mapMinTo))\"/>" +
                "<title type=\"string\" value=\"\(escape(item.title))\"/>" +
                "<view type=\"string\" value=\"\(view)\"/>" +
                "</NSDictionary>"
        }.joined()

        let locked = stateOverrides["Locked"] ?? []
        let properties = locked.compactMap { lockedOverride -> String? in
            guard let target = root.find(id: lockedOverride.targetID),
                  case .number(let lockedValue) = lockedOverride.value,
                  let homeValue = stateNumber(stateOverrides["Unlock"], targetID: lockedOverride.targetID, keyPath: lockedOverride.keyPath),
                  let sleepValue = stateNumber(stateOverrides["Sleep"], targetID: lockedOverride.targetID, keyPath: lockedOverride.keyPath) else { return nil }
            let rotation = ["transform.rotation.z", "transform.rotation.x", "transform.rotation.y"].contains(lockedOverride.keyPath)
            let lockOut = rotation ? lockedValue * .pi / 180 : lockedValue
            let homeOut = rotation ? homeValue * .pi / 180 : homeValue
            let sleepOut = rotation ? sleepValue * .pi / 180 : sleepValue
            let view = wallpaperView(targetID: lockedOverride.targetID, root: root)
            return "\n\(pad)    <NSDictionary>" +
                "<image type=\"null\"/>" +
                "<keyPath type=\"string\" value=\"\(escape(lockedOverride.keyPath))\"/>" +
                "<layerName type=\"string\" value=\"\(escape(target.name))\"/>" +
                "<v_home type=\"real\" value=\"\(number(homeOut))\"/>" +
                "<v_lock type=\"real\" value=\"\(number(lockOut))\"/>" +
                "<v_sleep type=\"real\" value=\"\(number(sleepOut))\"/>" +
                "<view type=\"string\" value=\"\(view)\"/>" +
                "</NSDictionary>"
        }.joined()

        return "\n\(pad)<style>" +
            "\n\(pad)  <wallpaperBackgroundAssetNames type=\"NSArray\"/>" +
            "\n\(pad)  <wallpaperFloatingAssetNames type=\"NSArray\"/>" +
            "\n\(pad)  <wallpaperParallaxGroups type=\"NSArray\">\(parallax)\n\(pad)  </wallpaperParallaxGroups>" +
            "\n\(pad)  <wallpaperPropertyGroups type=\"NSArray\">\(properties)\n\(pad)  </wallpaperPropertyGroups>" +
            "\n\(pad)</style>"
    }

    private static func stateNumber(_ overrides: [StateOverride]?, targetID: UUID, keyPath: String) -> Double? {
        guard let value = overrides?.last(where: { $0.targetID == targetID && $0.keyPath == keyPath })?.value,
              case .number(let number) = value else { return nil }
        return number
    }

    private static func wallpaperView(layerName: String, root: LayerModel) -> String {
        wallpaperView(root: root) { $0.name == layerName }
    }

    private static func wallpaperView(targetID: UUID, root: LayerModel) -> String {
        wallpaperView(root: root) { $0.id == targetID }
    }

    private static func wallpaperView(root: LayerModel, matches: (LayerModel) -> Bool) -> String {
        func walk(_ layer: LayerModel, background: Bool) -> String? {
            let inBackground = background || layer.name == "BACKGROUND"
            if matches(layer) { return inBackground ? "Background" : "Floating" }
            for child in layer.children {
                if let found = walk(child, background: inBackground) { return found }
            }
            return nil
        }
        return walk(root, background: false) ?? "Floating"
    }

    private static func liquidGlass'''
s, count = style_pattern.subn(style_replacement, s, count=1)
if count != 1:
    raise SystemExit(f'style replacement count={count}')
serializer.write_text(s)

# 3) Import root-level wallpaper style and redistribute dictionaries back to target layers.
importer = Path('apps/ios/CAPlayground/Export/CAArchiveImporter.swift')
s = importer.read_text()
old_vars = '''    private var currentGyroDictionary: [String: String]?
    private var headerComments: [String] = []
'''
new_vars = '''    private var currentGyroDictionary: [String: String]?
    private var currentWallpaperPropertyDictionary: [String: String]?
    private var wallpaperPropertyDictionaries: [[String: String]] = []
    private var headerComments: [String] = []
'''
if s.count(old_vars) != 1:
    raise SystemExit(f'importer vars anchor count={s.count(old_vars)}')
s = s.replace(old_vars, new_vars, 1)
old_parse = '''        guard parser.parse(), var root = delegate.result else { return nil }
        if root.name == "CAPlayground Root Layer", root.children.count == 1 { root = root.children[0] }
        return AnimationDocument(
'''
new_parse = '''        guard parser.parse(), var root = delegate.result else { return nil }
        if root.name == "CAPlayground Root Layer", root.children.count == 1 { root = root.children[0] }
        delegate.applyWallpaperStyle(to: &root)
        return AnimationDocument(
'''
if s.count(old_parse) != 1:
    raise SystemExit(f'importer parse anchor count={s.count(old_parse)}')
s = s.replace(old_parse, new_parse, 1)
old_start = '''        if beginEmitterCell(elementName, parent, attributes) { return }
        if beginGyro(elementName, parent, attributes) { return }
        if beginFilter(elementName, parent, attributes) { return }
'''
new_start = '''        if beginEmitterCell(elementName, parent, attributes) { return }
        if beginWallpaperProperty(elementName, parent, attributes) { return }
        if beginGyro(elementName, parent, attributes) { return }
        if beginFilter(elementName, parent, attributes) { return }
'''
if s.count(old_start) != 1:
    raise SystemExit(f'importer start hook count={s.count(old_start)}')
s = s.replace(old_start, new_start, 1)
old_end = '''        if endEmitterCell(elementName) { return }
        if endGyro(elementName) { return }
        if elementName == "CAFilter" || elementName == "CIFilter" { currentFilterIndex = nil; return }
'''
new_end = '''        if endEmitterCell(elementName) { return }
        if endWallpaperProperty(elementName) { return }
        if endGyro(elementName) { return }
        if elementName == "CAFilter" || elementName == "CIFilter" { currentFilterIndex = nil; return }
'''
if s.count(old_end) != 1:
    raise SystemExit(f'importer end hook count={s.count(old_end)}')
s = s.replace(old_end, new_end, 1)
gyro_marker = '    private func beginGyro(_ elementName: String, _ parent: String?, _ attributes: [String: String]) -> Bool {\n'
insert = r'''    private func beginWallpaperProperty(_ elementName: String, _ parent: String?, _ attributes: [String: String]) -> Bool {
        if elementName == "NSDictionary", parent == "wallpaperPropertyGroups" {
            currentWallpaperPropertyDictionary = [:]
            return true
        }
        guard currentWallpaperPropertyDictionary != nil,
              ["image", "keyPath", "layerName", "v_home", "v_lock", "v_sleep", "view"].contains(elementName) else { return false }
        currentWallpaperPropertyDictionary?[elementName] = attributes["value"] ?? ""
        return true
    }

    private func endWallpaperProperty(_ elementName: String) -> Bool {
        guard elementName == "NSDictionary", let dictionary = currentWallpaperPropertyDictionary else { return false }
        wallpaperPropertyDictionaries.append(dictionary)
        currentWallpaperPropertyDictionary = nil
        return true
    }

    private func applyWallpaperStyle(to root: inout LayerModel) {
        let rootDictionaries = root.gyroDictionaries ?? []
        if !rootDictionaries.isEmpty {
            root.gyroDictionaries = nil
            for dictionary in rootDictionaries {
                if let id = layerID(named: dictionary.layerName, in: root) {
                    root.update(id: id) { layer in
                        var values = layer.gyroDictionaries ?? []
                        values.append(dictionary)
                        layer.gyroDictionaries = values
                    }
                } else {
                    var values = root.gyroDictionaries ?? []
                    values.append(dictionary)
                    root.gyroDictionaries = values
                }
            }
        }

        for dictionary in wallpaperPropertyDictionaries {
            guard let layerName = dictionary["layerName"],
                  let targetID = layerID(named: layerName, in: root),
                  let keyPath = dictionary["keyPath"] else { continue }
            let rotation = ["transform.rotation.z", "transform.rotation.x", "transform.rotation.y"].contains(keyPath)
            for (state, key) in [("Locked", "v_lock"), ("Unlock", "v_home"), ("Sleep", "v_sleep")] {
                guard let raw = dictionary[key], var number = Double(raw) else { continue }
                if rotation { number *= 180 / .pi }
                var values = stateOverrides[state] ?? []
                if let index = values.firstIndex(where: { $0.targetID == targetID && $0.keyPath == keyPath }) {
                    values[index].value = .number(number)
                } else {
                    values.append(.init(targetID: targetID, keyPath: keyPath, value: .number(number)))
                }
                stateOverrides[state] = values
            }
        }
    }

    private func layerID(named name: String, in layer: LayerModel) -> UUID? {
        if layer.name == name { return layer.id }
        for child in layer.children {
            if let id = layerID(named: name, in: child) { return id }
        }
        return nil
    }

'''
if s.count(gyro_marker) != 1:
    raise SystemExit(f'gyro importer marker count={s.count(gyro_marker)}')
s = s.replace(gyro_marker, insert + gyro_marker, 1)
s = s.replace('title: dictionary["title"] ?? "Tilt Effect",', 'title: dictionary["title"] ?? "New Gyro Effect",')
importer.write_text(s)

Path('.github/gyro_parity_patch.py').unlink()
Path('.github/workflows/gyro-parity.yml').unlink()
