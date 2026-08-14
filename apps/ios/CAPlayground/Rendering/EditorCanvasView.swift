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

    // Website device-preview chrome.
    private let previewPhoneFrameLayer = CAShapeLayer()
    private let previewSideButtonLayer = CAShapeLayer()
    private let previewCarrierLayer = CATextLayer()
    private let previewTimeStatusLayer = CATextLayer()
    private let previewDateLayer = CATextLayer()
    private let previewClockLayer = CATextLayer()
    private let previewSignalLayer = CAShapeLayer()
    private let previewWifiLayer = CAShapeLayer()
    private let previewBatteryLayer = CAShapeLayer()
    private let previewHomeBarLayer = CAShapeLayer()
    private let previewFlashlightLayer = CALayer()
    private let previewCameraLayer = CALayer()
    private let previewUnlockedDockLayer = CAShapeLayer()
    private let previewSleepOverlayLayer = CALayer()

    private let previewControlsStack = UIStackView()
    private let depthControls = UIStackView()
    private let depthLabel = UILabel()
    private let depthSwitch = UISwitch()
    private let appearanceControls = UIStackView()
    private let lightLabel = UILabel()
    private let sunImage = UIImageView(image: UIImage(systemName: "sun.max"))
    private let appearanceSwitch = UISwitch()
    private let moonImage = UIImageView(image: UIImage(systemName: "moon"))
    private let darkLabel = UILabel()

    private enum PreviewPhoneState: String { case locked = "Locked", unlock = "Unlock", sleep = "Sleep" }
    private enum PreviewEase { case linear, easeOutCubic, easeOutQuadratic }

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

    private var previewPhoneState: PreviewPhoneState = .locked
    private var previewTheme = "Light"
    private var previewChromeOffset: CGFloat = 0
    private var previewTransitionActive = false
    private var previewTransitionFrom: PreviewPhoneState = .locked
    private var previewTransitionTo: PreviewPhoneState = .locked
    private var previewTransitionProgress = 0.0
    private var previewAnimationTask: Task<Void, Never>?
    private var previewSleepPauseTask: Task<Void, Never>?
    private var previewDragFrom: PreviewPhoneState?
    private var previewDragTo: PreviewPhoneState?
    private var previewDragProgress = 0.0
    private var previewTimelinePaused = false
    private var previewTimelineFrozenTime = 0.0
    private var previewTimelinePauseStartParentTime: Double?
    private var previewTimelineAdjustment = 0.0
    private var lastParentTimelineTime = 0.0

    private enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(patternImage: Self.checkerboard())
        layer.addSublayer(artworkLayer)

        previewPhoneFrameLayer.fillColor = UIColor.clear.cgColor
        previewPhoneFrameLayer.strokeColor = UIColor.black.cgColor
        previewPhoneFrameLayer.lineWidth = 8
        layer.addSublayer(previewPhoneFrameLayer)

        previewSideButtonLayer.fillColor = UIColor(caHex: "#555555")?.cgColor
        layer.addSublayer(previewSideButtonLayer)

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

        configurePreviewText(previewClockLayer, size: 120, weight: .bold)
        configurePreviewText(previewDateLayer, size: 18, weight: .medium)
        configurePreviewText(previewCarrierLayer, size: 14, weight: .semibold)
        configurePreviewText(previewTimeStatusLayer, size: 14, weight: .semibold)
        previewCarrierLayer.alignmentMode = .left
        previewTimeStatusLayer.alignmentMode = .left
        layer.addSublayer(previewCarrierLayer)
        layer.addSublayer(previewTimeStatusLayer)

        previewSignalLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(previewSignalLayer)
        previewWifiLayer.fillColor = UIColor.clear.cgColor
        previewWifiLayer.strokeColor = UIColor.white.cgColor
        previewWifiLayer.lineWidth = 1.5
        layer.addSublayer(previewWifiLayer)
        previewBatteryLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(previewBatteryLayer)
        previewHomeBarLayer.fillColor = UIColor.white.withAlphaComponent(0.75).cgColor
        layer.addSublayer(previewHomeBarLayer)

        configurePreviewButton(previewFlashlightLayer, symbol: "flashlight.on.fill")
        configurePreviewButton(previewCameraLayer, symbol: "camera.fill")
        layer.addSublayer(previewFlashlightLayer)
        layer.addSublayer(previewCameraLayer)

        previewUnlockedDockLayer.fillColor = UIColor.white.withAlphaComponent(0.20).cgColor
        layer.addSublayer(previewUnlockedDockLayer)
        previewSleepOverlayLayer.backgroundColor = UIColor.black.withAlphaComponent(0.30).cgColor
        layer.addSublayer(previewSleepOverlayLayer)

        configurePreviewControls()
        setPreviewChromeHidden(true)

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
        let previewChanged = self.showPreview != showPreview
        let needsRender = self.project != project || self.showBackground != showBackground || previewChanged

        if previewChanged {
            if showPreview { enterPreview(project) }
            else { exitPreview() }
        }

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
        lastParentTimelineTime = timelineTime

        artworkLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(project.width), height: CGFloat(project.height))
        if needsRender {
            let renderProject = showPreview ? previewRenderProject(project) : project
            renderer.render(project: renderProject, showBackground: showPreview ? true : showBackground, into: artworkLayer)
            installPreviewClockLayers()
        }

        if showPreview {
            applyCurrentPreviewState(project)
        }

        renderer.applyGyro(project: project, x: gyroX, y: gyroY)
        artworkLayer.speed = 0
        artworkLayer.timeOffset = effectiveTimelineTime(timelineTime)
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
            positionArtwork(); updateSelection(); updateEdgeGuide(); updatePreviewChrome()
        case .restartTimeline:
            previewTimelineAdjustment = 0
            previewTimelineFrozenTime = 0
            previewTimelinePauseStartParentTime = previewTimelinePaused ? 0 : nil
            artworkLayer.timeOffset = 0
        }
    }

    // MARK: - Website device preview

    private func configurePreviewControls() {
        previewControlsStack.axis = .horizontal
        previewControlsStack.alignment = .center
        previewControlsStack.distribution = .fill
        previewControlsStack.spacing = 8
        previewControlsStack.translatesAutoresizingMaskIntoConstraints = true
        previewControlsStack.isHidden = true
        addSubview(previewControlsStack)

        configureControlGroup(depthControls)
        depthLabel.text = "Depth Effect"
        configureControlLabel(depthLabel)
        depthSwitch.isOn = settingBool("caplay_preview_clock_depth", default: false)
        depthSwitch.addTarget(self, action: #selector(depthSwitchChanged), for: .valueChanged)
        depthControls.addArrangedSubview(depthLabel)
        depthControls.addArrangedSubview(depthSwitch)
        previewControlsStack.addArrangedSubview(depthControls)

        configureControlGroup(appearanceControls)
        lightLabel.text = "Light"
        darkLabel.text = "Dark"
        configureControlLabel(lightLabel)
        configureControlLabel(darkLabel)
        sunImage.tintColor = .label
        moonImage.tintColor = .label
        sunImage.contentMode = .scaleAspectFit
        moonImage.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            sunImage.widthAnchor.constraint(equalToConstant: 13), sunImage.heightAnchor.constraint(equalToConstant: 13),
            moonImage.widthAnchor.constraint(equalToConstant: 13), moonImage.heightAnchor.constraint(equalToConstant: 13)
        ])
        appearanceSwitch.addTarget(self, action: #selector(appearanceSwitchChanged), for: .valueChanged)
        appearanceControls.addArrangedSubview(lightLabel)
        appearanceControls.addArrangedSubview(sunImage)
        appearanceControls.addArrangedSubview(appearanceSwitch)
        appearanceControls.addArrangedSubview(moonImage)
        appearanceControls.addArrangedSubview(darkLabel)
        previewControlsStack.addArrangedSubview(appearanceControls)
    }

    private func configureControlGroup(_ stack: UIStackView) {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 5, leading: 8, bottom: 5, trailing: 8)
        stack.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.84)
        stack.layer.borderWidth = 1
        stack.layer.borderColor = UIColor.separator.cgColor
        stack.layer.cornerRadius = 6
    }

    private func configureControlLabel(_ label: UILabel) {
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .label
        label.setContentHuggingPriority(.required, for: .horizontal)
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

    private func configurePreviewButton(_ layer: CALayer, symbol: String) {
        layer.backgroundColor = UIColor.white.withAlphaComponent(0.20).cgColor
        layer.cornerRadius = 28
        layer.contents = UIImage(systemName: symbol)?.withTintColor(.white, renderingMode: .alwaysOriginal).cgImage
        layer.contentsGravity = .center
        layer.contentsScale = UIScreen.main.scale
    }

    private func enterPreview(_ project: CAProjectDocument) {
        previewAnimationTask?.cancel()
        previewSleepPauseTask?.cancel()
        previewPhoneState = .locked
        previewTheme = "Light"
        previewChromeOffset = 0
        previewTransitionActive = false
        previewDragFrom = nil
        previewDragTo = nil
        previewDragProgress = 0
        previewTimelinePaused = false
        previewTimelineFrozenTime = timelineTime
        previewTimelinePauseStartParentTime = nil
        previewTimelineAdjustment = 0
        depthSwitch.isOn = settingBool("caplay_preview_clock_depth", default: false)
        appearanceSwitch.isOn = false
        previewControlsStack.isHidden = false
        setPreviewChromeHidden(false)
        updatePreviewControlAvailability(project)
    }

    private func exitPreview() {
        previewAnimationTask?.cancel()
        previewSleepPauseTask?.cancel()
        previewAnimationTask = nil
        previewSleepPauseTask = nil
        previewTransitionActive = false
        previewDragFrom = nil
        previewDragTo = nil
        previewTimelinePaused = false
        previewTimelinePauseStartParentTime = nil
        previewTimelineAdjustment = 0
        previewControlsStack.isHidden = true
        setPreviewChromeHidden(true)
        previewClockLayer.removeFromSuperlayer()
        previewDateLayer.removeFromSuperlayer()
    }

    private func previewRenderProject(_ source: CAProjectDocument) -> CAProjectDocument {
        var result = source
        if source.gyroEnabled, let wallpaper = source.documents[.wallpaper] {
            // CoreAnimationRenderer renders background + floating together. Alias the wallpaper
            // document to floating in preview so gyro projects still preserve the website's
            // background-under-main ordering without changing the persisted project.
            result.activeCA = .floating
            result.documents[.floating] = wallpaper
            if let wallpaperAssets = source.documentAssets[.wallpaper] {
                result.documentAssets[.floating] = wallpaperAssets
            }
        } else {
            result.activeCA = .floating
        }
        if result.documents[.floating] != nil { result.documents[.floating]?.activeState = "Base State" }
        if result.documents[.background] != nil { result.documents[.background]?.activeState = "Base State" }
        return result
    }

    private func installPreviewClockLayers() {
        previewClockLayer.removeFromSuperlayer()
        previewDateLayer.removeFromSuperlayer()
        guard showPreview || project != nil else { return }

        if depthSwitch.isOn {
            // Depth Effect places the lock-screen clock between the background and foreground
            // artwork when both documents are present, matching the website's clock portal.
            if (artworkLayer.sublayers?.count ?? 0) >= 2 {
                artworkLayer.insertSublayer(previewDateLayer, at: 1)
                artworkLayer.insertSublayer(previewClockLayer, at: 2)
            } else {
                artworkLayer.insertSublayer(previewDateLayer, at: 0)
                artworkLayer.insertSublayer(previewClockLayer, at: 1)
            }
        } else {
            artworkLayer.addSublayer(previewDateLayer)
            artworkLayer.addSublayer(previewClockLayer)
        }
    }

    private func updatePreviewControlAvailability(_ project: CAProjectDocument) {
        appearanceControls.isHidden = !previewHasAppearanceSplit(project)
        let busy = previewTransitionActive || previewAnimationTask != nil
        depthSwitch.isEnabled = !busy
        appearanceSwitch.isEnabled = !busy
        appearanceSwitch.isOn = previewTheme == "Dark"
    }

    private func previewHasAppearanceSplit(_ project: CAProjectDocument) -> Bool {
        let mainKind: CADocumentKind = project.gyroEnabled ? .wallpaper : .floating
        return (project.documents[mainKind]?.appearanceSplit ?? false) || (project.documents[.background]?.appearanceSplit ?? false)
    }

    @objc private func depthSwitchChanged() {
        UserDefaults.standard.set(depthSwitch.isOn, forKey: "caplay_preview_clock_depth")
        installPreviewClockLayers()
        updatePreviewChrome()
    }

    @objc private func appearanceSwitchChanged() {
        guard let project, !previewTransitionActive else { return }
        previewTheme = appearanceSwitch.isOn ? "Dark" : "Light"
        renderer.applyPreviewState(project: project, state: previewPhoneState.rawValue, theme: previewTheme)
        updatePreviewChrome()
    }

    private func applyCurrentPreviewState(_ project: CAProjectDocument) {
        if previewTransitionActive {
            renderer.applyPreviewTransition(
                project: project,
                from: previewTransitionFrom.rawValue,
                to: previewTransitionTo.rawValue,
                theme: previewTheme,
                progress: previewTransitionProgress
            )
        } else {
            renderer.applyPreviewState(project: project, state: previewPhoneState.rawValue, theme: previewTheme)
        }
    }

    private func animatePreviewProgress(
        from: PreviewPhoneState,
        to: PreviewPhoneState,
        startProgress: Double,
        endProgress: Double,
        duration: Double,
        ease: PreviewEase,
        completionState: PreviewPhoneState
    ) {
        guard let project else { return }
        previewAnimationTask?.cancel()
        previewTransitionActive = true
        previewTransitionFrom = from
        previewTransitionTo = to
        previewTransitionProgress = startProgress
        updatePreviewControlAvailability(project)

        previewAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                let raw = min(1, max(0, elapsed / max(duration, 0.001)))
                let eased: Double = switch ease {
                case .linear: raw
                case .easeOutCubic: 1 - pow(1 - raw, 3)
                case .easeOutQuadratic: 1 - pow(1 - raw, 2)
                }
                let progress = startProgress + (endProgress - startProgress) * eased
                self.previewTransitionProgress = progress
                self.renderer.applyPreviewTransition(
                    project: project,
                    from: from.rawValue,
                    to: to.rawValue,
                    theme: self.previewTheme,
                    progress: progress
                )
                self.updatePreviewChrome()
                if raw >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            self.previewPhoneState = completionState
            self.previewTransitionActive = false
            self.previewTransitionProgress = 0
            self.previewDragFrom = nil
            self.previewDragTo = nil
            self.previewDragProgress = 0
            self.previewAnimationTask = nil
            self.renderer.applyPreviewState(project: project, state: completionState.rawValue, theme: self.previewTheme)
            if completionState == .sleep {
                self.previewChromeOffset = 0
                self.schedulePreviewTimelinePause()
            } else if completionState == .unlock {
                self.previewChromeOffset = -self.previewArtworkRect.height
                self.resumePreviewTimelineIfNeeded()
            } else {
                self.previewChromeOffset = 0
                self.resumePreviewTimelineIfNeeded()
            }
            self.updatePreviewControlAvailability(project)
            self.updatePreviewChrome()
        }
    }

    private func schedulePreviewTimelinePause() {
        previewSleepPauseTask?.cancel()
        previewSleepPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.previewPhoneState == .sleep else { return }
            self.previewTimelinePaused = true
            self.previewTimelinePauseStartParentTime = self.lastParentTimelineTime
            self.previewTimelineFrozenTime = max(0, self.lastParentTimelineTime - self.previewTimelineAdjustment)
            self.artworkLayer.timeOffset = self.previewTimelineFrozenTime
        }
    }

    private func resumePreviewTimelineIfNeeded() {
        previewSleepPauseTask?.cancel()
        previewSleepPauseTask = nil
        guard previewTimelinePaused else { return }
        if let start = previewTimelinePauseStartParentTime {
            previewTimelineAdjustment += max(0, lastParentTimelineTime - start)
        }
        previewTimelinePaused = false
        previewTimelinePauseStartParentTime = nil
    }

    private func effectiveTimelineTime(_ parentTime: Double) -> Double {
        if showPreview && previewTimelinePaused { return previewTimelineFrozenTime }
        return max(0, parentTime - (showPreview ? previewTimelineAdjustment : 0))
    }

    private func togglePreviewSleep() {
        guard showPreview, !previewTransitionActive, previewAnimationTask == nil else { return }
        if previewPhoneState == .sleep {
            resumePreviewTimelineIfNeeded()
            animatePreviewProgress(from: .sleep, to: .locked, startProgress: 0, endProgress: 1, duration: 0.5, ease: .linear, completionState: .locked)
        } else {
            previewSleepPauseTask?.cancel()
            schedulePreviewTimelinePause()
            animatePreviewProgress(from: previewPhoneState, to: .sleep, startProgress: 0, endProgress: 1, duration: 0.5, ease: .linear, completionState: .sleep)
        }
    }

    private func handlePreviewPan(_ recognizer: UIPanGestureRecognizer) {
        guard let project else { return }
        let rect = previewArtworkRect
        guard rect.width > 0, rect.height > 0 else { return }

        switch recognizer.state {
        case .began:
            guard !previewTransitionActive, previewPhoneState != .sleep else { return }
            let location = recognizer.location(in: self)
            if previewPhoneState == .locked, location.y >= rect.maxY - max(44, rect.height * 0.10) {
                previewDragFrom = .locked
                previewDragTo = .unlock
                previewChromeOffset = 0
            } else if previewPhoneState == .unlock, location.y <= rect.minY + max(44, rect.height * 0.08) {
                previewDragFrom = .unlock
                previewDragTo = .locked
                previewChromeOffset = -rect.height
            } else {
                previewDragFrom = nil
                previewDragTo = nil
            }

        case .changed:
            guard let from = previewDragFrom, let to = previewDragTo else { return }
            let translation = recognizer.translation(in: self).y
            let validTranslation: CGFloat
            if from == .locked && to == .unlock {
                validTranslation = min(0, translation)
            } else {
                validTranslation = max(0, translation)
            }
            let progress = min(1, abs(validTranslation) / max(rect.height, 1))
            previewDragProgress = Double(progress)
            previewTransitionActive = true
            previewTransitionFrom = from
            previewTransitionTo = to
            previewTransitionProgress = Double(progress)
            renderer.applyPreviewTransition(project: project, from: from.rawValue, to: to.rawValue, theme: previewTheme, progress: Double(progress))
            previewChromeOffset = from == .locked ? -rect.height * progress : -rect.height + rect.height * progress
            updatePreviewControlAvailability(project)
            updatePreviewChrome()

        case .ended, .cancelled:
            guard let from = previewDragFrom, let to = previewDragTo else { return }
            let progress = previewDragProgress
            if progress >= 0.5 {
                animatePreviewProgress(from: from, to: to, startProgress: progress, endProgress: 1, duration: 0.2, ease: .easeOutQuadratic, completionState: to)
            } else if progress > 0 {
                animatePreviewProgress(from: from, to: to, startProgress: progress, endProgress: 0, duration: 0.3, ease: .easeOutCubic, completionState: from)
            } else {
                previewTransitionActive = false
                previewDragFrom = nil
                previewDragTo = nil
                updatePreviewControlAvailability(project)
            }
        default:
            break
        }
    }

    private var previewArtworkRect: CGRect {
        artworkLayer.convert(artworkLayer.bounds, to: layer)
    }

    private func setPreviewChromeHidden(_ hidden: Bool) {
        for layer in [previewPhoneFrameLayer, previewSideButtonLayer, previewCarrierLayer, previewTimeStatusLayer, previewSignalLayer, previewWifiLayer, previewBatteryLayer, previewHomeBarLayer, previewFlashlightLayer, previewCameraLayer, previewUnlockedDockLayer, previewSleepOverlayLayer] {
            layer.isHidden = hidden
        }
        previewClockLayer.isHidden = hidden
        previewDateLayer.isHidden = hidden
    }

    private func updatePreviewChrome() {
        guard showPreview, let project else {
            setPreviewChromeHidden(true)
            previewControlsStack.isHidden = true
            return
        }

        let rect = previewArtworkRect
        guard rect.width > 0, rect.height > 0 else { return }
        setPreviewChromeHidden(false)
        previewControlsStack.isHidden = false
        updatePreviewControlAvailability(project)

        previewPhoneFrameLayer.path = UIBezierPath(roundedRect: rect.insetBy(dx: -8, dy: -8), cornerRadius: min(48, rect.width * 0.12)).cgPath
        previewSideButtonLayer.path = UIBezierPath(roundedRect: CGRect(x: rect.maxX + 8, y: rect.minY + rect.height * 0.11, width: 6, height: rect.height * 0.071), cornerRadius: 2).cgPath

        let controlsSize = previewControlsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        previewControlsStack.frame = CGRect(
            x: bounds.midX - controlsSize.width / 2,
            y: max(4, rect.minY - controlsSize.height - 14),
            width: controlsSize.width,
            height: controlsSize.height
        )

        let sleeping = previewPhoneState == .sleep && !previewTransitionActive
        let unlocked = previewPhoneState == .unlock && !previewTransitionActive
        let lockAlpha: Float
        if previewTransitionActive && (previewTransitionFrom == .sleep || previewTransitionTo == .sleep) {
            lockAlpha = Float(previewTransitionTo == .sleep ? 1 - previewTransitionProgress : previewTransitionProgress)
        } else {
            lockAlpha = sleeping ? 0 : 1
        }

        let lockOffset = previewChromeOffset
        let statusY = rect.minY + 10 + lockOffset
        previewCarrierLayer.string = "CAPG"
        previewCarrierLayer.frame = CGRect(x: rect.minX + 26, y: statusY, width: 70, height: 22)
        previewCarrierLayer.opacity = lockAlpha

        let now = Date()
        let timeFormatter = DateFormatter(); timeFormatter.dateFormat = "H:mm"
        previewTimeStatusLayer.string = timeFormatter.string(from: now)
        previewTimeStatusLayer.frame = CGRect(x: rect.minX + 26, y: rect.minY + 10, width: 70, height: 22)
        previewTimeStatusLayer.opacity = unlocked ? 1 : 0

        let signalBaseX = rect.maxX - 82
        let signalBaseY = statusY + 9
        let signalPath = UIBezierPath()
        for index in 0..<4 {
            let h = CGFloat(4 + index * 2)
            signalPath.append(UIBezierPath(roundedRect: CGRect(x: signalBaseX + CGFloat(index) * 5, y: signalBaseY - h, width: 3, height: h), cornerRadius: 1))
        }
        previewSignalLayer.path = signalPath.cgPath
        previewSignalLayer.opacity = sleeping ? 0 : 1

        let wifiPath = UIBezierPath()
        let wifiCenter = CGPoint(x: rect.maxX - 49, y: statusY + 8)
        wifiPath.addArc(withCenter: wifiCenter, radius: 8, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: true)
        wifiPath.move(to: CGPoint(x: wifiCenter.x - 4, y: wifiCenter.y + 1))
        wifiPath.addArc(withCenter: wifiCenter, radius: 4, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: true)
        previewWifiLayer.path = wifiPath.cgPath
        previewWifiLayer.opacity = sleeping ? 0 : 1

        let batteryRect = CGRect(x: rect.maxX - 32, y: statusY + 2, width: 24, height: 12)
        let batteryPath = UIBezierPath(roundedRect: batteryRect, cornerRadius: 2)
        batteryPath.append(UIBezierPath(roundedRect: CGRect(x: batteryRect.maxX + 1, y: batteryRect.midY - 2.5, width: 2, height: 5), cornerRadius: 1))
        previewBatteryLayer.path = batteryPath.cgPath
        previewBatteryLayer.opacity = sleeping ? 0 : 1

        let scaleToView = rect.width / CGFloat(max(project.width, 1))
        let artworkOffset = scaleToView > 0 ? lockOffset / scaleToView : 0
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "EEE d MMM"
        previewDateLayer.string = dateFormatter.string(from: now)
        previewClockLayer.string = timeFormatter.string(from: now)
        previewDateLayer.frame = CGRect(x: 0, y: 86 + artworkOffset, width: project.width, height: 26)
        previewClockLayer.frame = CGRect(x: 0, y: 110 + artworkOffset, width: project.width, height: 126)
        previewDateLayer.opacity = lockAlpha
        previewClockLayer.opacity = lockAlpha

        let buttonSize = max(38, min(56, rect.width * 0.145))
        previewFlashlightLayer.frame = CGRect(x: rect.minX + rect.width * 0.12, y: rect.maxY - buttonSize - 42 + lockOffset, width: buttonSize, height: buttonSize)
        previewFlashlightLayer.cornerRadius = buttonSize / 2
        previewFlashlightLayer.opacity = lockAlpha
        previewCameraLayer.frame = CGRect(x: rect.maxX - rect.width * 0.12 - buttonSize, y: rect.maxY - buttonSize - 42 + lockOffset, width: buttonSize, height: buttonSize)
        previewCameraLayer.cornerRadius = buttonSize / 2
        previewCameraLayer.opacity = lockAlpha

        let homeWidth = min(120, rect.width * 0.31)
        previewHomeBarLayer.path = UIBezierPath(roundedRect: CGRect(x: rect.midX - homeWidth / 2, y: rect.maxY - 22 + lockOffset, width: homeWidth, height: 5), cornerRadius: 3).cgPath
        previewHomeBarLayer.opacity = lockAlpha

        let dockPath = UIBezierPath()
        let appSize = min(56, rect.width * 0.143)
        let gap = min(20, rect.width * 0.051)
        let total = appSize * 4 + gap * 3
        let startX = rect.midX - total / 2
        let dockY = rect.maxY - appSize - 46
        for index in 0..<4 {
            dockPath.append(UIBezierPath(roundedRect: CGRect(x: startX + CGFloat(index) * (appSize + gap), y: dockY, width: appSize, height: appSize), cornerRadius: min(16, appSize * 0.28)))
        }
        previewUnlockedDockLayer.path = dockPath.cgPath
        previewUnlockedDockLayer.opacity = unlocked ? 1 : 0

        previewSleepOverlayLayer.frame = rect
        previewSleepOverlayLayer.cornerRadius = min(40, rect.width * 0.10)
        let sleepOpacity: Float
        if previewTransitionActive && (previewTransitionFrom == .sleep || previewTransitionTo == .sleep) {
            sleepOpacity = Float(previewTransitionTo == .sleep ? previewTransitionProgress : 1 - previewTransitionProgress)
        } else {
            sleepOpacity = sleeping ? 1 : 0
        }
        previewSleepOverlayLayer.opacity = sleepOpacity

        backgroundColor = showPreview ? UIColor.black : UIColor(patternImage: Self.checkerboard())
    }

    // MARK: - Editor canvas

    private func positionArtwork() {
        guard let project else { return }
        let fit = min(max((bounds.width - 32) / CGFloat(project.width), 0.01), max((bounds.height - 32) / CGFloat(project.height), 0.01))
        artworkLayer.setAffineTransform(CGAffineTransform(scaleX: fit * scale, y: fit * scale))
        artworkLayer.position = CGPoint(x: bounds.midX + panOffset.x, y: bounds.midY + panOffset.y)
        artworkLayer.cornerRadius = 0
        artworkLayer.shadowColor = UIColor.black.cgColor
        artworkLayer.shadowOpacity = showPreview ? 0.70 : 0.28
        artworkLayer.shadowRadius = showPreview ? 24 : 18
        artworkLayer.shadowOffset = CGSize(width: 0, height: showPreview ? 16 : 8)
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

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if showPreview {
            let point = recognizer.location(in: self)
            if previewSideButtonLayer.path?.contains(point) == true {
                togglePreviewSleep()
                return
            }
            if previewPhoneState == .sleep, previewArtworkRect.contains(point), !previewTransitionActive {
                togglePreviewSleep()
            }
            return
        }

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
        if showPreview {
            handlePreviewPan(recognizer)
            return
        }

        guard let selectedID, let target = renderer.layer(for: selectedID) else { return }
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
        positionArtwork(); updateSelection(); updateEdgeGuide(); updatePreviewChrome()
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

// MARK: - Website preview state application

@MainActor
private extension CoreAnimationRenderer {
    func applyPreviewState(project: CAProjectDocument, state: String, theme: String) {
        let mainKind: CADocumentKind = project.gyroEnabled ? .wallpaper : .floating
        let hasSplit = (project.documents[mainKind]?.appearanceSplit ?? false) || (project.documents[.background]?.appearanceSplit ?? false)
        let resolvedState = hasSplit ? "\(state) \(theme)" : state
        for kind in [CADocumentKind.background, mainKind] {
            guard let document = project.documents[kind] else { continue }
            applyPreviewDocument(document, state: resolvedState)
        }
    }

    func applyPreviewTransition(project: CAProjectDocument, from: String, to: String, theme: String, progress: Double) {
        let mainKind: CADocumentKind = project.gyroEnabled ? .wallpaper : .floating
        let hasSplit = (project.documents[mainKind]?.appearanceSplit ?? false) || (project.documents[.background]?.appearanceSplit ?? false)
        let fromState = hasSplit ? "\(from) \(theme)" : from
        let toState = hasSplit ? "\(to) \(theme)" : to
        for kind in [CADocumentKind.background, mainKind] {
            guard let document = project.documents[kind] else { continue }
            interpolatePreviewDocument(document, from: fromState, to: toState, progress: min(max(progress, 0), 1))
        }
    }

    func applyPreviewDocument(_ document: AnimationDocument, state: String) {
        let models = previewFlatten(document.root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for model in models {
            guard let target = renderedLayers[model.id] else { continue }
            let keys = previewOverrideKeys(for: model.id, document: document)
            for key in keys {
                let value = previewOverrideValue(targetID: model.id, keyPath: key, state: state, document: document) ?? previewBaseValue(model, keyPath: key)
                if let value { setPreviewValue(value, keyPath: key, on: target) }
            }
        }
        CATransaction.commit()
    }

    func interpolatePreviewDocument(_ document: AnimationDocument, from: String, to: String, progress: Double) {
        let models = previewFlatten(document.root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for model in models {
            guard let target = renderedLayers[model.id] else { continue }
            let keys = previewOverrideKeys(for: model.id, document: document)
            for key in keys {
                let base = previewBaseValue(model, keyPath: key)
                let fromValue = previewOverrideValue(targetID: model.id, keyPath: key, state: from, document: document) ?? base
                let toValue = previewOverrideValue(targetID: model.id, keyPath: key, state: to, document: document) ?? base
                guard let fromValue, let toValue else { continue }
                let value = interpolatePreviewValue(fromValue, toValue, progress: progress)
                setPreviewValue(value, keyPath: key, on: target)
            }
        }
        CATransaction.commit()
    }

    func previewFlatten(_ layer: LayerModel) -> [LayerModel] {
        [layer] + layer.children.flatMap(previewFlatten)
    }

    func previewOverrideKeys(for id: UUID, document: AnimationDocument) -> Set<String> {
        Set(document.stateOverrides.values.flatMap { overrides in
            overrides.filter { $0.targetID == id }.map(\.keyPath)
        })
    }

    func previewOverrideValue(targetID: UUID, keyPath: String, state: String, document: AnimationDocument) -> OverrideValue? {
        document.stateOverrides[state]?.last { $0.targetID == targetID && $0.keyPath == keyPath }?.value
    }

    func previewBaseValue(_ model: LayerModel, keyPath: String) -> OverrideValue? {
        switch keyPath {
        case "opacity": .number(model.opacity)
        case "position.x": .number(model.position.x)
        case "position.y": .number(model.position.y)
        case "zPosition": .number(model.zPosition)
        case "bounds.size.width": .number(model.size.width)
        case "bounds.size.height": .number(model.size.height)
        case "cornerRadius": .number(model.cornerRadius)
        case "transform.scale.xy": .number(model.scale)
        case "transform.rotation.z": .number(model.rotation)
        case "transform.rotation.x": .number(model.rotationX)
        case "transform.rotation.y": .number(model.rotationY)
        case "backgroundColor": .string(model.backgroundColor ?? "#000000")
        default: nil
        }
    }

    func interpolatePreviewValue(_ from: OverrideValue, _ to: OverrideValue, progress: Double) -> OverrideValue {
        switch (from, to) {
        case (.number(let a), .number(let b)):
            return .number(a + (b - a) * progress)
        case (.string(let a), .string(let b)):
            if let color = interpolatePreviewColor(a, b, progress: progress) { return .string(color) }
            return .string(progress < 0.5 ? a : b)
        default:
            return progress < 0.5 ? from : to
        }
    }

    func interpolatePreviewColor(_ a: String, _ b: String, progress: Double) -> String? {
        guard let first = UIColor(caHex: a), let second = UIColor(caHex: b) else { return nil }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard first.getRed(&ar, green: &ag, blue: &ab, alpha: &aa), second.getRed(&br, green: &bg, blue: &bb, alpha: &ba) else { return nil }
        let p = CGFloat(progress)
        let r = ar + (br - ar) * p
        let g = ag + (bg - ag) * p
        let blue = ab + (bb - ab) * p
        let alpha = aa + (ba - aa) * p
        if alpha < 0.999 {
            return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(blue * 255), Int(alpha * 255))
        }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(blue * 255))
    }

    func setPreviewValue(_ value: OverrideValue, keyPath: String, on layer: CALayer) {
        switch (keyPath, value) {
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
}