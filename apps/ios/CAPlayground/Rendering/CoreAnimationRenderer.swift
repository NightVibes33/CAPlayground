import UIKit
import QuartzCore

@MainActor
final class CoreAnimationRenderer {
    private(set) var renderedLayers: [UUID: CALayer] = [:]

    func render(project: CAProjectDocument, into host: CALayer) {
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        renderedLayers.removeAll(keepingCapacity: true)
        let root = makeLayer(from: project.root)
        root.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
        root.position = CGPoint(x: CGFloat(project.width / 2), y: CGFloat(project.height / 2))
        host.addSublayer(root)
        apply(state: project.activeState, project: project)
    }

    func layer(for id: UUID) -> CALayer? { renderedLayers[id] }

    private func makeLayer(from model: LayerModel) -> CALayer {
        let layer: CALayer
        switch model.kind {
        case .basic:
            layer = CALayer()
        case .shape:
            layer = makeShapeLayer(model)
        case .image:
            layer = makeImageLayer(model)
        case .text:
            layer = makeTextLayer(model)
        case .gradient:
            layer = makeGradientLayer(model)
        case .video:
            layer = makeFrameSequenceLayer(model)
        case .emitter:
            layer = makeEmitterLayer(model)
        case .transform:
            layer = CATransformLayer()
        case .replicator:
            layer = makeReplicatorLayer(model)
        case .liquidGlass:
            layer = makePublicGlassFallbackLayer(model)
        }

        renderedLayers[model.id] = layer
        layer.name = model.id.uuidString
        applyCommon(model, to: layer)
        model.children.forEach { layer.addSublayer(makeLayer(from: $0)) }
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
        layer.backgroundColor = UIColor(caHex: model.backgroundColor)?
            .withAlphaComponent(CGFloat(model.backgroundOpacity)).cgColor
        layer.borderColor = UIColor(caHex: model.borderColor)?.cgColor
        layer.borderWidth = CGFloat(model.borderWidth)
        layer.cornerRadius = CGFloat(model.cornerRadius)
        layer.masksToBounds = model.masksToBounds
        layer.isGeometryFlipped = model.geometryFlipped
        layer.compositingFilter = publicCompositingFilter(named: model.blendMode)

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
        case "rounded-rect":
            layer.path = UIBezierPath(roundedRect: rect, cornerRadius: CGFloat(model.cornerRadius)).cgPath
        default: layer.path = UIBezierPath(rect: rect).cgPath
        }
        layer.fillColor = UIColor(caHex: model.fillColor)?.cgColor
        layer.strokeColor = UIColor(caHex: model.strokeColor)?.cgColor
        layer.lineWidth = CGFloat(model.strokeWidth ?? 0)
        return layer
    }

    private func makeImageLayer(_ model: LayerModel) -> CALayer {
        let layer = CALayer()
        if let name = model.imageName, let image = UIImage(named: name) { layer.contents = image.cgImage }
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
        layer.contentsScale = UIScreen.main.scale
        return layer
    }

    private func makeGradientLayer(_ model: LayerModel) -> CAGradientLayer {
        let layer = CAGradientLayer()
        let stops = model.gradientStops ?? [
            .init(color: "#6366F1", opacity: 1), .init(color: "#5AD197", opacity: 1)
        ]
        layer.colors = stops.compactMap { UIColor(caHex: $0.color)?.withAlphaComponent($0.opacity).cgColor }
        layer.locations = stops.indices.map { NSNumber(value: Double($0) / Double(max(stops.count - 1, 1))) }
        layer.startPoint = CGPoint(x: CGFloat(model.gradientStart?.x ?? 0), y: CGFloat(model.gradientStart?.y ?? 0))
        layer.endPoint = CGPoint(x: CGFloat(model.gradientEnd?.x ?? 1), y: CGFloat(model.gradientEnd?.y ?? 1))
        layer.type = switch model.gradientType {
        case "radial": .radial
        case "conic": .conic
        default: .axial
        }
        return layer
    }

    private func makeFrameSequenceLayer(_ model: LayerModel) -> CALayer {
        let layer = CALayer()
        guard let prefix = model.imageName, let count = model.frameCount, count > 0 else { return layer }
        let frames = (0..<count).compactMap { UIImage(named: "\(prefix)\($0)")?.cgImage }
        guard !frames.isEmpty else { return layer }
        layer.contents = frames[0]
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.duration = Double(frames.count) / max(model.framesPerSecond ?? 30, 1)
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "frames")
        return layer
    }

    private func makeEmitterLayer(_ model: LayerModel) -> CAEmitterLayer {
        let layer = CAEmitterLayer()
        layer.emitterPosition = CGPoint(x: CGFloat(model.emitterPosition?.x ?? model.size.width / 2),
                                        y: CGFloat(model.emitterPosition?.y ?? model.size.height / 2))
        layer.emitterSize = CGSize(width: CGFloat(model.emitterSize?.width ?? 1), height: CGFloat(model.emitterSize?.height ?? 1))
        layer.emitterShape = CAEmitterLayerEmitterShape(rawValue: model.emitterShape ?? "point")
        layer.emitterMode = CAEmitterLayerEmitterMode(rawValue: model.emitterMode ?? "volume")
        layer.renderMode = CAEmitterLayerRenderMode(rawValue: model.renderMode ?? "unordered")
        let cell = CAEmitterCell()
        cell.birthRate = 18
        cell.lifetime = 2.5
        cell.velocity = 45
        cell.velocityRange = 25
        cell.scale = 0.03
        cell.scaleRange = 0.02
        cell.alphaSpeed = -0.35
        cell.contents = UIImage(systemName: "sparkle")?.withTintColor(.white).cgImage
        layer.emitterCells = [cell]
        return layer
    }

    private func makeReplicatorLayer(_ model: LayerModel) -> CAReplicatorLayer {
        let layer = CAReplicatorLayer()
        layer.instanceCount = model.instanceCount ?? 1
        layer.instanceDelay = model.instanceDelay ?? 0
        var transform = CATransform3DMakeTranslation(
            CGFloat(model.instanceTranslationX ?? 0), CGFloat(model.instanceTranslationY ?? 0), CGFloat(model.instanceTranslationZ ?? 0)
        )
        transform = CATransform3DRotate(transform, CGFloat(model.instanceRotation ?? 0), 0, 0, 1)
        layer.instanceTransform = transform
        return layer
    }

    private func makePublicGlassFallbackLayer(_ model: LayerModel) -> CALayer {
        let layer = CAGradientLayer()
        layer.colors = [UIColor.white.withAlphaComponent(0.24).cgColor,
                        UIColor.white.withAlphaComponent(0.08).cgColor]
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.borderWidth = CGFloat(max(model.borderWidth, 0.5))
        return layer
    }

    private func applyAnimations(_ models: [KeyframeAnimationModel], to layer: CALayer) {
        for model in models where model.enabled && !model.numericValues.isEmpty {
            let animation = CAKeyframeAnimation(keyPath: model.keyPath)
            animation.values = model.numericValues
            animation.keyTimes = model.keyTimes.map(NSNumber.init(value:))
            animation.duration = model.duration
            animation.autoreverses = model.autoreverses
            animation.repeatCount = model.repeats ? .infinity : 0
            animation.calculationMode = CAAnimationCalculationMode(rawValue: model.calculationMode)
            animation.timingFunction = CAMediaTimingFunction(name: timingName(model.timingFunction))
            layer.add(animation, forKey: "caplayground.\(model.id.uuidString)")
        }
    }

    private func apply(state: String, project: CAProjectDocument) {
        guard let overrides = project.stateOverrides[state] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for override in overrides {
            guard let layer = renderedLayers[override.targetID] else { continue }
            switch (override.keyPath, override.value) {
            case ("opacity", .number(let value)): layer.opacity = Float(value)
            case ("position.x", .number(let value)): layer.position.x = CGFloat(value)
            case ("position.y", .number(let value)): layer.position.y = CGFloat(value)
            case ("backgroundColor", .string(let value)): layer.backgroundColor = UIColor(caHex: value)?.cgColor
            default: break
            }
        }
        CATransaction.commit()
    }

    private func timingName(_ value: String) -> CAMediaTimingFunctionName {
        switch value {
        case "easeIn": .easeIn
        case "easeOut": .easeOut
        case "easeInEaseOut": .easeInEaseOut
        default: .linear
        }
    }

    private func publicCompositingFilter(named name: String?) -> String? {
        switch name {
        case "multiplyBlendMode", "screenBlendMode", "overlayBlendMode": name
        default: nil
        }
    }
}
