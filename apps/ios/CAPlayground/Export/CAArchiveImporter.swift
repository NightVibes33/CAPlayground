import Foundation

enum CAArchiveImportError: Error {
    case missingDocument
    case invalidCAML
}

enum CAArchiveImporter {
    static func importProject(data: Data, suggestedName: String) throws -> CAProjectDocument {
        let entries = try ZIPArchive.extract(data)
        let camlEntries = entries.filter { $0.path.lowercased().hasSuffix("/main.caml") || $0.path.lowercased() == "main.caml" }
        guard !camlEntries.isEmpty else { throw CAArchiveImportError.missingDocument }

        var documents: [CADocumentKind: AnimationDocument] = [:]
        for entry in camlEntries {
            let lower = entry.path.lowercased()
            let kind: CADocumentKind
            if lower.contains("background") { kind = .background }
            else if lower.contains("floating") { kind = .floating }
            else if lower.contains("wallpaper") { kind = .wallpaper }
            else { kind = documents[.floating] == nil ? .floating : .background }
            guard let root = CAMLImporter.parse(entry.data) else { continue }
            documents[kind] = AnimationDocument(root: root)
        }
        guard let first = documents.values.first else { throw CAArchiveImportError.invalidCAML }
        let gyroEnabled = documents[.wallpaper] != nil
        let active: CADocumentKind = gyroEnabled ? .wallpaper : (documents[.floating] != nil ? .floating : .background)
        let name = suggestedName.replacingOccurrences(of: ".tendies", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: ".zip", with: "", options: [.caseInsensitive])
        var assets: [String: Data] = [:]
        for entry in entries where entry.path.lowercased().contains("/assets/") {
            let name = URL(fileURLWithPath: entry.path).lastPathComponent
            if assets[name] == nil { assets[name] = entry.data }
        }
        return CAProjectDocument(
            id: UUID(), name: name.isEmpty ? "Imported Wallpaper" : name,
            width: first.root.size.width, height: first.root.size.height,
            background: first.root.backgroundColor, geometryFlipped: first.root.geometryFlipped,
            gyroEnabled: gyroEnabled, activeCA: active, documents: documents,
            assets: assets, modifiedAt: .now
        )
    }
}

private final class CAMLImporter: NSObject, XMLParserDelegate {
    private struct Draft {
        var layer: LayerModel
    }

    private var stack: [Draft] = []
    private var result: LayerModel?

    static func parse(_ data: Data) -> LayerModel? {
        let delegate = CAMLImporter()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), var root = delegate.result else { return nil }
        if root.name == "CAPlayground Root Layer", root.children.count == 1 { root = root.children[0] }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "CGImage", let src = attributes["src"], !stack.isEmpty {
            stack[stack.count - 1].layer.imageName = URL(fileURLWithPath: src).lastPathComponent
            return
        }
        guard let kind = kind(elementName, attributes: attributes) else { return }
        let id = UUID(uuidString: attributes["id"] ?? "") ?? UUID()
        let bounds = numbers(attributes["bounds"])
        let position = numbers(attributes["position"])
        let anchor = numbers(attributes["anchorPoint"])
        let size = LayerSize(width: bounds.count >= 4 ? bounds[2] : 390, height: bounds.count >= 4 ? bounds[3] : 844)
        var layer = LayerModel(
            id: id, name: attributes["name"] ?? kind.title, kind: kind,
            position: .init(x: position.first ?? size.width / 2, y: position.count > 1 ? position[1] : size.height / 2),
            size: size
        )
        layer.anchorPoint = .init(x: anchor.first ?? 0.5, y: anchor.count > 1 ? anchor[1] : 0.5)
        layer.zPosition = number(attributes["zPosition"]) ?? 0
        layer.opacity = number(attributes["opacity"]) ?? 1
        layer.speed = number(attributes["speed"]) ?? 1
        layer.cornerRadius = number(attributes["cornerRadius"]) ?? 0
        layer.borderWidth = number(attributes["borderWidth"]) ?? 0
        layer.masksToBounds = attributes["masksToBounds"] == "1"
        layer.geometryFlipped = attributes["geometryFlipped"] == "1"
        layer.backgroundColor = color(attributes["backgroundColor"])
        layer.borderColor = color(attributes["borderColor"])
        layer.blendMode = attributes["compositingFilter"]
        layer.text = attributes["string"]
        layer.fontSize = number(attributes["fontSize"])
        layer.textColor = color(attributes["foregroundColor"])
        layer.textAlignment = attributes["alignmentMode"]
        layer.wrapsText = attributes["wrapped"].map { $0 == "1" }
        layer.imageName = attributes["contents"].map { URL(fileURLWithPath: $0).lastPathComponent }
        layer.contentMode = contentMode(attributes["contentsGravity"])
        layer.instanceCount = attributes["instanceCount"].flatMap(Int.init)
        layer.instanceDelay = number(attributes["instanceDelay"])
        layer.emitterShape = attributes["emitterShape"]
        layer.emitterMode = attributes["emitterMode"]
        layer.renderMode = attributes["renderMode"]
        layer.frameCount = attributes["caplayFrameCount"].flatMap(Int.init)
        layer.framesPerSecond = number(attributes["caplayFPS"])
        layer.videoDuration = number(attributes["caplayDuration"])
        layer.framePrefix = attributes["caplayFramePrefix"]
        layer.frameExtension = attributes["caplayFrameExtension"]
        layer.autoReverses = attributes["caplayAutoReverses"].map { $0 == "1" }
        layer.syncWithState = attributes["caplaySyncWWithState"].map { $0 == "1" }
        stack.append(.init(layer: layer))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard kind(elementName, attributes: [:]) != nil, let draft = stack.popLast() else { return }
        if stack.isEmpty { result = draft.layer }
        else { stack[stack.count - 1].layer.children.append(draft.layer) }
    }

    private func kind(_ name: String, attributes: [String: String]) -> LayerKind? {
        switch name {
        case "CAGradientLayer": .gradient
        case "CAEmitterLayer": .emitter
        case "CATransformLayer": .transform
        case "CAReplicatorLayer": .replicator
        case "CATextLayer": .text
        case "CALayer": attributes["caplayKind"] == "video" ? .video : .basic
        default: nil
        }
    }

    private func numbers(_ value: String?) -> [Double] {
        value?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) } ?? []
    }

    private func number(_ value: String?) -> Double? { value.flatMap(Double.init) }

    private func color(_ value: String?) -> String? {
        let components = numbers(value)
        guard components.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
    }

    private func contentMode(_ gravity: String?) -> String? {
        switch gravity {
        case "resizeAspect": "contain"
        case "resizeAspectFill": "cover"
        case "center": "none"
        case "resize": "fill"
        default: nil
        }
    }
}
