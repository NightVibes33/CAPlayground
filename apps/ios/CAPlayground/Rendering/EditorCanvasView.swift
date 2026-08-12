import UIKit

@MainActor
protocol EditorCanvasViewDelegate: AnyObject {
    func canvas(_ canvas: EditorCanvasView, selected id: UUID?)
    func canvas(_ canvas: EditorCanvasView, moved id: UUID, to position: Vector2)
    func canvas(_ canvas: EditorCanvasView, resized id: UUID, to size: LayerSize, position: Vector2)
    func canvas(_ canvas: EditorCanvasView, rotated id: UUID, to degrees: Double)
}

@MainActor
final class EditorCanvasView: UIView {
    weak var delegate: EditorCanvasViewDelegate?
    private let renderer = CoreAnimationRenderer()
    private let artworkLayer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private var project: CAProjectDocument?
    private var selectedID: UUID?
    private var scale: CGFloat = 1
    private var resizeCorner: ResizeCorner?
    private var rotationStartDegrees = 0.0

    private enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(caHex: "#1F2937")
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
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        addGestureRecognizer(pinch)
        addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:))))
        isAccessibilityElement = true
        accessibilityLabel = "Core Animation canvas"
        accessibilityHint = "Tap a layer to select it. Drag to move the selected layer. Pinch to zoom."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionArtwork()
        updateSelection()
    }

    func display(_ project: CAProjectDocument, selectedID: UUID?, showBackground: Bool) {
        self.project = project
        self.selectedID = selectedID
        artworkLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
        renderer.render(project: project, showBackground: showBackground, into: artworkLayer)
        positionArtwork()
        updateSelection()
    }

    private func positionArtwork() {
        guard let project else { return }
        let fit = min((bounds.width - 32) / CGFloat(project.width), (bounds.height - 32) / CGFloat(project.height))
        artworkLayer.setAffineTransform(CGAffineTransform(scaleX: fit * scale, y: fit * scale))
        artworkLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        artworkLayer.cornerRadius = 18 / max(fit * scale, 0.01)
        artworkLayer.masksToBounds = true
        artworkLayer.shadowColor = UIColor.black.cgColor
        artworkLayer.shadowOpacity = 0.35
        artworkLayer.shadowRadius = 18
    }

    private func updateSelection() {
        guard let selectedID, let target = renderer.layer(for: selectedID) else {
            selectionLayer.path = nil
            handleLayer.path = nil
            return
        }
        let rect = target.convert(target.bounds, to: layer)
        selectionLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        let handles = UIBezierPath()
        for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            handles.append(UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)))
        }
        handleLayer.path = handles.cgPath
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
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
        guard let selectedID, let target = renderer.layer(for: selectedID) else { return }
        let translation = recognizer.translation(in: self)
        let sx = abs(artworkLayer.affineTransform().a)
        guard sx > 0 else { return }
        if recognizer.state == .began {
            resizeCorner = corner(at: recognizer.location(in: self), target: target)
        }
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
            target.bounds.size = CGSize(width: max(width, 1), height: max(height, 1))
            target.position = position
        } else {
            target.position.x += translation.x / sx
            target.position.y += translation.y / sx
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

    private func corner(at point: CGPoint, target: CALayer) -> ResizeCorner? {
        let rect = target.convert(target.bounds, to: layer)
        let points: [(ResizeCorner, CGPoint)] = [
            (.topLeft, .init(x: rect.minX, y: rect.minY)), (.topRight, .init(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, .init(x: rect.minX, y: rect.maxY)), (.bottomRight, .init(x: rect.maxX, y: rect.maxY))
        ]
        return points.first { hypot($0.1.x - point.x, $0.1.y - point.y) <= 24 }?.0
    }

    @objc private func rotated(_ recognizer: UIRotationGestureRecognizer) {
        guard let selectedID, let target = renderer.layer(for: selectedID) else { return }
        if recognizer.state == .began {
            rotationStartDegrees = project?.root.find(id: selectedID)?.rotation ?? 0
        }
        let degrees = rotationStartDegrees + Double(recognizer.rotation * 180 / .pi)
        target.setValue(degrees * .pi / 180, forKeyPath: "transform.rotation.z")
        updateSelection()
        if recognizer.state == .ended || recognizer.state == .cancelled {
            delegate?.canvas(self, rotated: selectedID, to: degrees)
        }
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .changed {
            scale = min(max(scale * recognizer.scale, 0.35), 4)
            recognizer.scale = 1
            positionArtwork()
            updateSelection()
        }
    }
}
