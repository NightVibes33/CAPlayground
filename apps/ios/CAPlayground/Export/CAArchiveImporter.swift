import Foundation

enum CAArchiveImportError: Error {
    case missingDocument
    case invalidCAML
}

enum CAArchiveImporter {
    static func importProject(data: Data, suggestedName: String) throws -> CAProjectDocument {
        let entries = try ZIPArchive.extract(data)
        let camlEntries = entries.filter {
            let lower = $0.path.lowercased()
            return lower.hasSuffix("/main.caml") || lower == "main.caml"
        }
        guard !camlEntries.isEmpty else { throw CAArchiveImportError.missingDocument }

        var documents: [CADocumentKind: AnimationDocument] = [:]
        for entry in camlEntries {
            let kind = documentKind(for: entry.path, fallback: documents[.floating] == nil ? .floating : .background)
            guard let document = CAMLImporter.parse(entry.data) else { continue }
            documents[kind] = document
        }

        guard let first = documents.values.first else { throw CAArchiveImportError.invalidCAML }
        let gyroEnabled = documents[.wallpaper] != nil
        let active: CADocumentKind = gyroEnabled ? .wallpaper : (documents[.floating] != nil ? .floating : .background)
        var name = suggestedName
        for suffix in [".tendies", ".ca.zip", ".zip", ".ca"] where name.lowercased().hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }

        var legacyAssets: [String: Data] = [:]
        var scopedAssets: [CADocumentKind: [String: Data]] = [:]
        for entry in entries {
            let lower = entry.path.lowercased()
            guard lower.contains("/assets/") || lower.hasPrefix("assets/") else { continue }
            let assetName = URL(fileURLWithPath: entry.path).lastPathComponent
            guard !assetName.isEmpty else { continue }
            let kind = documentKind(for: entry.path, fallback: active)
            scopedAssets[kind, default: [:]][assetName] = entry.data
            if legacyAssets[assetName] == nil { legacyAssets[assetName] = entry.data }
        }

        return CAProjectDocument(
            id: UUID(),
            name: name.isEmpty ? "Imported Wallpaper" : name,
            width: first.root.size.width,
            height: first.root.size.height,
            background: first.root.backgroundColor,
            geometryFlipped: first.root.geometryFlipped,
            gyroEnabled: gyroEnabled,
            activeCA: active,
            documents: documents,
            assets: legacyAssets,
            documentAssets: scopedAssets,
            modifiedAt: .now
        )
    }

    private static func documentKind(for path: String, fallback: CADocumentKind) -> CADocumentKind {
        let lower = path.lowercased()
        if lower.contains("background") { return .background }
        if lower.contains("floating") { return .floating }
        if lower.contains("wallpaper") { return .wallpaper }
        return fallback
    }
}

private final class CAMLImporter: NSObject, XMLParserDelegate {
    private struct LayerDraft {
        var tag: String
        var layer: LayerModel
    }

    private struct AnimationDraft {
        var keyPath: String
        var duration: Double
        var speed: Double
        var autoreverses: Bool
        var repeats: Bool
        var repeatDuration: Double?
        var calculationMode: String
        var timingFunction: String
        var keyTimes: [Double] = []
        var values: [AnimationValue] = []
    }

    private struct EmitterCellDraft {
        var cell: EmitterCellModel
    }

    private struct TransitionDraft {
        var transition: StateTransition
    }

    private var elementStack: [String] = []
    private var layerStack: [LayerDraft] = []
    private var result: LayerModel?

    private var states: [String] = []
    private var stateOverrides: [String: [StateOverride]] = [:]
    private var stateTransitions: [StateTransition] = []
    private var currentState: String?
    private var currentStateSetValue: (targetID: UUID, keyPath: String)?
    private var currentTransition: TransitionDraft?
    private var currentTransitionElement: StateTransitionElement?

    private var currentAnimation: AnimationDraft?
    private var animationLayerDepth: Int?
    private var animationSection: String?
    private var animationColorArray: [GradientStop]?

    private var currentEmitterCell: EmitterCellDraft?
    private var currentFilterIndex: Int?
    private var currentGyroDictionary: [String: String]?
    private var headerComments: [String] = []

    static func parse(_ data: Data) -> AnimationDocument? {
        let delegate = CAMLImporter()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), var root = delegate.result else { return nil }
        if root.name == "CAPlayground Root Layer", root.children.count == 1 {
            root = root.children[0]
        }
        return AnimationDocument(
            root: root,
            states: delegate.states.isEmpty ? ["Locked", "Unlock", "Sleep"] : delegate.states,
            activeState: "Base State",
            stateOverrides: delegate.stateOverrides,
            stateTransitions: delegate.stateTransitions,
            selectedID: nil,
            appearanceMode: "light",
            appearanceSplit: false,
            camlHeaderComments: delegate.headerComments.isEmpty ? nil : delegate.headerComments.joined(separator: "\n")
        )
    }

    func parser(_ parser: XMLParser, foundComment comment: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().contains("generated by caplayground") else { return }
        headerComments.append(trimmed)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let parent = elementStack.last
        elementStack.append(elementName)

        if beginStateElement(elementName, attributes: attributes) { return }
        if beginTransitionElement(elementName, attributes: attributes) { return }
        if beginAnimationElement(elementName, parent: parent, attributes: attributes) { return }
        if beginEmitterCellElement(elementName, parent: parent, attributes: attributes) { return }
        if beginStyleElement(elementName, parent: parent, attributes: attributes) { return }
        if beginFilterElement(elementName, parent: parent, attributes: attributes) { return }

        if let kind = kind(elementName, attributes: attributes) {
            beginLayer(tag: elementName, kind: kind, attributes: attributes)
            return
        }

        guard !layerStack.isEmpty else { return }
        let index = layerStack.count - 1

        switch elementName {
        case "CGImage":
            let source = attributes["src"]
            if currentEmitterCell != nil {
                currentEmitterCell?.cell.imageName = source.map(assetName)
            } else if currentAnimation != nil, animationSection == "values", let source {
                if layerStack[index].layer.kind == .basic { layerStack[index].layer.kind = .video }
                if layerStack[index].layer.framePrefix == nil { inferVideoFrameNaming(source, layerIndex: index) }
            } else if let source {
                layerStack[index].layer.imageName = assetName(source)
                if layerStack[index].layer.kind == .basic { layerStack[index].layer.kind = .image }
            }
        case "contents":
            if let source = attributes["src"] {
                layerStack[index].layer.imageName = assetName(source)
                if layerStack[index].layer.kind == .basic { layerStack[index].layer.kind = .image }
            }
        case "backgroundColor":
            if let value = attributes["value"] {
                layerStack[index].layer.backgroundColor = color(value)
                layerStack[index].layer.backgroundOpacity = number(attributes["opacity"]) ?? 1
            }
        case "font": layerStack[index].layer.fontFamily = attributes["value"]
        case "string": layerStack[index].layer.text = attributes["value"] ?? ""
        case "type":
            if layerStack[index].layer.kind == .gradient { layerStack[index].layer.gradientType = attributes["value"] ?? attributes["type"] }
        case "CGColor":
            if currentAnimation != nil, animationSection == "values" {
                appendAnimationColor(attributes)
            } else if parent == "colors", layerStack[index].layer.kind == .gradient,
                      let value = attributes["value"], let hex = color(value) {
                var stops = layerStack[index].layer.gradientStops ?? []
                stops.append(.init(color: hex, opacity: number(attributes["opacity"]) ?? 1))
                layerStack[index].layer.gradientStops = stops
            } else if currentEmitterCell != nil, let value = attributes["value"], let hex = color(value) {
                currentEmitterCell?.cell.color = hex
            }
        case "real", "integer": appendAnimationScalarIfNeeded(elementName, attributes: attributes)
        case "CGPoint":
            if currentAnimation != nil, animationSection == "values" {
                let values = numbers(attributes["value"])
                if values.count >= 2 { currentAnimation?.values.append(.point(.init(x: values[0], y: values[1]))) }
            }
        case "CGRect":
            if currentAnimation != nil, animationSection == "values" {
                let values = numbers(attributes["value"])
                if values.count >= 4 { currentAnimation?.values.append(.size(.init(width: values[2], height: values[3]))) }
            }
        case "NSArray": if currentAnimation != nil, animationSection == "values" { animationColorArray = [] }
        case "keyTimes", "values": if currentAnimation != nil { animationSection = elementName }
        case "inputIntensity":
            if let filterIndex = currentFilterIndex,
               let value = number(attributes["value"]),
               layerStack[index].layer.filters.indices.contains(filterIndex) {
                layerStack[index].layer.filters[filterIndex].value = value
            }
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { if !elementStack.isEmpty { elementStack.removeLast() } }
        if endStateElement(elementName) { return }
        if endTransitionElement(elementName) { return }
        if endAnimationElement(elementName) { return }
        if endEmitterCellElement(elementName) { return }
        if endStyleElement(elementName) { return }
        if elementName == "CAFilter" || elementName == "CIFilter" { currentFilterIndex = nil; return }
        if elementName == "keyTimes" || elementName == "values" {
            if animationSection == elementName { animationSection = nil }
            return
        }
        if elementName == "NSArray", let colors = animationColorArray {
            if currentAnimation != nil, animationSection == "values" { currentAnimation?.values.append(.colors(colors)) }
            animationColorArray = nil
            return
        }
        guard isLayerElement(elementName), let draft = layerStack.popLast() else { return }
        if layerStack.isEmpty { result = draft.layer }
        else { layerStack[layerStack.count - 1].layer.children.append(draft.layer) }
    }

    private func beginLayer(tag: String, kind: LayerKind, attributes: [String: String]) {
        let id = UUID(uuidString: attributes["id"] ?? "") ?? UUID()
        let bounds = numbers(attributes["bounds"])
        let position = numbers(attributes["position"])
        let anchor = numbers(attributes["anchorPoint"])
        let size = LayerSize(width: bounds.count >= 4 ? bounds[2] : 390, height: bounds.count >= 4 ? bounds[3] : 844)
        var layer = LayerModel(
            id: id, name: attributes["name"] ?? kind.title, kind: kind,
            position: .init(x: position.first ?? size.width / 2, y: position.count > 1 ? position[1] : size.height / 2), size: size
        )
        layer.anchorPoint = .init(x: anchor.first ?? 0.5, y: anchor.count > 1 ? anchor[1] : 0.5)
        layer.zPosition = number(attributes["zPosition"]) ?? 0
        layer.opacity = number(attributes["opacity"]) ?? 1
        layer.speed = number(attributes["speed"]) ?? 1
        layer.cornerRadius = number(attributes["cornerRadius"]) ?? 0
        layer.borderWidth = number(attributes["borderWidth"]) ?? 0
        layer.masksToBounds = attributes["masksToBounds"].map(bool) ?? false
        layer.geometryFlipped = attributes["geometryFlipped"].map(bool) ?? false
        layer.backgroundColor = color(attributes["backgroundColor"])
        layer.borderColor = color(attributes["borderColor"])
        layer.blendMode = attributes["compositingFilter"]
        layer.text = attributes["string"]
        layer.fontFamily = attributes["font"]
        layer.fontSize = number(attributes["fontSize"])
        layer.textColor = color(attributes["foregroundColor"])
        layer.textAlignment = attributes["alignmentMode"]
        layer.wrapsText = attributes["wrapped"].map(bool)
        layer.imageName = attributes["contents"].map(assetName)
        layer.contentMode = contentMode(attributes["contentsGravity"])
        layer.instanceCount = attributes["instanceCount"].flatMap(Int.init)
        layer.instanceDelay = number(attributes["instanceDelay"])
        layer.emitterPosition = point(attributes["emitterPosition"])
        layer.emitterSize = sizeValue(attributes["emitterSize"])
        layer.emitterShape = attributes["emitterShape"]
        layer.emitterMode = attributes["emitterMode"]
        layer.renderMode = attributes["renderMode"]
        layer.gradientType = attributes["type"]
        layer.gradientStart = point(attributes["startPoint"])
        layer.gradientEnd = point(attributes["endPoint"])
        layer.frameCount = attributes["caplayFrameCount"].flatMap(Int.init)
        layer.framesPerSecond = number(attributes["caplayFPS"])
        layer.videoDuration = number(attributes["caplayDuration"])
        layer.framePrefix = attributes["caplayFramePrefix"]
        layer.frameExtension = attributes["caplayFrameExtension"]
        layer.calculationMode = attributes["calculationMode"]
        layer.autoReverses = attributes["caplayAutoReverses"].map(bool)
        layer.syncWithState = attributes["caplaySyncWWithState"].map(bool)
        layer.currentFrameIndex = attributes["caplayCurrentFrameIndex"].flatMap(Int.init)
        if let json = attributes["caplaySyncStateFrameMode"]?.data(using: .utf8) { layer.syncStateFrameMode = try? JSONDecoder().decode([String: String].self, from: json) }
        applyTransform(attributes, to: &layer)
        applyReplicatorTransform(attributes, to: &layer)
        layerStack.append(.init(tag: tag, layer: layer))
    }

    private func beginAnimationElement(_ elementName: String, parent: String?, attributes: [String: String]) -> Bool {
        let isAnimationContainerItem = parent == "animations" && (elementName == "CAKeyframeAnimation" || elementName == "animation" || elementName == "p")
        guard isAnimationContainerItem else { return false }
        let type = attributes["type"] ?? elementName
        guard type == "CAKeyframeAnimation" || elementName == "CAKeyframeAnimation", !layerStack.isEmpty else { return false }
        let repeatCount = attributes["repeatCount"]
        let repeatDurationRaw = attributes["repeatDuration"]
        let repeats = repeatCount == "inf" || repeatCount == "infinity" || repeatDurationRaw == "inf" || repeatDurationRaw == "infinity"
        currentAnimation = AnimationDraft(
            keyPath: attributes["keyPath"] ?? "position", duration: number(attributes["duration"]) ?? 1,
            speed: number(attributes["speed"]) ?? 1, autoreverses: attributes["autoreverses"].map(bool) ?? false,
            repeats: repeats, repeatDuration: repeats ? nil : number(repeatDurationRaw),
            calculationMode: attributes["calculationMode"] ?? "linear", timingFunction: attributes["timingFunction"] ?? "linear"
        )
        animationLayerDepth = layerStack.count
        return true
    }

    private func endAnimationElement(_ elementName: String) -> Bool {
        guard let draft = currentAnimation, ["CAKeyframeAnimation", "animation", "p"].contains(elementName), animationLayerDepth == layerStack.count, !layerStack.isEmpty else { return false }
        let keyTimes: [Double]
        if draft.keyTimes.isEmpty {
            let denominator = max(draft.values.count - 1, 1)
            keyTimes = draft.values.indices.map { Double($0) / Double(denominator) }
        } else { keyTimes = Array(draft.keyTimes.prefix(draft.values.count)) }
        let numericValues = draft.values.compactMap { value -> Double? in if case .number(let number) = value { return number }; return nil }
        layerStack[layerStack.count - 1].layer.animations.append(KeyframeAnimationModel(
            enabled: true, keyPath: draft.keyPath, numericValues: numericValues, values: draft.values.isEmpty ? nil : draft.values,
            keyTimes: keyTimes, duration: draft.duration, autoreverses: draft.autoreverses, repeats: draft.repeats,
            calculationMode: draft.calculationMode, timingFunction: draft.timingFunction, repeatDurationSeconds: draft.repeatDuration, speed: draft.speed
        ))
        currentAnimation = nil; animationLayerDepth = nil; animationSection = nil; animationColorArray = nil
        return true
    }

    private func appendAnimationScalarIfNeeded(_ elementName: String, attributes: [String: String]) {
        guard var animation = currentAnimation, let raw = number(attributes["value"]) else { return }
        if animationSection == "keyTimes" { animation.keyTimes.append(raw) }
        else if animationSection == "values" { animation.values.append(.number(animation.keyPath.hasPrefix("transform.rotation") ? raw * 180 / .pi : raw)) }
        else { return }
        currentAnimation = animation
    }

    private func appendAnimationColor(_ attributes: [String: String]) {
        guard let value = attributes["value"], let hex = color(value) else { return }
        let stop = GradientStop(color: hex, opacity: number(attributes["opacity"]) ?? 1)
        if animationColorArray != nil { animationColorArray?.append(stop) } else { currentAnimation?.values.append(.color(hex)) }
    }

    private func beginStateElement(_ elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "LKState":
            let name = attributes["name"] ?? "State"; currentState = name
            if !states.contains(name), !name.lowercased().hasPrefix("base") { states.append(name) }
            return true
        case "LKStateSetValue":
            guard let target = UUID(uuidString: attributes["targetId"] ?? ""), let keyPath = attributes["keyPath"] else { return true }
            currentStateSetValue = (target, keyPath); return true
        case "value":
            guard let state = currentState, let setValue = currentStateSetValue else { return false }
            let type = attributes["type"] ?? "real", raw = attributes["value"] ?? ""
            let value: OverrideValue
            if type == "string" { value = .string(raw) }
            else if type == "CGColor" { value = .string(color(raw) ?? raw) }
            else if let number = Double(raw) { value = .number(setValue.keyPath.hasPrefix("transform.rotation") ? number * 180 / .pi : number) }
            else { value = .string(raw) }
            stateOverrides[state, default: []].append(.init(targetID: setValue.targetID, keyPath: setValue.keyPath, value: value))
            return true
        default: return false
        }
    }

    private func endStateElement(_ elementName: String) -> Bool {
        switch elementName { case "LKStateSetValue": currentStateSetValue = nil; return true; case "LKState": currentState = nil; return true; default: return false }
    }

    private func beginTransitionElement(_ elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "LKStateTransition":
            currentTransition = .init(transition: .init(fromState: attributes["fromState"] ?? "Locked", toState: attributes["toState"] ?? "Unlock", elements: [])); return true
        case "LKStateTransitionElement":
            guard currentTransition != nil, let target = UUID(uuidString: attributes["targetId"] ?? "") else { return true }
            currentTransitionElement = .init(targetID: target, keyPath: attributes["key"] ?? attributes["keyPath"] ?? "position", animation: nil); return true
        case "animation":
            guard currentTransition != nil, currentTransitionElement != nil, elementStack.dropLast().contains("LKStateTransition") else { return false }
            currentTransitionElement?.animation = SpringAnimationModel(
                type: attributes["type"] ?? "CASpringAnimation", damping: number(attributes["damping"]) ?? 10,
                mass: number(attributes["mass"]) ?? 1, stiffness: number(attributes["stiffness"]) ?? 100,
                initialVelocity: number(attributes["velocity"]) ?? number(attributes["initialVelocity"]) ?? 0,
                duration: number(attributes["duration"]), fillMode: attributes["fillMode"], keyPath: attributes["keyPath"],
                micaAutorecalculatesDuration: attributes["mica_autorecalculatesDuration"].map(bool)
            ); return true
        default: return false
        }
    }

    private func endTransitionElement(_ elementName: String) -> Bool {
        switch elementName {
        case "LKStateTransitionElement": if let element = currentTransitionElement { currentTransition?.transition.elements.append(element) }; currentTransitionElement = nil; return true
        case "LKStateTransition": if let transition = currentTransition?.transition { stateTransitions.append(transition) }; currentTransition = nil; return true
        default: return false
        }
    }

    private func beginEmitterCellElement(_ elementName: String, parent: String?, attributes: [String: String]) -> Bool {
        guard elementName == "CAEmitterCell", parent == "emitterCells" else { return false }
        currentEmitterCell = .init(cell: EmitterCellModel(
            name: attributes["name"] ?? "Particle", imageName: nil,
            birthRate: number(attributes["birthRate"]) ?? 18, lifetime: number(attributes["lifetime"]) ?? 2.5,
            lifetimeRange: number(attributes["lifetimeRange"]) ?? 0, velocity: number(attributes["velocity"]) ?? 45,
            velocityRange: number(attributes["velocityRange"]) ?? 25, emissionLongitude: number(attributes["emissionLongitude"]) ?? 0,
            emissionLatitude: number(attributes["emissionLatitude"]) ?? 0, emissionRange: number(attributes["emissionRange"]) ?? 360,
            scale: number(attributes["scale"]) ?? 0.03, scaleRange: number(attributes["scaleRange"]) ?? 0.02,
            scaleSpeed: number(attributes["scaleSpeed"]) ?? 0, alphaRange: number(attributes["alphaRange"]) ?? 0,
            alphaSpeed: number(attributes["alphaSpeed"]) ?? -0.35, spin: number(attributes["spin"]) ?? 0,
            spinRange: number(attributes["spinRange"]) ?? 0, xAcceleration: number(attributes["xAcceleration"]) ?? 0,
            yAcceleration: number(attributes["yAcceleration"]) ?? 0, color: color(attributes["color"]) ?? "#FFFFFF"
        )); return true
    }

    private func endEmitterCellElement(_ elementName: String) -> Bool {
        guard elementName == "CAEmitterCell", let draft = currentEmitterCell else { return false }
        if !layerStack.isEmpty { var cells = layerStack[layerStack.count - 1].layer.emitterCells ?? []; cells.append(draft.cell); layerStack[layerStack.count - 1].layer.emitterCells = cells }
        currentEmitterCell = nil; return true
    }

    private func beginFilterElement(_ elementName: String, parent: String?, attributes: [String: String]) -> Bool {
        guard !layerStack.isEmpty else { return false }
        let index = layerStack.count - 1
        if elementName == "compositingFilter" { layerStack[index].layer.blendMode = attributes["filter"] ?? attributes["name"]; return true }
        guard (elementName == "CAFilter" || elementName == "CIFilter"), parent == "filters" else { return false }
        let type = attributes["filter"] ?? attributes["name"] ?? (elementName == "CIFilter" ? "CISepiaTone" : "")
        let rawValue: Double
        if type == "gaussianBlur" { rawValue = number(attributes["inputRadius"]) ?? 0 }
        else if type == "colorContrast" || type == "colorSaturate" { rawValue = number(attributes["inputAmount"]) ?? 1 }
        else if type == "colorHueRotate" { rawValue = (number(attributes["inputAngle"]) ?? 0) * 180 / .pi }
        else { rawValue = number(attributes["inputIntensity"]) ?? 1 }
        layerStack[index].layer.filters.append(.init(type: type, value: rawValue, enabled: attributes["enabled"].map(bool) ?? true))
        currentFilterIndex = layerStack[index].layer.filters.count - 1; return true
    }

    private func beginStyleElement(_ elementName: String, parent: String?, attributes: [String: String]) -> Bool {
        if elementName == "NSDictionary", parent == "wallpaperParallaxGroups" { currentGyroDictionary = [:]; return true }
        guard currentGyroDictionary != nil, ["axis", "image", "keyPath", "layerName", "mapMaxTo", "mapMinTo", "title", "view"].contains(elementName) else { return false }
        currentGyroDictionary?[elementName] = attributes["value"] ?? ""; return true
    }

    private func endStyleElement(_ elementName: String) -> Bool {
        guard elementName == "NSDictionary", let dictionary = currentGyroDictionary else { return false }
        defer { currentGyroDictionary = nil }
        guard !layerStack.isEmpty, let layerName = dictionary["layerName"] else { return true }
        var gyros = layerStack[layerStack.count - 1].layer.gyroDictionaries ?? []
        gyros.append(.init(axis: dictionary["axis"] ?? "x", keyPath: dictionary["keyPath"] ?? "position.x", layerName: layerName,
                           mapMinTo: Double(dictionary["mapMinTo"] ?? "") ?? -50, mapMaxTo: Double(dictionary["mapMaxTo"] ?? "") ?? 50,
                           title: dictionary["title"] ?? "Tilt Effect", view: dictionary["view"] ?? "Wallpaper"))
        layerStack[layerStack.count - 1].layer.gyroDictionaries = gyros; return true
    }

    private func kind(_ name: String, attributes: [String: String]) -> LayerKind? {
        switch name {
        case "CAGradientLayer": return .gradient
        case "CAEmitterLayer": return .emitter
        case "CATransformLayer": return .transform
        case "CAReplicatorLayer": return .replicator
        case "CATextLayer": return .text
        case "CABackdropLayer": return attributes["caplayKind"] == "liquidGlass" ? .liquidGlass : .basic
        case "CALayer":
            if attributes["caplayKind"] == "video" { return .video }
            if attributes["caplayKind"] == "image" { return .image }
            if attributes["caplayKind"] == "shape" { return .shape }
            return .basic
        default: return nil
        }
    }

    private func isLayerElement(_ name: String) -> Bool { ["CAGradientLayer", "CAEmitterLayer", "CATransformLayer", "CAReplicatorLayer", "CATextLayer", "CABackdropLayer", "CALayer"].contains(name) }

    private func applyTransform(_ attributes: [String: String], to layer: inout LayerModel) {
        if let z = number(attributes["transform.rotation.z"]) { layer.rotation = z * 180 / .pi }
        if let x = number(attributes["transform.rotation.x"]) { layer.rotationX = x * 180 / .pi }
        if let y = number(attributes["transform.rotation.y"]) { layer.rotationY = y * 180 / .pi }
        guard let transform = attributes["transform"] else { return }
        if let scale = capture(#"scale\(\s*([-+0-9.eE]+)"#, in: transform).flatMap(Double.init) { layer.scale = scale }
        if attributes["transform.rotation.z"] == nil, let degrees = capture(#"rotate\(\s*([-+0-9.eE]+)deg"#, in: transform).flatMap(Double.init) { layer.rotation = degrees }
        if attributes["transform.rotation.y"] == nil, let degrees = capture(#"rotate\(\s*([-+0-9.eE]+)deg\s*,\s*0\s*,\s*1\s*,\s*0"#, in: transform).flatMap(Double.init) { layer.rotationY = degrees }
        if attributes["transform.rotation.x"] == nil, let degrees = capture(#"rotate\(\s*([-+0-9.eE]+)deg\s*,\s*1\s*,\s*0\s*,\s*0"#, in: transform).flatMap(Double.init) { layer.rotationX = degrees }
    }

    private func applyReplicatorTransform(_ attributes: [String: String], to layer: inout LayerModel) {
        if let perspective = attributes["sublayerTransform"].flatMap({ capture(#"perspective\(\s*([-+0-9.eE]+)"#, in: $0) }).flatMap(Double.init) { layer.perspective = perspective }
        guard let transform = attributes["instanceTransform"] else { return }
        if let values = captureGroups(#"translate\(\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)"#, in: transform), values.count == 3 {
            layer.instanceTranslationX = Double(values[0]) ?? 0; layer.instanceTranslationY = Double(values[1]) ?? 0; layer.instanceTranslationZ = Double(values[2]) ?? 0
        }
        if let rotation = capture(#"rotate\(\s*([-+0-9.eE]+)deg"#, in: transform).flatMap(Double.init) { layer.instanceRotation = rotation }
    }

    private func inferVideoFrameNaming(_ source: String, layerIndex: Int) {
        let file = assetName(source), ext = "." + URL(fileURLWithPath: file).pathExtension
        let base = (file as NSString).deletingPathExtension
        let prefix = base.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
        layerStack[layerIndex].layer.framePrefix = prefix; layerStack[layerIndex].layer.frameExtension = ext == "." ? ".jpg" : ext
    }

    private func assetName(_ value: String) -> String { URL(fileURLWithPath: value).lastPathComponent }
    private func numbers(_ value: String?) -> [Double] { value?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) } ?? [] }
    private func number(_ value: String?) -> Double? { value.flatMap(Double.init) }
    private func bool(_ value: String) -> Bool { value == "1" || value.lowercased() == "true" || value.lowercased() == "yes" }

    private func color(_ value: String?) -> String? {
        let components = numbers(value); guard components.count >= 3 else { return nil }
        let r = min(max(components[0], 0), 1), g = min(max(components[1], 0), 1), b = min(max(components[2], 0), 1)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func point(_ value: String?) -> Vector2? { let values = numbers(value); guard values.count >= 2 else { return nil }; return .init(x: values[0], y: values[1]) }
    private func sizeValue(_ value: String?) -> LayerSize? { let values = numbers(value); guard values.count >= 2 else { return nil }; return .init(width: values[0], height: values[1]) }
    private func contentMode(_ gravity: String?) -> String? { switch gravity { case "resizeAspect": return "contain"; case "resizeAspectFill": return "cover"; case "center": return "none"; case "resize": return "fill"; default: return nil } }
    private func capture(_ pattern: String, in text: String) -> String? { captureGroups(pattern, in: text)?.first }
    private func captureGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var values: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index); guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }; values.append(String(text[swiftRange]))
        }
        return values
    }
}
