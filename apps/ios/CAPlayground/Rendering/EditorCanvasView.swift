import UIKit

@MainActor
protocol EditorCanvasViewDelegate: AnyObject {
    func canvas(_ canvas: EditorCanvasView, selected id: UUID?)
    func canvas(_ canvas: EditorCanvasView, moved id: UUID, to position: Vector2)
    func canvas(_ canvas: EditorCanvasView, resized id: UUID, to size: LayerSize, position: Vector2)
    func canvas(_ canvas: EditorCanvasView, rotated id: UUID, to degrees: Double)
}

@MainActor
final class EditorCanvasView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: EditorCanvasViewDelegate?
    private let renderer = CoreAnimationRenderer()
    private let artworkLayer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let anchorLayer = CAShapeLayer()
    private let edgeGuideLayer = CAShapeLayer()
    private let previewClockLayer = CATextLayer()
    private let previewDateLayer = CATextLayer()

    private var project: CAProjectDocument?
    private var selectedID: UUID?
    private var scale: CGFloat = 1
    private var panOffset = CGPoint.zero
    private var resizeCorner: ResizeCorner?
    private var rotationStartDegrees = 0.0
    private var lastCommandID: UUID?
    private var showPreview = false
    private var showEdgeGuide = false
    private var clipToCanvas = false
    private var showAnchorPoint = false
    private var gyroX = 0.0
    private var gyroY = 0.0
    private var timelineTime = 0.0
    private var showBackground = true

    private enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(patternImage: Self.checkerboard())
        layer.addSublayer(artworkLayer)

        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.strokeColor = UIColor(caHex: "#5AD197")?.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [6, 4]
        layer.addSublayer(selectionLayer)

        handleLayer.fillColor = UIColor.systemBackground.cgColor
        handleLayer.strokeColor = UIColor(caHex: "#5AD197")?.cgColor
        handleLayer.lineWidth = 2
        layer.addSublayer(handleLayer)

        anchorLayer.fillColor = UIColor(caHex: "#5AD197")?.cgColor
        anchorLayer.strokeColor = UIColor.white.cgColor
        anchorLayer.lineWidth = 1.5
        layer.addSublayer(anchorLayer)

        edgeGuideLayer.fillColor = UIColor.clear.cgColor
        edgeGuideLayer.strokeColor = UIColor.white.cgColor
        edgeGuideLayer.lineWidth = 3
        edgeGuideLayer.lineDashPattern = [5, 5]
        edgeGuideLayer.compositingFilter = "differenceBlendMode"
        layer.addSublayer(edgeGuideLayer)

        configurePreviewText(previewClockLayer, size: 58, weight: .light)
        configurePreviewText(previewDateLayer, size: 15, weight: .semibold)
        artworkLayer.addSublayer(previewClockLayer)
        artworkLayer.addSublayer(previewDateLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)

        let editPan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        editPan.maximumNumberOfTouches = 1
        editPan.delegate = self
        addGestureRecognizer(editPan)

        let canvasPan = UIPanGestureRecognizer(target: self, action: #selector(pannedCanvas(_:)))
        canvasPan.minimumNumberOfTouches = 2
        canvasPan.maximumNumberOfTouches = 2
        canvasPan.delegate = self
        addGestureRecognizer(canvasPan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
        rotation.delegate = self
        addGestureRecognizer(rotation)

        isAccessibilityElement = true
        accessibilityLabel = "Core Animation canvas"
        accessibilityHint = "Tap a layer to select it. Drag to move. Drag a corner to resize. Rotate with two fingers. Pinch to zoom and drag with two fingers to pan."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionArtwork()
        updateSelection()
        updateEdgeGuide()
        updatePreviewChrome()
    }

    func display(
        _ project: CAProjectDocument,
        selectedID: UUID?,
        showBackground: Bool,
        showPreview: Bool,
        showEdgeGuide: Bool,
        clipToCanvas: Bool,
        showAnchorPoint: Bool,
        gyroX: Double,
        gyroY: Double,
        timelineTime: Double,
        timelinePlaying: Bool
    ) {
        let needsRender = self.project != project || self.showBackground != showBackground
        self.project = project
        self.selectedID = selectedID
        self.showBackground = showBackground
        self.showPreview = showPreview
        self.showEdgeGuide = showEdgeGuide
        self.clipToCanvas = clipToCanvas
        self.showAnchorPoint = showAnchorPoint
        self.gyroX = gyroX
        self.gyroY = gyroY
        self.timelineTime = timelineTime

        artworkLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
        if needsRender {
            renderer.render(project: project, showBackground: showBackground, into: artworkLayer)
            artworkLayer.addSublayer(previewClockLayer)
            artworkLayer.addSublayer(previewDateLayer)
        }
        renderer.applyGyro(project: project, x: gyroX, y: gyroY)
        artworkLayer.speed = 0
        artworkLayer.timeOffset = timelineTime
        artworkLayer.masksToBounds = clipToCanvas || showPreview

        positionArtwork()
        updateSelection()
        updateEdgeGuide()
        updatePreviewChrome()
    }

    func perform(_ command: EditorCanvasCommand) {
        guard command.id != lastCommandID else { return }
        lastCommandID = command.id
        switch command.action {
        case .zoomIn: zoom(by: 1.1)
        case .zoomOut: zoom(by: 1 / 1.1)
        case .resetZoom:
            scale = 1
            panOffset = .zero
            positionArtwork(); updateSelection(); updateEdgeGuide()
        case .restartTimeline:
            artworkLayer.timeOffset = 0
        }
    }

    private func configurePreviewText(_ layer: CATextLayer, size: CGFloat, weight: UIFont.Weight) {
        layer.alignmentMode = .center
        layer.foregroundColor = UIColor.white.cgColor
        layer.font = UIFont.systemFont(ofSize: size, weight: weight)
        layer.fontSize = size
        layer.contentsScale = max(window?.screen.scale ?? 2, 2)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
    }

    private func positionArtwork() {
        guard let project else { return }
        let fit = min(max((bounds.width - 32) / CGFloat(project.width), 0.01), max((bounds.height - 32) / CGFloat(project.height), 0.01))
        artworkLayer.setAffineTransform(CGAffineTransform(scaleX: fit * scale, y: fit * scale))
        artworkLayer.position = CGPoint(x: bounds.midX + panOffset.x, y: bounds.midY + panOffset.y)
        artworkLayer.cornerRadius = showPreview ? 0 : 0
        artworkLayer.shadowColor = UIColor.black.cgColor
        artworkLayer.shadowOpacity = 0.28
        artworkLayer.shadowRadius = 18
        artworkLayer.shadowOffset = CGSize(width: 0, height: 8)
    }

    private func updateSelection() {
        guard !showPreview, let selectedID, let target = renderer.layer(for: selectedID) else {
            selectionLayer.path = nil
            handleLayer.path = nil
            anchorLayer.path = nil
            return
        }
        let rect = target.convert(target.bounds, to: layer)
        selectionLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        let handles = UIBezierPath()
        for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            handles.append(UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)))
        }
        handleLayer.path = handles.cgPath

        if showAnchorPoint {
            let anchorLocal = CGPoint(x: target.bounds.width * target.anchorPoint.x, y: target.bounds.height * target.anchorPoint.y)
            let anchor = target.convert(anchorLocal, to: layer)
            anchorLayer.path = UIBezierPath(ovalIn: CGRect(x: anchor.x - 5, y: anchor.y - 5, width: 10, height: 10)).cgPath
        } else {
            anchorLayer.path = nil
        }
    }

    private func updateEdgeGuide() {
        guard showEdgeGuide else { edgeGuideLayer.path = nil; return }
        let rect = artworkLayer.convert(artworkLayer.bounds, to: layer).insetBy(dx: 1.5, dy: 1.5)
        edgeGuideLayer.path = UIBezierPath(rect: rect).cgPath
    }

    private func updatePreviewChrome() {
        guard let project else { return }
        previewClockLayer.isHidden = !showPreview
        previewDateLayer.isHidden = !showPreview
        guard showPreview else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, MMMM d"
        previewDateLayer.string = formatter.string(from: .now)
        previewClockLayer.string = "9:41"
        previewDateLayer.frame = CGRect(x: 0, y: 40, width: project.width, height: 24)
        previewClockLayer.frame = CGRect(x: 0, y: 62, width: project.width, height: 76)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard !showPreview else { return }
        let point = recognizer.location(in: self)
        guard let hit = layer.hitTest(point), hit !== artworkLayer else {
            selectedID = nil
            delegate?.canvas(self, selected: nil)
            updateSelection()
            return
        }
        var candidate: CALayer? = hit
        while candidate != nil, candidate?.name == nil { candidate = candidate?.superlayer }
        let hitID = candidate?.name.flatMap(UUID.init(uuidString:))
        selectedID = hitID.flatMap { renderer.isSelectable($0) ? $0 : nil }
        delegate?.canvas(self, selected: selectedID)
        updateSelection()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        guard !showPreview, let selectedID, let target = renderer.layer(for: selectedID) else { return }
        let translation = recognizer.translation(in: self)
        let sx = abs(artworkLayer.affineTransform().a)
        guard sx > 0 else { return }
        if recognizer.state == .began { resizeCorner = corner(at: recognizer.location(in: self), target: target) }

        if let resizeCorner {
            let dx = translation.x / sx
            let dy = translation.y / sx
            var width = target.bounds.width
            var height = target.bounds.height
            var position = target.position
            switch resizeCorner {
            case .topLeft: width -= dx; height -= dy; position.x += dx / 2; position.y += dy / 2
            case .topRight: width += dx; height -= dy; position.x += dx / 2; position.y += dy / 2
            case .bottomLeft: width -= dx; height += dy; position.x += dx / 2; position.y += dy / 2
            case .bottomRight: width += dx; height += dy; position.x += dx / 2; position.y += dy / 2
            }
            width = max(width, 1); height = max(height, 1)
            if settingBool("caplay_settings_snap_resize", default: true) {
                let snapped = snapSize(CGSize(width: width, height: height), position: position, targetID: selectedID, screenScale: sx)
                width = snapped.size.width; height = snapped.size.height; position = snapped.position
            }
            target.bounds.size = CGSize(width: width, height: height)
            target.position = position
        } else {
            var position = CGPoint(x: target.position.x + translation.x / sx, y: target.position.y + translation.y / sx)
            position = snapPosition(position, target: target, targetID: selectedID, screenScale: sx)
            target.position = position
        }
        recognizer.setTranslation(.zero, in: self)
        updateSelection()

        if recognizer.state == .ended || recognizer.state == .cancelled {
            if resizeCorner != nil {
                delegate?.canvas(self, resized: selectedID,
                                 to: .init(width: Double(target.bounds.width), height: Double(target.bounds.height)),
                                 position: .init(x: Double(target.position.x), y: Double(target.position.y)))
            } else {
                delegate?.canvas(self, moved: selectedID, to: .init(x: Double(target.position.x), y: Double(target.position.y)))
            }
            resizeCorner = nil
        }
    }

    @objc private func pannedCanvas(_ recognizer: UIPanGestureRecognizer) {
        guard !showPreview else { return }
        let translation = recognizer.translation(in: self)
        panOffset.x += translation.x
        panOffset.y += translation.y
        recognizer.setTranslation(.zero, in: self)
        positionArtwork(); updateSelection(); updateEdgeGuide()
    }

    private func corner(at point: CGPoint, target: CALayer) -> ResizeCorner? {
        let rect = target.convert(target.bounds, to: layer)
        let points: [(ResizeCorner, CGPoint)] = [
            (.topLeft, .init(x: rect.minX, y: rect.minY)), (.topRight, .init(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, .init(x: rect.minX, y: rect.maxY)), (.bottomRight, .init(x: rect.maxX, y: rect.maxY))
        ]
        return points.first { hypot($0.1.x - point.x, $0.1.y - point.y) <= 24 }?.0
    }

    @objc private func rotated(_ recognizer: UIRotationGestureRecognizer) {
        guard !showPreview, let selectedID, let target = renderer.layer(for: selectedID) else { return }
        if recognizer.state == .began { rotationStartDegrees = project?.root.find(id: selectedID)?.rotation ?? 0 }
        var degrees = rotationStartDegrees + Double(recognizer.rotation * 180 / .pi)
        if settingBool("caplay_settings_snap_rotation", default: true) {
            let threshold = 6.0
            for candidate in [0.0, 90, 180, 270, 360, -90, -180, -270] where abs(degrees - candidate) <= threshold { degrees = candidate; break }
        }
        target.setValue(degrees * .pi / 180, forKeyPath: "transform.rotation.z")
        updateSelection()
        if recognizer.state == .ended || recognizer.state == .cancelled { delegate?.canvas(self, rotated: selectedID, to: degrees) }
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        guard !showPreview else { return }
        if recognizer.state == .changed {
            let sensitivity = UserDefaults.standard.object(forKey: "caplay_settings_pinch_zoom_sensitivity") as? Double ?? 1
            let adjusted = 1 + (recognizer.scale - 1) * sensitivity
            scale = min(max(scale * adjusted, 0.2), 5)
            recognizer.scale = 1
            positionArtwork(); updateSelection(); updateEdgeGuide()
        }
    }

    private func zoom(by factor: CGFloat) {
        scale = min(max(scale * factor, 0.2), 5)
        positionArtwork(); updateSelection(); updateEdgeGuide()
    }

    private func snapPosition(_ proposed: CGPoint, target: CALayer, targetID: UUID, screenScale: CGFloat) -> CGPoint {
        guard let project else { return proposed }
        let threshold = CGFloat(UserDefaults.standard.object(forKey: "caplay_settings_snap_threshold") as? Double ?? 12) / max(screenScale, 0.01)
        var result = proposed
        let halfW = target.bounds.width / 2, halfH = target.bounds.height / 2

        if settingBool("caplay_settings_snap_edges", default: true) {
            let candidatesX: [(CGFloat, CGFloat)] = [(result.x - halfW, 0), (result.x, CGFloat(project.width / 2)), (result.x + halfW, CGFloat(project.width))]
            for (actual, desired) in candidatesX where abs(actual - desired) <= threshold { result.x += desired - actual; break }
            let candidatesY: [(CGFloat, CGFloat)] = [(result.y - halfH, 0), (result.y, CGFloat(project.height / 2)), (result.y + halfH, CGFloat(project.height))]
            for (actual, desired) in candidatesY where abs(actual - desired) <= threshold { result.y += desired - actual; break }
        }

        if settingBool("caplay_settings_snap_layers", default: true) {
            for (id, layer) in renderer.renderedLayers where id != targetID && renderer.isSelectable(id) {
                let other = layer.frame
                let xTargets = [other.minX, other.midX, other.maxX]
                let xActual = [result.x - halfW, result.x, result.x + halfW]
                outerX: for actual in xActual { for desired in xTargets where abs(actual - desired) <= threshold { result.x += desired - actual; break outerX } }
                let yTargets = [other.minY, other.midY, other.maxY]
                let yActual = [result.y - halfH, result.y, result.y + halfH]
                outerY: for actual in yActual { for desired in yTargets where abs(actual - desired) <= threshold { result.y += desired - actual; break outerY } }
            }
        }
        return result
    }

    private func snapSize(_ proposed: CGSize, position: CGPoint, targetID: UUID, screenScale: CGFloat) -> (size: CGSize, position: CGPoint) {
        guard let project else { return (proposed, position) }
        let threshold = CGFloat(UserDefaults.standard.object(forKey: "caplay_settings_snap_threshold") as? Double ?? 12) / max(screenScale, 0.01)
        var size = proposed
        var position = position
        if settingBool("caplay_settings_snap_edges", default: true) {
            let right = position.x + size.width / 2
            if abs(right - CGFloat(project.width)) <= threshold { size.width += CGFloat(project.width) - right; position.x += (CGFloat(project.width) - right) / 2 }
            let bottom = position.y + size.height / 2
            if abs(bottom - CGFloat(project.height)) <= threshold { size.height += CGFloat(project.height) - bottom; position.y += (CGFloat(project.height) - bottom) / 2 }
        }
        return (CGSize(width: max(size.width, 1), height: max(size.height, 1)), position)
    }

    private func settingBool(_ key: String, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private static func checkerboard() -> UIImage {
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(caHex: "#0B1220")! : UIColor(caHex: "#F8FAFC")! }.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(caHex: "#1F2937")! : UIColor(caHex: "#E5E7EB")! }.setFill()
            context.fill(CGRect(x: 10, y: 0, width: 10, height: 10))
            context.fill(CGRect(x: 0, y: 10, width: 10, height: 10))
        }
    }
}
