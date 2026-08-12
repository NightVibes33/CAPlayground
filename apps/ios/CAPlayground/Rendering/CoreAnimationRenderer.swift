import UIKit
import QuartzCore
import CoreImage

@MainActor
final class CoreAnimationRenderer {
    private(set) var renderedLayers: [UUID: CALayer] = [:]
    private var selectableIDs: Set<UUID> = []
    private var assets: [String: Data] = [:]

    func render(project: CAProjectDocument, showBackground: Bool, into host: CALayer) {
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        renderedLayers.removeAll(keepingCapacity: true)
        selectableIDs.removeAll(keepingCapacity: true)
        host.backgroundColor = UIColor(caHex: project.background ?? "#F3F4F6")?.cgColor

        if showBackground, project.activeCA == .floating, let background = project.documents[.background] {
            assets = project.assets(for: .background)
            let backgroundRoot = makeLayer(from: background.root, selectable: false)
            backgroundRoot.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
            backgroundRoot.position = CGPoint(x: CGFloat(project.width / 2), y: CGFloat(project.height / 2))
            host.addSublayer(backgroundRoot)
            apply(state: project.activeState, document: background)
        }

        assets = project.assets(for: project.activeCA)
        let root = makeLayer(from: project.root)
        root.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
        root.position = CGPoint(x: CGFloat(project.width / 2), y: CGFloat(project.height / 2))
        host.addSublayer(root)
        apply(state: project.activeState, document: project.documents[project.activeCA]!)
    }

    func layer(for id: UUID) -> CALayer? { renderedLayers[id] }
    func isSelectable(_ id: UUID) -> Bool { selectableIDs.contains(id) }

    func applyGyro(project: CAProjectDocument, x: Double, y: Double) {
        let all = flatten(project.root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for owner in all {
            for dictionary in owner.gyroDictionaries ?? [] {
                let targetModel = all.first(where: { $0.name == dictionary.layerName }) ?? owner
                guard let target = renderedLayers[targetModel.id] else { continue }
                let input = dictionary.axis == "y" ? y : x
                let normalized = min(max((input + 1) / 2, 0), 1)
                let value = dictionary.mapMinTo + (dictionary.mapMaxTo - dictionary.mapMinTo) * normalized
                switch dictionary.keyPath {
                case "position.x": target.position.x = CGFloat(value)
                case "position.y": target.position.y = CGFloat(value)
                case "transform.rotation.x": target.setValue(value * .pi / 180, forKeyPath: "transform.rotation.x")
                case "transform.rotation.y": target.setValue(value * .pi / 180, forKeyPath: "transform.rotation.y")
                case "transform.rotation.z": target.setValue(value * .pi / 180, forKeyPath: "transform.rotation.z")
                case "opacity": target.opacity = Float(value)
                default: target.setValue(value, forKeyPath: dictionary.keyPath)
                }
            }
        }
        CATransaction.commit()
    }

    private func flatten(_ layer: LayerModel) -> [LayerModel] { [layer] + layer.children.flatMap(flatten) }

    private func makeLayer(from model: LayerModel, selectable: Bool = true) -> CALayer {
        let layer: CALayer
        switch model.kind {
        case .basic: layer = CALayer()
        case .shape: layer = makeShapeLayer(model)
        case .image: layer = makeImageLayer(model)
        case .text: layer = makeTextLayer(model)
        case .gradient: layer = makeGradientLayer(model)
        case .video: layer = makeFrameSequenceLayer(model)
        case .emitter: layer = makeEmitterLayer(model)
        case .transform: layer = CATransformLayer()
        case .replicator: layer = makeReplicatorLayer(model)
        case .liquidGlass: layer = makePublicGlassFallbackLayer(model)
        }

        renderedLayers[model.id] = layer
        if selectable { selectableIDs.insert(model.id) }
        layer.name = model.id.uuidString
        applyCommon(model, to: layer)
        model.children.forEach { layer.addSublayer(makeLayer(from: $0, selectable: selectable)) }
        applyAnimations(model.animations, to: layer)
        return layer
    }

    private func applyCommon(_ model: LayerModel, to layer: CALayer) {
        layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(model.size.width), height: CGFloat(model.size.height))
        layer.position = CGPoint(x: CGFloat(model.position.x), y: CGFloat(model.position.y))
        layer.zPosition = CGFloat(model.zPosition)
        layer.opacity = model.isVisible ? Float(model.opacity) : 0
        layer.speed = Float(model.speed)
        layer.anchorPoint = CGPoint(x: model.anchorPoint.x, y: model.anchorPoint.y)
        layer.backgroundColor = UIColor(caHex: model.backgroundColor)?.withAlphaComponent(CGFloat(model.backgroundOpacity)).cgColor
        layer.borderColor = UIColor(caHex: model.borderColor)?.cgColor
        layer.borderWidth = CGFloat(model.borderWidth)
        layer.cornerRadius = CGFloat(model.cornerRadius)
        layer.masksToBounds = model.masksToBounds
        layer.isGeometryFlipped = model.geometryFlipped
        layer.compositingFilter = publicCompositingFilter(named: model.blendMode)
        layer.filters = model.filters.compactMap { filter in
            guard filter.enabled else { return nil }
            switch filter.type {
            case "gaussianBlur": return CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: filter.value])
            case "colorContrast": return CIFilter(name: "CIColorControls", parameters: [kCIInputContrastKey: filter.value])
            case "colorSaturate": return CIFilter(name: "CIColorControls", parameters: [kCIInputSaturationKey: filter.value])
            case "colorHueRotate": return CIFilter(name: "CIHueAdjust", parameters: [kCIInputAngleKey: filter.value * .pi / 180])
            case "colorInvert": return CIFilter(name: "CIColorInvert")
            case "CISepiaTone": return CIFilter(name: "CISepiaTone", parameters: [kCIInputIntensityKey: filter.value])
            default: return nil
            }
        }

        var transform = CATransform3DIdentity
        if let perspective = model.perspective, perspective != 0 { transform.m34 = CGFloat(-1 / perspective) }
        transform = CATransform3DScale(transform, CGFloat(model.scale), CGFloat(model.scale), 1)
        transform = CATransform3DRotate(transform, CGFloat(model.rotationX * .pi / 180), 1, 0, 0)
        transform = CATransform3DRotate(transform, CGFloat(model.rotationY * .pi / 180), 0, 1, 0)
        transform = CATransform3DRotate(transform, CGFloat(model.rotation * .pi / 180), 0, 0, 1)
        layer.transform = transform
    }

    private func makeShapeLayer(_ model: LayerModel) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let rect = CGRect(x: 0, y: 0, width: CGFloat(model.size.width), height: CGFloat(model.size.height))
        switch model.shape ?? "rect" {
        case "circle": layer.path = UIBezierPath(ovalIn: rect).cgPath
        case "rounded-rect": layer.path = UIBezierPath(roundedRect: rect, cornerRadius: CGFloat(model.cornerRadius)).cgPath
        default: layer.path = UIBezierPath(rect: rect).cgPath
        }
        layer.fillColor = UIColor(caHex: model.fillColor)?.cgColor
        layer.strokeColor = UIColor(caHex: model.strokeColor)?.cgColor
        layer.lineWidth = CGFloat(model.strokeWidth ?? 0)
        return layer
    }

    private func makeImageLayer(_ model: LayerModel) -> CALayer {
        let layer = CALayer()
        if let name = model.imageName, let image = assets[name].flatMap(UIImage.init(data:)) ?? UIImage(named: name) { layer.contents = image.cgImage }
        layer.contentsGravity = switch model.contentMode {
        case "contain": .resizeAspect
        case "fill": .resize
        case "none": .center
        default: .resizeAspectFill
        }
        return layer
    }

    private func makeTextLayer(_ model: LayerModel) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = model.text ?? "Text"
        layer.font = UIFont(name: model.fontFamily ?? "SFProText-Regular", size: CGFloat(model.fontSize ?? 32))
        layer.fontSize = CGFloat(model.fontSize ?? 32)
        layer.foregroundColor = UIColor(caHex: model.textColor ?? "#FFFFFF")?.cgColor
        layer.alignmentMode = switch model.textAlignment {
        case "center": .center
        case "right": .right
        case "justified": .justified
        default: .left
        }
        layer.isWrapped = model.wrapsText ?? true
        layer.contentsScale = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.scale }.first ?? 2
        return layer
    }

    private func makeGradientLayer(_ model: LayerModel) -> CAGradientLayer {
        let layer = CAGradientLayer()
        let stops = model.gradientStops ?? [.init(color: "#6366F1", opacity: 1), .init(color: "#5AD197", opacity: 1)]
        layer.colors = stops.compactMap { UIColor(caHex: $0.color)?.withAlphaComponent($0.opacity).cgColor }
        layer.locations = stops.indices.map { NSNumber(value: Double($0) / Double(max(stops.count - 1, 1))) }
        layer.startPoint = CGPoint(x: CGFloat(model.gradientStart?.x ?? 0), y: CGFloat(model.gradientStart?.y ?? 0))
        layer.endPoint = CGPoint(x: CGFloat(model.gradientEnd?.x ?? 1), y: CGFloat(model.gradientEnd?.y ?? 1))
        layer.type = switch model.gradientType { case "radial": .radial; case "conic": .conic; default: .axial }
        return layer
    }

    private func makeFrameSequenceLayer(_ model: LayerModel) -> CALayer {
        let layer = CALayer()
        guard let prefix = model.framePrefix ?? model.imageName, let count = model.frameCount, count > 0 else { return layer }
        let ext = model.frameExtension ?? ""
        let frames = (0..<count).compactMap { index in
            let name = "\(prefix)\(index)\(ext)"
            return (assets[name].flatMap(UIImage.init(data:)) ?? UIImage(named: name))?.cgImage
        }
        guard !frames.isEmpty else { return layer }
        let current = min(max(model.currentFrameIndex ?? 0, 0), frames.count - 1)
        layer.contents = frames[current]
        if model.syncWithState ?? false { return layer }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.duration = model.videoDuration ?? (Double(frames.count) / max(model.framesPerSecond ?? 30, 1))
        animation.calculationMode = CAAnimationCalculationMode(rawValue: model.calculationMode ?? "discrete")
        animation.autoreverses = model.autoReverses ?? false
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "frames")
        return layer
    }

    private func makeEmitterLayer(_ model: LayerModel) -> CAEmitterLayer {
        let layer = CAEmitterLayer()
        layer.emitterPosition = CGPoint(x: CGFloat(model.emitterPosition?.x ?? model.size.width / 2), y: CGFloat(model.emitterPosition?.y ?? model.size.height / 2))
        layer.emitterSize = CGSize(width: CGFloat(model.emitterSize?.width ?? 1), height: CGFloat(model.emitterSize?.height ?? 1))
        layer.emitterShape = CAEmitterLayerEmitterShape(rawValue: model.emitterShape ?? "point")
        layer.emitterMode = CAEmitterLayerEmitterMode(rawValue: model.emitterMode ?? "volume")
        layer.renderMode = CAEmitterLayerRenderMode(rawValue: model.renderMode ?? "unordered")
        let emitterCells = model.emitterCells ?? [EmitterCellModel()]
        layer.emitterCells = emitterCells.map { cellModel in
            let cell = CAEmitterCell(); cell.name = cellModel.name; cell.birthRate = Float(cellModel.birthRate)
            cell.contentsScale = CGFloat(cellModel.contentsScale)
            cell.lifetime = Float(cellModel.lifetime); cell.lifetimeRange = Float(cellModel.lifetimeRange)
            cell.velocity = CGFloat(cellModel.velocity); cell.velocityRange = CGFloat(cellModel.velocityRange)
            cell.emissionLongitude = CGFloat(cellModel.emissionLongitude * .pi / 180); cell.emissionLatitude = CGFloat(cellModel.emissionLatitude * .pi / 180); cell.emissionRange = CGFloat(cellModel.emissionRange * .pi / 180)
            cell.scale = CGFloat(cellModel.scale); cell.scaleRange = CGFloat(cellModel.scaleRange); cell.scaleSpeed = CGFloat(cellModel.scaleSpeed)
            cell.alphaRange = Float(cellModel.alphaRange); cell.alphaSpeed = Float(cellModel.alphaSpeed)
            cell.spin = CGFloat(cellModel.spin * .pi / 180); cell.spinRange = CGFloat(cellModel.spinRange * .pi / 180)
            cell.xAcceleration = CGFloat(cellModel.xAcceleration); cell.yAcceleration = CGFloat(cellModel.yAcceleration)
            cell.redRange = Float(cellModel.redRange); cell.redSpeed = Float(cellModel.redSpeed)
            cell.greenRange = Float(cellModel.greenRange); cell.greenSpeed = Float(cellModel.greenSpeed)
            cell.blueRange = Float(cellModel.blueRange); cell.blueSpeed = Float(cellModel.blueSpeed)
            let alpha = min(max(cellModel.alpha, 0), 1)
            cell.color = UIColor(caHex: cellModel.color)?.withAlphaComponent(CGFloat(alpha)).cgColor
            cell.contents = cellModel.imageName.flatMap { name in assets[name].flatMap(UIImage.init(data:)) ?? UIImage(named: name) }?.cgImage ?? UIImage(systemName: "sparkle")?.withTintColor(.white).cgImage
            return cell
        }
        return layer
    }

    private func makeReplicatorLayer(_ model: LayerModel) -> CAReplicatorLayer {
        let layer = CAReplicatorLayer()
        layer.instanceCount = model.instanceCount ?? 1
        layer.instanceDelay = model.instanceDelay ?? 0
        var transform = CATransform3DMakeTranslation(CGFloat(model.instanceTranslationX ?? 0), CGFloat(model.instanceTranslationY ?? 0), CGFloat(model.instanceTranslationZ ?? 0))
        transform = CATransform3DRotate(transform, CGFloat((model.instanceRotation ?? 0) * .pi / 180), 0, 0, 1)
        layer.instanceTransform = transform
        return layer
    }

    private func makePublicGlassFallbackLayer(_ model: LayerModel) -> CALayer {
        let layer = CAGradientLayer()
        layer.colors = [UIColor.white.withAlphaComponent(0.24).cgColor, UIColor.white.withAlphaComponent(0.08).cgColor]
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.borderWidth = CGFloat(max(model.borderWidth, 0.5))
        return layer
    }

    private func applyAnimations(_ models: [KeyframeAnimationModel], to layer: CALayer) {
        for model in models where model.enabled && !(model.values ?? model.numericValues.map(AnimationValue.number)).isEmpty {
            let animation = CAKeyframeAnimation(keyPath: model.keyPath)
            animation.values = (model.values ?? model.numericValues.map(AnimationValue.number)).compactMap { value in
                switch value {
                case .number(let number): return NSNumber(value: model.keyPath.hasPrefix("transform.rotation") ? number * .pi / 180 : number)
                case .point(let point): return NSValue(cgPoint: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
                case .size(let size): return NSValue(cgRect: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)))
                case .color(let hex): return UIColor(caHex: hex)?.cgColor
                case .colors(let stops): return stops.compactMap { UIColor(caHex: $0.color)?.withAlphaComponent(CGFloat($0.opacity)).cgColor }
                }
            }
            animation.keyTimes = model.keyTimes.map(NSNumber.init(value:))
            animation.duration = model.duration
            animation.speed = Float(model.speed)
            animation.autoreverses = model.autoreverses
            animation.repeatCount = model.repeats ? .infinity : 0
            if let repeatDuration = model.repeatDurationSeconds, repeatDuration > 0 { animation.repeatDuration = repeatDuration }
            animation.calculationMode = CAAnimationCalculationMode(rawValue: model.calculationMode)
            animation.timingFunction = CAMediaTimingFunction(name: timingName(model.timingFunction))
            layer.add(animation, forKey: "caplayground.\(model.id.uuidString)")
        }
    }

    private func apply(state: String, document: AnimationDocument) {
        guard let overrides = document.stateOverrides[state] else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for override in overrides {
            guard let layer = renderedLayers[override.targetID] else { continue }
            switch (override.keyPath, override.value) {
            case ("opacity", .number(let value)): layer.opacity = Float(value)
            case ("position.x", .number(let value)): layer.position.x = CGFloat(value)
            case ("position.y", .number(let value)): layer.position.y = CGFloat(value)
            case ("zPosition", .number(let value)): layer.zPosition = CGFloat(value)
            case ("bounds.size.width", .number(let value)): layer.bounds.size.width = CGFloat(value)
            case ("bounds.size.height", .number(let value)): layer.bounds.size.height = CGFloat(value)
            case ("cornerRadius", .number(let value)): layer.cornerRadius = CGFloat(value)
            case ("transform.scale.xy", .number(let value)): layer.setValue(value, forKeyPath: "transform.scale")
            case ("transform.rotation.z", .number(let value)): layer.setValue(value * .pi / 180, forKeyPath: "transform.rotation.z")
            case ("transform.rotation.x", .number(let value)): layer.setValue(value * .pi / 180, forKeyPath: "transform.rotation.x")
            case ("transform.rotation.y", .number(let value)): layer.setValue(value * .pi / 180, forKeyPath: "transform.rotation.y")
            case ("backgroundColor", .string(let value)): layer.backgroundColor = UIColor(caHex: value)?.cgColor
            default: break
            }
        }
        CATransaction.commit()
    }

    private func timingName(_ value: String) -> CAMediaTimingFunctionName {
        switch value { case "easeIn": .easeIn; case "easeOut": .easeOut; case "easeInEaseOut": .easeInEaseOut; default: .linear }
    }

    private func publicCompositingFilter(named name: String?) -> String? {
        switch name {
        case "colorBlendMode", "colorBurnBlendMode", "colorDodgeBlendMode", "darkenBlendMode", "differenceBlendMode", "exclusionBlendMode", "hueBlendMode", "lightenBlendMode", "luminosityBlendMode", "multiplyBlendMode", "overlayBlendMode", "saturationBlendMode", "screenBlendMode": return name
        default: return nil
        }
    }
}
