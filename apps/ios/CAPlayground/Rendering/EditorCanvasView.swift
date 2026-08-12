import UIKit

@MainActor
protocol EditorCanvasViewDelegate: AnyObject {
    func canvas(_ canvas: EditorCanvasView, selected id: UUID?)
    func canvas(_ canvas: EditorCanvasView, moved id: UUID, to position: Vector2)
}

@MainActor
final class EditorCanvasView: UIView {
    weak var delegate: EditorCanvasViewDelegate?
    private let renderer = CoreAnimationRenderer()
    private let artworkLayer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private var project: CAProjectDocument?
    private var selectedID: UUID?
    private var scale: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(caHex: "#1F2937")
        layer.addSublayer(artworkLayer)
        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.strokeColor = UIColor(caHex: "#5AD197")?.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [6, 4]
        layer.addSublayer(selectionLayer)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        addGestureRecognizer(pinch)
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

    func display(_ project: CAProjectDocument, selectedID: UUID?) {
        self.project = project
        self.selectedID = selectedID
        artworkLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
        renderer.render(project: project, into: artworkLayer)
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
            return
        }
        let rect = target.convert(target.bounds, to: layer)
        selectionLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
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
        selectedID = candidate?.name.flatMap(UUID.init(uuidString:))
        delegate?.canvas(self, selected: selectedID)
        updateSelection()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        guard let selectedID, let target = renderer.layer(for: selectedID) else { return }
        let translation = recognizer.translation(in: self)
        let sx = abs(artworkLayer.affineTransform().a)
        guard sx > 0 else { return }
        target.position.x += translation.x / sx
        target.position.y += translation.y / sx
        recognizer.setTranslation(.zero, in: self)
        updateSelection()
        if recognizer.state == .ended || recognizer.state == .cancelled {
            delegate?.canvas(self, moved: selectedID, to: .init(x: Double(target.position.x), y: Double(target.position.y)))
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
