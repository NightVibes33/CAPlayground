import SwiftUI
import UIKit

struct WebsiteTimelinePanel: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @Binding var currentTime: Double
    @Binding var viewSeconds: Double

    @State private var collapsed: Set<UUID> = []
    @State private var labelWidth: CGFloat = 100
    @State private var labelResizeStart: CGFloat?
    @State private var rulerDragging = false
    @State private var shiftDown = false

    private let duration = 600.0
    private let rowHeight: CGFloat = 24
    private let rulerHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Timeline").font(.caption.bold())
                Spacer()
                Button { viewSeconds = min(duration, viewSeconds * 2) } label: {
                    Image(systemName: "minus").frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel("Zoom out")
                .disabled(viewSeconds >= duration)
                Text("Scale").font(.caption2)
                Button { viewSeconds = max(1, viewSeconds / 2) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel("Zoom in")
                .disabled(viewSeconds <= 1)
            }
            .padding(.horizontal, 4)

            GeometryReader { proxy in
                let viewport = max(1, proxy.size.width - labelWidth)
                let pxPerSecond = viewport / CGFloat(max(1, min(duration, viewSeconds)))
                let trackWidth = max(viewport, CGFloat(duration) * pxPerSecond)
                let rows = displayRows

                ZStack(alignment: .topLeading) {
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            labelColumn(rows)
                                .frame(width: labelWidth)

                            ScrollViewReader { reader in
                                ScrollView(.horizontal) {
                                    ZStack(alignment: .topLeading) {
                                        VStack(spacing: 0) {
                                            ruler(width: trackWidth, pxPerSecond: pxPerSecond)
                                            ForEach(rows) { row in
                                                trackRow(row, trackWidth: trackWidth, pxPerSecond: pxPerSecond)
                                            }
                                        }

                                        Rectangle()
                                            .fill(CATheme.accent.opacity(0.10))
                                            .frame(
                                                width: max(0, min(trackWidth, CGFloat(currentTime) * pxPerSecond)),
                                                height: rulerHeight + CGFloat(rows.count) * rowHeight
                                            )

                                        Rectangle()
                                            .fill(CATheme.accent)
                                            .frame(width: 2, height: rulerHeight + CGFloat(rows.count) * rowHeight)
                                            .offset(x: min(trackWidth, max(0, CGFloat(currentTime) * pxPerSecond)))
                                            .overlay(alignment: .top) {
                                                Color.clear.frame(width: 1, height: 1).id("timeline-playhead")
                                            }
                                    }
                                    .frame(width: trackWidth, alignment: .leading)
                                }
                                .onChange(of: currentTime) { _, _ in
                                    if !rulerDragging {
                                        withAnimation(.linear(duration: 0.08)) {
                                            reader.scrollTo("timeline-playhead", anchor: .center)
                                        }
                                    }
                                }
                            }
                            .frame(width: viewport)
                        }
                    }
                    .scrollIndicators(.visible)

                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 8, height: proxy.size.height)
                        .offset(x: labelWidth - 4)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if labelResizeStart == nil { labelResizeStart = labelWidth }
                                    labelWidth = min(200, max(100, (labelResizeStart ?? labelWidth) + value.translation.width))
                                }
                                .onEnded { _ in labelResizeStart = nil }
                        )
                        .overlay {
                            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(.separator)))
            }
            .frame(maxHeight: 192)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .background(TimelineModifierCapture(isShiftDown: $shiftDown).frame(width: 1, height: 1))
    }

    private func labelColumn(_ rows: [TimelineDisplayRow]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Time").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: rulerHeight)
            .background(Color(.systemBackground))
            .overlay(alignment: .bottom) { Divider() }

            ForEach(rows) { row in
                switch row.kind {
                case .layer(let layer, let depth, let collapsible):
                    HStack(spacing: 2) {
                        if collapsible {
                            Button {
                                if collapsed.contains(layer.id) { collapsed.remove(layer.id) }
                                else { collapsed.insert(layer.id) }
                            } label: {
                                Image(systemName: collapsed.contains(layer.id) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 14, height: 20)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 14)
                        }
                        Text(layer.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 2 + CGFloat(depth) * 8)
                    .padding(.trailing, 2)
                    .frame(height: rowHeight)
                    .background(selectedID == layer.id ? CATheme.accent.opacity(0.20) : Color.secondary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        if selectedID == layer.id { Rectangle().fill(CATheme.accent).frame(width: 2) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if selectedID != layer.id { selectedID = layer.id } }
                    .overlay(alignment: .bottom) { Divider() }

                case .animation(let layer, let animation, let depth):
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(animationColor(animation.keyPath))
                            .frame(width: 8, height: 8)
                        Text(animation.keyPath).font(.system(size: 10)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16 + CGFloat(depth) * 8)
                    .padding(.trailing, 2)
                    .frame(height: rowHeight)
                    .background(selectedID == layer.id ? CATheme.accent.opacity(0.10) : Color(.systemBackground))
                    .overlay(alignment: .leading) {
                        if selectedID == layer.id { Rectangle().fill(CATheme.accent).frame(width: 2) }
                    }
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }

    private func ruler(width: CGFloat, pxPerSecond: CGFloat) -> some View {
        let intervals = tickIntervals(viewSeconds)
        return Canvas { context, _ in
            var t = 0.0
            while t <= duration + 0.0001 {
                let x = CGFloat(t) * pxPerSecond
                let remainder = t.truncatingRemainder(dividingBy: intervals.labelEvery)
                let labeled = abs(remainder) < 0.001 || abs(remainder - intervals.labelEvery) < 0.001
                var path = Path()
                path.move(to: CGPoint(x: x, y: labeled ? 0 : 12))
                path.addLine(to: CGPoint(x: x, y: 24))
                context.stroke(path, with: .color(labeled ? .secondary : .secondary.opacity(0.65)), lineWidth: 1)
                if labeled {
                    context.draw(
                        Text(formatTime(t)).font(.system(size: 10)).foregroundStyle(.primary),
                        at: CGPoint(x: x + 2, y: 5),
                        anchor: .topLeading
                    )
                }
                t += intervals.tickEvery
            }
        }
        .frame(width: width, height: rulerHeight)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    rulerDragging = true
                    currentTime = min(duration, max(0, Double(value.location.x / pxPerSecond)))
                }
                .onEnded { value in
                    currentTime = min(duration, max(0, Double(value.location.x / pxPerSecond)))
                    rulerDragging = false
                }
        )
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func trackRow(_ row: TimelineDisplayRow, trackWidth: CGFloat, pxPerSecond: CGFloat) -> some View {
        switch row.kind {
        case .layer:
            Color.secondary.opacity(0.05)
                .frame(width: trackWidth, height: rowHeight)
                .overlay(alignment: .bottom) { Divider() }
        case .animation(let layer, let animation, _):
            TimelineAnimationTrack(
                project: $project,
                layerID: layer.id,
                animationID: animation.id,
                trackWidth: trackWidth,
                pxPerSecond: pxPerSecond,
                timelineDuration: duration,
                rowHeight: rowHeight,
                color: animationColor(animation.keyPath),
                shiftDown: shiftDown
            )
        }
    }

    private var displayRows: [TimelineDisplayRow] {
        var result: [TimelineDisplayRow] = []
        func hasAnimation(_ layer: LayerModel) -> Bool {
            layer.animations.contains { $0.enabled } || layer.children.contains(where: hasAnimation)
        }
        func walk(_ layer: LayerModel, depth: Int) {
            let own = layer.animations.filter(\.enabled)
            let childHas = layer.children.contains(where: hasAnimation)
            guard !own.isEmpty || childHas else { return }
            result.append(.init(id: "layer-\(layer.id)", kind: .layer(layer, depth, !own.isEmpty || childHas)))
            guard !collapsed.contains(layer.id) else { return }
            for animation in own {
                result.append(.init(id: "animation-\(layer.id)-\(animation.id)", kind: .animation(layer, animation, depth)))
            }
            for child in layer.children { walk(child, depth: depth + 1) }
        }
        for layer in project.root.children { walk(layer, depth: 0) }
        return result
    }

    private func tickIntervals(_ view: Double) -> (tickEvery: Double, labelEvery: Double) {
        let raw = view / 5
        let nice = [0.1, 0.2, 0.5, 1.0, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let label = nice.first(where: { raw <= $0 }) ?? 600
        return (label / 5, label)
    }

    private func formatTime(_ seconds: Double) -> String {
        seconds == floor(seconds) ? "\(Int(seconds))s" : String(format: "%.1fs", seconds)
    }

    private func animationColor(_ keyPath: String) -> Color {
        switch keyPath {
        case "position": Color(red: 249/255, green: 115/255, blue: 22/255)
        case "position.x": Color(red: 251/255, green: 146/255, blue: 60/255)
        case "position.y": Color(red: 234/255, green: 88/255, blue: 12/255)
        case "opacity": Color(red: 168/255, green: 85/255, blue: 247/255)
        case "transform.rotation.z": Color(red: 59/255, green: 130/255, blue: 246/255)
        case "transform.rotation.x": Color(red: 239/255, green: 68/255, blue: 68/255)
        case "transform.rotation.y": Color(red: 34/255, green: 197/255, blue: 94/255)
        case "bounds": Color(red: 236/255, green: 72/255, blue: 153/255)
        default: Color(red: 107/255, green: 114/255, blue: 128/255)
        }
    }
}

private struct TimelineDisplayRow: Identifiable {
    enum Kind {
        case layer(LayerModel, Int, Bool)
        case animation(LayerModel, KeyframeAnimationModel, Int)
    }
    let id: String
    let kind: Kind
}

private struct TimelineAnimationTrack: View {
    @Binding var project: CAProjectDocument
    let layerID: UUID
    let animationID: UUID
    let trackWidth: CGFloat
    let pxPerSecond: CGFloat
    let timelineDuration: Double
    let rowHeight: CGFloat
    let color: Color
    let shiftDown: Bool

    @State private var localDuration: Double?
    @State private var startDuration = 1.0
    @State private var hovering = false

    private var animation: KeyframeAnimationModel? {
        project.root.find(id: layerID)?.animations.first(where: { $0.id == animationID })
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.secondary.opacity(0.04)
            if let animation {
                let duration = localDuration ?? animation.duration
                let speed = animation.speed
                let effective = speed != 0 ? duration / speed : duration
                let cycleWidth = max(2, CGFloat(effective) * pxPerSecond)
                let count: Int = {
                    if animation.repeats { return max(1, Int(ceil(timelineDuration / max(effective, 0.0001)))) }
                    if let repeatDuration = animation.repeatDurationSeconds {
                        return max(1, Int(ceil(repeatDuration / max(duration, 0.0001))))
                    }
                    return 1
                }()

                ForEach(0..<count, id: \.self) { repeatIndex in
                    let first = repeatIndex == 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.75))
                        .frame(width: cycleWidth, height: rowHeight - 4)
                        .overlay(alignment: .leading) {
                            if first {
                                Text(durationText(duration, speed: speed))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                            } else if animation.autoreverses && repeatIndex % 2 == 1 {
                                Text("← reverse")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if first {
                                Rectangle()
                                    .fill(Color.white.opacity(hovering || localDuration != nil ? 0.30 : 0.001))
                                    .frame(width: 24)
                                    .contentShape(Rectangle())
                                    .onHover { hovering = $0 }
                                    .gesture(resizeGesture(animation))
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if first && (hovering || localDuration != nil) {
                                Text(String(format: "%.1fs", effective))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(.systemBackground))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 4))
                                    .offset(x: 18, y: -24)
                            }
                        }
                        .offset(x: CGFloat(repeatIndex) * cycleWidth)
                }
            }
        }
        .frame(width: trackWidth, height: rowHeight)
        .overlay(alignment: .bottom) { Divider() }
        .clipped()
    }

    private func resizeGesture(_ animation: KeyframeAnimationModel) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if localDuration == nil {
                    startDuration = animation.duration
                    localDuration = animation.duration
                }
                localDuration = calculatedDuration(animation, translation: value.translation.width)
            }
            .onEnded { value in
                let final = calculatedDuration(animation, translation: value.translation.width)
                project.root.update(id: layerID) { layer in
                    guard let index = layer.animations.firstIndex(where: { $0.id == animationID }) else { return }
                    layer.animations[index].duration = final
                }
                localDuration = nil
            }
    }

    private func calculatedDuration(_ animation: KeyframeAnimationModel, translation: CGFloat) -> Double {
        let speed = animation.speed
        let deltaEffective = Double(translation / max(pxPerSecond, 0.0001))
        let delta = deltaEffective * speed
        var next = max(0.1, startDuration + delta)
        if shiftDown {
            next = max(0.1, (next * 2).rounded() / 2)
        } else {
            next = (next * 10).rounded() / 10
        }
        return next
    }

    private func durationText(_ duration: Double, speed: Double) -> String {
        let base = String(format: "%.1fs", duration)
        return speed == 1 ? base : "\(base) @ \(String(format: "%.1f", speed))x"
    }
}

private struct TimelineModifierCapture: UIViewRepresentable {
    @Binding var isShiftDown: Bool

    func makeUIView(context: Context) -> TimelineModifierView {
        let view = TimelineModifierView()
        view.onModifierChange = { value in isShiftDown = value }
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: TimelineModifierView, context: Context) {
        uiView.onModifierChange = { value in isShiftDown = value }
        if !uiView.isFirstResponder {
            DispatchQueue.main.async { _ = uiView.becomeFirstResponder() }
        }
    }
}

private final class TimelineModifierView: UIView {
    var onModifierChange: ((Bool) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        onModifierChange?(event?.modifierFlags.contains(.shift) == true)
        super.pressesBegan(presses, with: event)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        onModifierChange?(event?.modifierFlags.contains(.shift) == true)
        super.pressesChanged(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        onModifierChange?(event?.modifierFlags.contains(.shift) == true)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        onModifierChange?(false)
        super.pressesCancelled(presses, with: event)
    }
}
